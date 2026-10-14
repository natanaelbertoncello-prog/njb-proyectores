import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';

/// Recibe lo que otras apps "comparten" con NJB Proyectores (Android):
/// un link de YouTube desde Chrome, una página, etc.
class ShareService {
  ShareService._();

  static const _channel = MethodChannel(AppConfig.shareChannel);
  static final _controller = StreamController<String>.broadcast();
  static bool _initialized = false;

  /// Links o textos compartidos mientras la app ya estaba abierta.
  static Stream<String> get stream => _controller.stream;

  static Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments?.toString();
        if (text != null && text.isNotEmpty) _controller.add(text);
      }
    });
  }

  /// Texto compartido con el que se abrió la app (si lo hubo). Se consume una vez.
  static Future<String?> takeInitial() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getSharedText');
    } catch (_) {
      return null;
    }
  }

  /// Extrae la primera URL de un texto compartido ("Mirá esto https://…").
  static String? extractUrl(String text) {
    final match = RegExp(r'https?://[^\s<>"]+', caseSensitive: false).firstMatch(text);
    return match?.group(0);
  }
}
