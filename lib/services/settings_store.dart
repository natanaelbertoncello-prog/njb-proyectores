import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mirroring_settings.dart';

/// Guarda en el equipo los ajustes y preferencias para que sobrevivan a los
/// reinicios. Las claves con prefijo `flutter.` también las lee el código
/// nativo (BootReceiver.kt) para saber si arrancar como receptor.
class SettingsStore {
  SettingsStore._();

  static const _kSettings = 'mirroringSettings';
  static const _kAutoReceiver = 'autoReceiver';
  static const _kLastReceiverIp = 'lastReceiverIp';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  static Future<MirroringSettings> loadSettings() async {
    try {
      final raw = (await _p).getString(_kSettings);
      if (raw != null) return MirroringSettings.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('No se pudieron leer los ajustes guardados: $e');
    }
    return MirroringSettings();
  }

  static Future<void> saveSettings(MirroringSettings settings) async {
    try {
      await (await _p).setString(_kSettings, jsonEncode(settings.toMap()));
    } catch (e) {
      debugPrint('No se pudieron guardar los ajustes: $e');
    }
  }

  /// "Este equipo es el proyector": abrir directamente el modo receptor.
  static Future<bool> getAutoReceiver() async {
    try {
      return (await _p).getBool(_kAutoReceiver) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoReceiver(bool value) async {
    try {
      await (await _p).setBool(_kAutoReceiver, value);
    } catch (_) {}
  }

  static Future<String?> getLastReceiverIp() async {
    try {
      return (await _p).getString(_kLastReceiverIp);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setLastReceiverIp(String ip) async {
    try {
      await (await _p).setString(_kLastReceiverIp, ip);
    } catch (_) {}
  }
}
