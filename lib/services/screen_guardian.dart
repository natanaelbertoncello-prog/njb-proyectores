import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';

/// Estado del "guardián de pantalla" nativo (Android).
class ScreenGuardianStatus {
  final bool running;
  final bool wakeLock;
  final bool silentAudio;
  final bool mediaSession;
  final bool inputPoke;
  final bool canWriteSecureSettings;
  final bool canWriteSystemSettings;
  final bool systemScreensaverDisabled;
  final int sdkInt;

  const ScreenGuardianStatus({
    this.running = false,
    this.wakeLock = false,
    this.silentAudio = false,
    this.mediaSession = false,
    this.inputPoke = false,
    this.canWriteSecureSettings = false,
    this.canWriteSystemSettings = false,
    this.systemScreensaverDisabled = false,
    this.sdkInt = 0,
  });

  factory ScreenGuardianStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const ScreenGuardianStatus();
    bool b(String k) => map[k] == true;
    return ScreenGuardianStatus(
      running: b('running'),
      wakeLock: b('wakeLock'),
      silentAudio: b('silentAudio'),
      mediaSession: b('mediaSession'),
      inputPoke: b('inputPoke'),
      canWriteSecureSettings: b('canWriteSecureSettings'),
      canWriteSystemSettings: b('canWriteSystemSettings'),
      systemScreensaverDisabled: b('systemScreensaverDisabled'),
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    );
  }

  /// Resumen corto para mostrar en el HUD.
  String get summary {
    if (systemScreensaverDisabled) return 'SCREENSAVER DEL SISTEMA DESACTIVADO';
    if (!running) return 'PROTECCIÓN INACTIVA';
    final parts = <String>[
      if (wakeLock) 'WAKELOCK',
      if (silentAudio) 'AUDIO',
      if (mediaSession) 'MEDIA',
      if (inputPoke) 'INPUT',
    ];
    return parts.isEmpty ? 'PROTECCIÓN ACTIVA' : 'PROTECCIÓN: ${parts.join(' + ')}';
  }
}

/// Puente hacia `ScreenGuardian.kt`. En plataformas que no son Android todos
/// los métodos son inofensivos (no hacen nada).
class ScreenGuardian {
  ScreenGuardian._();

  static const _channel = MethodChannel(AppConfig.screenGuardianChannel);

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Activa todas las capas anti-screensaver (wakelock, audio silencioso,
  /// sesión multimedia tipo YouTube y "toques" sintéticos periódicos).
  static Future<ScreenGuardianStatus> start() async {
    if (!isSupported) return const ScreenGuardianStatus();
    try {
      final result = await _channel.invokeMethod<Map>('start');
      return ScreenGuardianStatus.fromMap(result);
    } catch (e) {
      debugPrint('ScreenGuardian.start: $e');
      return const ScreenGuardianStatus();
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('ScreenGuardian.stop: $e');
    }
  }

  static Future<ScreenGuardianStatus> status() async {
    if (!isSupported) return const ScreenGuardianStatus();
    try {
      final result = await _channel.invokeMethod<Map>('status');
      return ScreenGuardianStatus.fromMap(result);
    } catch (e) {
      debugPrint('ScreenGuardian.status: $e');
      return const ScreenGuardianStatus();
    }
  }

  /// Intenta desactivar el protector de pantalla y el apagado automático a
  /// nivel sistema. Sólo funciona si la app recibió los permisos por ADB
  /// (ver `tools/configurar_proyector.ps1`). Devuelve qué ajustes se aplicaron.
  static Future<Map<String, bool>> applySystemSettings() async {
    if (!isSupported) return {};
    try {
      final result = await _channel.invokeMethod<Map>('applySystemSettings');
      return result?.map((k, v) => MapEntry(k.toString(), v == true)) ?? {};
    } catch (e) {
      debugPrint('ScreenGuardian.applySystemSettings: $e');
      return {};
    }
  }
}
