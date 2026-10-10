import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/signaling_service.dart';
import '../models/mirroring_settings.dart';
import 'app_config.dart';

enum MirroringStatus { idle, connecting, mirroring, error }

class MirroringState {
  final MirroringStatus status;
  final RTCVideoRenderer? localRenderer;
  final String? errorMessage;
  final MirroringSettings settings;
  final DesktopCapturerSource? lastSource;
  final String? lastReceiverIp;

  /// Datos del receptor conectado (nombre, versión).
  final PeerInfo? receiverPeer;

  /// Mensaje informativo (por ejemplo "Reconectando 2/5").
  final String? statusMessage;

  MirroringState({
    this.status = MirroringStatus.idle,
    this.localRenderer,
    this.errorMessage,
    MirroringSettings? settings,
    this.lastSource,
    this.lastReceiverIp,
    this.receiverPeer,
    this.statusMessage,
  }) : settings = settings ?? MirroringSettings();

  MirroringState copyWith({
    MirroringStatus? status,
    RTCVideoRenderer? localRenderer,
    String? errorMessage,
    MirroringSettings? settings,
    DesktopCapturerSource? lastSource,
    String? lastReceiverIp,
    PeerInfo? receiverPeer,
    String? statusMessage,
    bool clearError = false,
    bool clearPeer = false,
  }) {
    return MirroringState(
      status: status ?? this.status,
      localRenderer: localRenderer ?? this.localRenderer,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      settings: settings ?? this.settings,
      lastSource: lastSource ?? this.lastSource,
      lastReceiverIp: lastReceiverIp ?? this.lastReceiverIp,
      receiverPeer: clearPeer ? null : (receiverPeer ?? this.receiverPeer),
      statusMessage: statusMessage,
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

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

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

      final quality = _getQualityDimensions();
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

      state = state.copyWith(statusMessage: 'Capturando pantalla…');
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
    await signaling.connectToReceiver(ip, _localStream!, state.settings);
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

  Map<String, int> _getQualityDimensions() {
    switch (state.settings.resolution) {
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

    _signaling?.updateSettings(newSettings);

    final stream = _localStream;
    if (stream == null) return;

    for (final track in stream.getAudioTracks()) {
      track.enabled = newSettings.isAudioEnabled;
    }

    if (oldSettings.fps != newSettings.fps) {
      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        try {
          await videoTracks.first.applyConstraints({'frameRate': newSettings.fps});
        } catch (_) {
          // Algunos drivers de escritorio necesitan reiniciar la captura.
          // En Android no lo hacemos: volvería a pedir permiso al usuario.
          if (!_isAndroid && state.status == MirroringStatus.mirroring) {
            await startMirroring(source: state.lastSource, receiverIp: state.lastReceiverIp);
          }
        }
      }
    }
  }

  Future<void> _teardownStream() async {
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
