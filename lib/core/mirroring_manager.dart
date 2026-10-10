import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/discovery_service.dart';
import '../services/signaling_service.dart';
import '../models/mirroring_settings.dart';
import 'app_config.dart';

enum MirroringStatus { idle, connecting, mirroring, error }

/// Lo que realmente está saliendo hacia el receptor (WebRTC getStats).
class SenderStats {
  final int width;
  final int height;
  final int fps;
  final double bitrateMbps;
  final String codec;

  /// 'none', 'cpu', 'bandwidth' u 'other'.
  final String limitation;
  final double? rttMs;

  const SenderStats({
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.bitrateMbps = 0,
    this.codec = '',
    this.limitation = 'none',
    this.rttMs,
  });

  String get limitationLabel {
    switch (limitation) {
      case 'cpu':
        return 'LÍMITE: CPU DE LA PC';
      case 'bandwidth':
        return 'LÍMITE: RED';
      case 'other':
        return 'LÍMITE: OTRO';
      default:
        return 'SIN LÍMITE';
    }
  }

  String get summary {
    if (width == 0) return 'ENVIANDO…';
    return '${width}x$height @ ${fps}FPS • ${bitrateMbps.toStringAsFixed(1)} Mbps'
        '${codec.isNotEmpty ? ' • $codec' : ''} • $limitationLabel';
  }
}

class MirroringState {
  final MirroringStatus status;
  final RTCVideoRenderer? localRenderer;
  final String? errorMessage;
  final MirroringSettings settings;
  final DesktopCapturerSource? lastSource;
  final String? lastReceiverIp;

  /// Datos del receptor conectado (nombre, versión, pantalla).
  final PeerInfo? receiverPeer;

  /// Resolución concreta en uso (resuelve 'Auto').
  final String effectiveResolution;

  /// Mensaje informativo (por ejemplo "Reconectando 2/5").
  final String? statusMessage;

  final SenderStats? stats;

  MirroringState({
    this.status = MirroringStatus.idle,
    this.localRenderer,
    this.errorMessage,
    MirroringSettings? settings,
    this.lastSource,
    this.lastReceiverIp,
    this.receiverPeer,
    this.effectiveResolution = '1080p',
    this.statusMessage,
    this.stats,
  }) : settings = settings ?? MirroringSettings();

  MirroringState copyWith({
    MirroringStatus? status,
    RTCVideoRenderer? localRenderer,
    String? errorMessage,
    MirroringSettings? settings,
    DesktopCapturerSource? lastSource,
    String? lastReceiverIp,
    PeerInfo? receiverPeer,
    String? effectiveResolution,
    String? statusMessage,
    SenderStats? stats,
    bool clearError = false,
    bool clearPeer = false,
    bool clearStats = false,
  }) {
    return MirroringState(
      status: status ?? this.status,
      localRenderer: localRenderer ?? this.localRenderer,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      settings: settings ?? this.settings,
      lastSource: lastSource ?? this.lastSource,
      lastReceiverIp: lastReceiverIp ?? this.lastReceiverIp,
      receiverPeer: clearPeer ? null : (receiverPeer ?? this.receiverPeer),
      effectiveResolution: effectiveResolution ?? this.effectiveResolution,
      statusMessage: statusMessage,
      stats: clearStats ? null : (stats ?? this.stats),
    );
  }
}

final mirroringProvider = StateNotifierProvider<MirroringManager, MirroringState>((ref) {
  return MirroringManager();
});

/// Lado emisor: captura la pantalla y la envía al receptor elegido.
class MirroringManager extends StateNotifier<MirroringState> {
  MirroringManager() : super(MirroringState());

  static const _serviceChannel = MethodChannel(AppConfig.serviceChannel);
  static const _maxReconnectAttempts = 5;

  MediaStream? _localStream;
  SignalingService? _signaling;
  bool _stopping = false;
  int _session = 0;
  Timer? _statsTimer;
  double _prevBytesSent = 0;
  DateTime? _prevStatsTime;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Ajustes tal como se envían al receptor y al codificador (sin 'Auto').
  MirroringSettings get _effectiveSettings => state.settings.copyWith(resolution: state.effectiveResolution);

  Future<void> _stopNativeService() async {
    if (!_isAndroid) return;
    try {
      await _serviceChannel.invokeMethod('stopService');
    } catch (e) {
      debugPrint('Error al detener el servicio nativo: $e');
    }
  }

  Future<void> startMirroring({DesktopCapturerSource? source, String? receiverIp}) async {
    if (state.status == MirroringStatus.mirroring && source == null && receiverIp == null) return;

    final selectedSource = source ?? state.lastSource;
    final targetIp = receiverIp ?? state.lastReceiverIp;
    final session = ++_session;
    _stopping = false;

    state = state.copyWith(
      status: MirroringStatus.connecting,
      lastSource: selectedSource,
      lastReceiverIp: targetIp,
      clearError: true,
      clearPeer: true,
      clearStats: true,
      statusMessage: 'Preparando captura…',
    );

    try {
      // Si ya había una captura activa (cambio de fuente), se libera ANTES de
      // pedir la nueva. Antes se hacía después y en Android mataba el servicio
      // en primer plano recién iniciado.
      await _teardownStream();

      try {
        await WakelockPlus.enable();
      } catch (e) {
        debugPrint('Wakelock: $e');
      }

      // Resolución 'Auto': preguntamos al receptor el tamaño de su pantalla
      // antes de capturar, para mandar exactamente lo que puede mostrar.
      String effective = state.settings.resolution;
      if (effective == 'Auto') {
        ReceiverInfo? info;
        if (targetIp != null && targetIp.isNotEmpty) {
          info = await DiscoveryService.probeReceiver(targetIp, timeout: const Duration(seconds: 2));
        }
        effective = MirroringSettings.resolveAuto(info?.screenWidth, info?.screenHeight);
      }
      if (session != _session) return;
      state = state.copyWith(effectiveResolution: effective, statusMessage: 'Capturando en $effective…');

      // Android 14+: el servicio en primer plano de tipo mediaProjection tiene
      // que estar corriendo antes de capturar.
      if (_isAndroid) {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
        final bool ok = await _serviceChannel.invokeMethod('startMirroringFlow') ?? false;
        if (!ok) {
          state = state.copyWith(
            status: MirroringStatus.idle,
            errorMessage: 'Permiso de captura de pantalla denegado',
            statusMessage: null,
          );
          return;
        }
      }

      final quality = _getQualityDimensions(effective);
      final Map<String, dynamic> mediaConstraints = {
        'audio': state.settings.isAudioEnabled,
        'video': (selectedSource != null)
            ? {
                'mandatory': {
                  'chromeMediaSource': selectedSource.id.contains('screen') ? 'screen' : 'window',
                  'chromeMediaSourceId': selectedSource.id,
                  'maxWidth': quality['width'].toString(),
                  'maxHeight': quality['height'].toString(),
                  'maxFrameRate': state.settings.fps.toString(),
                },
                'optional': [],
              }
            : {
                'width': {'ideal': quality['width']},
                'height': {'ideal': quality['height']},
                'frameRate': {'ideal': state.settings.fps},
              }
      };

      final stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      if (session != _session) {
        // Se pidió otra captura mientras esperábamos: descartamos esta.
        for (final t in stream.getTracks()) {
          t.stop();
        }
        await stream.dispose();
        return;
      }
      _localStream = stream;

      for (final track in stream.getVideoTracks()) {
        // El usuario cortó la captura desde el sistema (barra de Windows, etc.)
        track.onEnded = () => stopMirroring();
      }

      if (targetIp != null && targetIp.isNotEmpty) {
        state = state.copyWith(statusMessage: 'Conectando con $targetIp…');
        await _connect(targetIp);
      }

      final renderer = state.localRenderer ?? RTCVideoRenderer();
      if (state.localRenderer == null) {
        await renderer.initialize();
      }
      renderer.srcObject = _localStream;

      state = state.copyWith(
        status: MirroringStatus.mirroring,
        localRenderer: renderer,
        clearError: true,
        statusMessage: null,
      );
      _startStatsTimer();
    } catch (e) {
      debugPrint('Error en startMirroring: $e');
      await _teardownStream();
      await _stopNativeService();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      state = state.copyWith(
        status: MirroringStatus.error,
        errorMessage: _friendlyError(e),
        statusMessage: null,
      );
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '');
    if (text.contains('NotAllowedError') || text.contains('permission')) {
      return 'No se autorizó la captura de pantalla.';
    }
    return text;
  }

  Future<void> _connect(String ip) async {
    final signaling = SignalingService();
    signaling.onPeerInfo = (peer) {
      if (identical(_signaling, signaling)) {
        state = state.copyWith(receiverPeer: peer, statusMessage: state.statusMessage);
      }
    };
    signaling.onDisconnected = (reason) {
      if (identical(_signaling, signaling)) _onReceiverLost(reason);
    };
    _signaling = signaling;
    _prevBytesSent = 0;
    _prevStatsTime = null;
    await signaling.connectToReceiver(ip, _localStream!, _effectiveSettings);
  }

  /// El receptor se cayó: intentamos reconectar reutilizando la captura actual.
  Future<void> _onReceiverLost(String reason) async {
    if (_stopping || _localStream == null) return;
    final session = _session;
    final ip = state.lastReceiverIp;

    await _signaling?.dispose();
    _signaling = null;

    if (ip == null) {
      state = state.copyWith(status: MirroringStatus.error, errorMessage: reason, statusMessage: null);
      return;
    }

    for (int attempt = 1; attempt <= _maxReconnectAttempts; attempt++) {
      if (_stopping || _localStream == null || session != _session) return;
      state = state.copyWith(
        status: MirroringStatus.connecting,
        statusMessage: 'Se perdió el receptor. Reconectando ($attempt/$_maxReconnectAttempts)…',
      );
      await Future.delayed(const Duration(seconds: 3));
      if (_stopping || _localStream == null || session != _session) return;
      try {
        await _connect(ip);
        state = state.copyWith(status: MirroringStatus.mirroring, clearError: true, statusMessage: null);
        return;
      } catch (e) {
        debugPrint('Reconexión $attempt falló: $e');
      }
    }

    if (session == _session) {
      state = state.copyWith(
        status: MirroringStatus.error,
        errorMessage: 'No se pudo reconectar con el receptor ($reason).',
        statusMessage: null,
      );
    }
  }

  /// Cambio de códec en vivo: se renegocia la conexión sin volver a capturar.
  Future<void> _renegotiate() async {
    final ip = state.lastReceiverIp;
    if (ip == null || _localStream == null || _stopping) return;
    final session = _session;
    state = state.copyWith(status: MirroringStatus.connecting, statusMessage: 'Aplicando códec ${state.settings.codec}…');
    await _signaling?.dispose();
    _signaling = null;
    try {
      await _connect(ip);
      if (session == _session) {
        state = state.copyWith(status: MirroringStatus.mirroring, clearError: true, clearStats: true, statusMessage: null);
      }
    } catch (e) {
      if (session == _session) {
        state = state.copyWith(status: MirroringStatus.error, errorMessage: 'No se pudo renegociar: $e', statusMessage: null);
      }
    }
  }

  Map<String, int> _getQualityDimensions(String resolution) {
    switch (resolution) {
      case '4K':
        return {'width': 3840, 'height': 2160};
      case '2K':
        return {'width': 2560, 'height': 1440};
      case '720p':
        return {'width': 1280, 'height': 720};
      case '480p':
        return {'width': 854, 'height': 480};
      default:
        return {'width': 1920, 'height': 1080};
    }
  }

  Future<void> updateSettings(MirroringSettings newSettings) async {
    final oldSettings = state.settings;
    state = state.copyWith(settings: newSettings, statusMessage: state.statusMessage);

    final stream = _localStream;
    final live = stream != null && state.status == MirroringStatus.mirroring;

    // Resolución o FPS: en escritorio se reinicia la captura (sin pedir
    // permiso). En Android no: volvería a mostrar el diálogo del sistema.
    final captureChanged = oldSettings.resolution != newSettings.resolution || oldSettings.fps != newSettings.fps;
    if (live && captureChanged && !_isAndroid) {
      await startMirroring(source: state.lastSource, receiverIp: state.lastReceiverIp);
      return;
    }

    _signaling?.updateSettings(_effectiveSettings);

    if (stream == null) return;

    for (final track in stream.getAudioTracks()) {
      track.enabled = newSettings.isAudioEnabled;
    }

    if (live && oldSettings.codec != newSettings.codec) {
      await _renegotiate();
    }
  }

  // ---------------------------------------------------------------------------
  // Estadísticas de envío
  // ---------------------------------------------------------------------------

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _collectStats());
  }

  Future<void> _collectStats() async {
    final pc = _signaling?.peerConnection;
    if (pc == null || state.status != MirroringStatus.mirroring) return;

    List<StatsReport> reports;
    try {
      reports = await pc.getStats();
    } catch (_) {
      return;
    }

    int width = 0, height = 0, fps = 0;
    double? bytesSent;
    String limitation = 'none';
    String? codecId;
    double? rttMs;
    final codecs = <String, String>{};

    for (final r in reports) {
      if (r.type == 'codec') {
        codecs[r.id] = (r.values['mimeType'] ?? '').toString();
      } else if (r.type == 'outbound-rtp' && r.values['kind'] == 'video') {
        width = _asInt(r.values['frameWidth']);
        height = _asInt(r.values['frameHeight']);
        fps = _asInt(r.values['framesPerSecond']);
        bytesSent = _asDouble(r.values['bytesSent']);
        limitation = (r.values['qualityLimitationReason'] ?? 'none').toString();
        codecId = r.values['codecId']?.toString();
      } else if (r.type == 'candidate-pair' &&
          r.values['state'] == 'succeeded' &&
          r.values['currentRoundTripTime'] != null) {
        rttMs = (_asDouble(r.values['currentRoundTripTime']) ?? 0) * 1000;
      }
    }

    final now = DateTime.now();
    double bitrate = state.stats?.bitrateMbps ?? 0;
    if (bytesSent != null && _prevStatsTime != null) {
      final seconds = now.difference(_prevStatsTime!).inMilliseconds / 1000;
      if (seconds > 0) bitrate = ((bytesSent - _prevBytesSent) * 8) / seconds / 1000000;
    }
    if (bytesSent != null) {
      _prevBytesSent = bytesSent;
      _prevStatsTime = now;
    }

    final codec = codecId != null ? (codecs[codecId] ?? '').replaceFirst('video/', '') : '';

    if (state.status == MirroringStatus.mirroring) {
      state = state.copyWith(
        stats: SenderStats(
          width: width,
          height: height,
          fps: fps,
          bitrateMbps: bitrate < 0 ? 0 : bitrate,
          codec: codec,
          limitation: limitation,
          rttMs: rttMs,
        ),
        statusMessage: state.statusMessage,
      );
    }
  }

  static int _asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);
  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // ---------------------------------------------------------------------------

  Future<void> _teardownStream() async {
    _statsTimer?.cancel();
    _statsTimer = null;

    final signaling = _signaling;
    _signaling = null;
    await signaling?.dispose();

    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
  }

  Future<void> stopMirroring({bool resetState = true}) async {
    _stopping = true;
    _session++;
    await _stopNativeService();
    try {
      await WakelockPlus.disable();
    } catch (_) {}

    await _teardownStream();

    if (resetState) {
      final renderer = state.localRenderer;
      if (renderer != null) {
        renderer.srcObject = null;
        await renderer.dispose();
      }
      state = MirroringState(settings: state.settings, lastReceiverIp: state.lastReceiverIp, lastSource: state.lastSource);
    }
  }

  @override
  void dispose() {
    stopMirroring();
    super.dispose();
  }
}
