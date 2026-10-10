import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/app_config.dart';
import '../core/app_version.dart';
import '../models/mirroring_settings.dart';

typedef OnRemoteStream = void Function(MediaStream stream);
typedef OnSettingsUpdated = void Function(MirroringSettings settings);
typedef OnDisconnected = void Function(String reason);
typedef OnPeerInfo = void Function(PeerInfo info);

/// Datos que cada extremo envía al conectarse (`hello`).
class PeerInfo {
  final String name;
  final String version;
  final String platform;

  const PeerInfo({required this.name, required this.version, required this.platform});

  Map<String, dynamic> toMap() => {'name': name, 'version': version, 'platform': platform};

  factory PeerInfo.fromMap(Map<dynamic, dynamic> map) => PeerInfo(
        name: (map['name'] ?? '?').toString(),
        version: (map['version'] ?? '?').toString(),
        platform: (map['platform'] ?? '?').toString(),
      );
}

/// Señalización WebRTC sobre WebSocket dentro de la LAN.
///
/// - El receptor abre un servidor HTTP en [AppConfig.signalingPort]:
///   `GET /info` identifica al receptor y cualquier otra ruta acepta WebSocket.
/// - El emisor se conecta por WebSocket, manda `hello` + `offer` y recibe `answer`.
class SignalingService {
  RTCPeerConnection? _pc;
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  HttpServer? _server;
  Timer? _disconnectGrace;
  bool _disposed = false;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  /// Se dispara una sola vez cuando la conexión se pierde o el otro lado cierra.
  OnDisconnected? onDisconnected;

  /// Se dispara al recibir el `hello` del otro extremo.
  OnPeerInfo? onPeerInfo;

  PeerInfo? remotePeer;

  RTCPeerConnection? get peerConnection => _pc;
  bool get hasPeer => _pc != null;

  static const Map<String, dynamic> _rtcConfig = {
    // Sin STUN/TURN: emisor y receptor están en la misma LAN, así que los
    // candidatos "host" alcanzan y no dependemos de tener internet.
    'iceServers': <Map<String, String>>[],
    'sdpSemantics': 'unified-plan',
  };

  static Future<Map<String, dynamic>> localInfo() async {
    final version = await CurrentVersion.get();
    return {
      'app': 'njb-proyectores',
      'name': AppConfig.receiverServiceName,
      'version': version.withBuild,
      'platform': Platform.operatingSystem,
      'port': AppConfig.signalingPort,
    };
  }

  static Future<PeerInfo> _localPeer() async {
    final info = await localInfo();
    return PeerInfo(name: info['name'], version: info['version'], platform: info['platform']);
  }

  // ---------------------------------------------------------------------------
  // RECEPTOR (servidor)
  // ---------------------------------------------------------------------------

  Future<void> startServer({
    required OnRemoteStream onRemoteStream,
    required OnSettingsUpdated onSettings,
  }) async {
    final wsHandler = webSocketHandler((WebSocketChannel ws, String? protocol) {
      _attachServerChannel(ws, onRemoteStream, onSettings);
    });

    Future<Response> handler(Request request) async {
      if (request.method == 'GET' && request.url.path == 'info') {
        return Response.ok(
          jsonEncode(await localInfo()),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'access-control-allow-origin': '*',
          },
        );
      }
      return await wsHandler(request);
    }

    // 0.0.0.0: escucha en Wi-Fi y Ethernet a la vez.
    _server = await io.serve(handler, InternetAddress.anyIPv4, AppConfig.signalingPort, shared: true);
    debugPrint('Receptor escuchando en 0.0.0.0:${AppConfig.signalingPort}');
  }

  Future<void> _attachServerChannel(
    WebSocketChannel ws,
    OnRemoteStream onRemoteStream,
    OnSettingsUpdated onSettings,
  ) async {
    // Si ya había un emisor, lo reemplazamos limpiamente por el nuevo.
    await _closePeer();
    await _closeChannel();

    _channel = ws;
    remotePeer = null;
    _send({'type': 'hello', 'peer': (await _localPeer()).toMap()});

    _channelSub = ws.stream.listen(
      (message) => _onServerMessage(message, onRemoteStream, onSettings),
      onError: (e) => _handleDisconnect('Error de conexión: $e'),
      onDone: () => _handleDisconnect('El emisor cerró la conexión'),
      cancelOnError: true,
    );
  }

  Future<void> _onServerMessage(dynamic message, OnRemoteStream onRemoteStream, OnSettingsUpdated onSettings) async {
    final data = _decode(message);
    if (data == null) return;

    try {
      switch (data['type']) {
        case 'hello':
          remotePeer = PeerInfo.fromMap(data['peer'] ?? {});
          onPeerInfo?.call(remotePeer!);
        case 'offer':
          await _closePeer();
          _pc = await createPeerConnection(_rtcConfig);
          _wirePeerEvents();
          _pc!.onTrack = (RTCTrackEvent event) {
            if (event.streams.isNotEmpty) onRemoteStream(event.streams[0]);
          };
          await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
          _remoteDescriptionSet = true;
          await _flushCandidates();
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          _send({'type': 'answer', 'sdp': answer.sdp});
        case 'candidate':
          await _addCandidate(data['candidate']);
        case 'settings_update':
          onSettings(MirroringSettings.fromMap(Map<String, dynamic>.from(data['settings'])));
        case 'bye':
          _handleDisconnect('El emisor detuvo la transmisión');
      }
    } catch (e) {
      debugPrint('Error procesando mensaje de señalización: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // EMISOR (cliente)
  // ---------------------------------------------------------------------------

  Future<void> connectToReceiver(String receiverIp, MediaStream localStream, MirroringSettings settings) async {
    await _closePeer();
    await _closeChannel();

    final uri = Uri.parse('ws://$receiverIp:${AppConfig.signalingPort}/ws');
    _channel = WebSocketChannel.connect(uri);
    try {
      await _channel!.ready.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw Exception('El receptor $receiverIp no respondió. ¿Está abierto el modo receptor?');
    } catch (e) {
      throw Exception('No se pudo conectar con $receiverIp: $e');
    }

    _send({'type': 'hello', 'peer': (await _localPeer()).toMap()});

    _pc = await createPeerConnection(_rtcConfig);
    _wirePeerEvents();

    for (final track in localStream.getTracks()) {
      final sender = await _pc!.addTrack(track, localStream);
      if (track.kind == 'video') {
        await setVideoBitrate(sender, settings.resolution);
      } else if (track.kind == 'audio') {
        await _setAudioBitrate(sender);
      }
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp});

    _channelSub = _channel!.stream.listen(
      _onClientMessage,
      onError: (e) => _handleDisconnect('Error de conexión: $e'),
      onDone: () => _handleDisconnect('El receptor cerró la conexión'),
      cancelOnError: true,
    );
  }

  Future<void> _onClientMessage(dynamic message) async {
    final data = _decode(message);
    if (data == null) return;
    try {
      switch (data['type']) {
        case 'hello':
          remotePeer = PeerInfo.fromMap(data['peer'] ?? {});
          onPeerInfo?.call(remotePeer!);
        case 'answer':
          await _pc?.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
          _remoteDescriptionSet = true;
          await _flushCandidates();
        case 'candidate':
          await _addCandidate(data['candidate']);
        case 'bye':
          _handleDisconnect('El receptor cerró la sesión');
      }
    } catch (e) {
      debugPrint('Error procesando mensaje de señalización: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Común
  // ---------------------------------------------------------------------------

  void _wirePeerEvents() {
    final pc = _pc!;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send({'type': 'candidate', 'candidate': candidate.toMap()});
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      // Eventos de una conexión vieja (ya reemplazada) se ignoran.
      if (!identical(_pc, pc)) return;
      debugPrint('WebRTC: $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _disconnectGrace?.cancel();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Puede ser transitorio: damos unos segundos antes de darlo por perdido.
          _disconnectGrace?.cancel();
          _disconnectGrace = Timer(const Duration(seconds: 6), () {
            _handleDisconnect('Se perdió la conexión de video');
          });
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _handleDisconnect('Falló la conexión de video');
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _handleDisconnect('La conexión de video se cerró');
        default:
          break;
      }
    };
  }

  Future<void> _addCandidate(dynamic raw) async {
    if (raw is! Map) return;
    final candidate = RTCIceCandidate(raw['candidate'], raw['sdpMid'], raw['sdpMLineIndex']);
    if (_pc == null || !_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _pc!.addCandidate(candidate);
  }

  Future<void> _flushCandidates() async {
    for (final c in _pendingCandidates) {
      try {
        await _pc?.addCandidate(c);
      } catch (e) {
        debugPrint('Candidato ICE rechazado: $e');
      }
    }
    _pendingCandidates.clear();
  }

  Map<String, dynamic>? _decode(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('No se pudo enviar mensaje de señalización: $e');
    }
  }

  bool _disconnectNotified = false;
  void _handleDisconnect(String reason) {
    if (_disposed || _disconnectNotified) return;
    _disconnectNotified = true;
    _disconnectGrace?.cancel();
    debugPrint('Señalización: $reason');
    onDisconnected?.call(reason);
  }

  /// (scaleDownFactor, maxBitrate, minBitrate) para cada resolución.
  static (double, int, int) _encodingParamsForResolution(String resolution) {
    switch (resolution) {
      case '4K':
        return (1.0, 12000000, 6000000);
      case '2K':
        return (1.0, 8000000, 4000000);
      case '1080p':
        return (1.0, 5000000, 2500000);
      case '720p':
        return (1.5, 3000000, 1200000);
      default:
        return (2.25, 1500000, 500000); // 480p
    }
  }

  Future<void> setVideoBitrate(RTCRtpSender sender, String resolution) async {
    try {
      final params = sender.parameters;
      if (params.encodings != null && params.encodings!.isNotEmpty) {
        final (scaleDown, maxBitrate, minBitrate) = _encodingParamsForResolution(resolution);
        for (final encoding in params.encodings!) {
          encoding.scaleResolutionDownBy = scaleDown;
          encoding.maxBitrate = maxBitrate;
          encoding.minBitrate = minBitrate;
        }
        await sender.setParameters(params);
      }
    } catch (e) {
      debugPrint('No se pudieron aplicar parámetros de video: $e');
    }
  }

  Future<void> _setAudioBitrate(RTCRtpSender sender) async {
    try {
      final params = sender.parameters;
      if (params.encodings != null) {
        for (final encoding in params.encodings!) {
          encoding.maxBitrate = 510000;
        }
        await sender.setParameters(params);
      }
    } catch (e) {
      debugPrint('No se pudieron aplicar parámetros de audio: $e');
    }
  }

  void updateSettings(MirroringSettings settings) {
    _send({'type': 'settings_update', 'settings': settings.toMap()});
    _pc?.getSenders().then((senders) {
      for (final sender in senders) {
        if (sender.track?.kind == 'video') setVideoBitrate(sender, settings.resolution);
      }
    });
  }

  Future<void> _closePeer() async {
    _disconnectGrace?.cancel();
    final pc = _pc;
    _pc = null;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    if (pc != null) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
  }

  Future<void> _closeChannel() async {
    await _channelSub?.cancel();
    _channelSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.sink.close();
      } catch (_) {}
    }
    _disconnectNotified = false;
  }

  /// Avisa al otro extremo y libera todo.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _send({'type': 'bye'});
    await _closePeer();
    await _closeChannel();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }
}
