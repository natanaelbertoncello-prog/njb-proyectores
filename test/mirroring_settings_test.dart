import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:proyectar/models/mirroring_settings.dart';

void main() {
  group('MirroringSettings', () {
    test('sobrevive un viaje de ida y vuelta por JSON', () {
      final original = MirroringSettings(
        brightness: 1.3,
        contrast: 0.8,
        saturation: 1.1,
        sharpness: 0.4,
        hue: -0.5,
        exposure: 0.25,
        isAudioEnabled: false,
        isAntiScreensaverEnabled: true,
        resolution: '720p',
        fps: 60,
      );

      final restored = MirroringSettings.fromMap(
        jsonDecode(jsonEncode(original.toMap())) as Map<String, dynamic>,
      );

      expect(restored.brightness, original.brightness);
      expect(restored.contrast, original.contrast);
      expect(restored.saturation, original.saturation);
      expect(restored.sharpness, original.sharpness);
      expect(restored.hue, original.hue);
      expect(restored.exposure, original.exposure);
      expect(restored.isAudioEnabled, original.isAudioEnabled);
      expect(restored.isAntiScreensaverEnabled, original.isAntiScreensaverEnabled);
      expect(restored.resolution, original.resolution);
      expect(restored.fps, original.fps);
    });

    test('usa valores por defecto si faltan campos (emisor viejo)', () {
      final restored = MirroringSettings.fromMap({'resolution': '480p'});
      expect(restored.resolution, '480p');
      expect(restored.fps, 30);
      expect(restored.isAudioEnabled, isTrue);
      expect(restored.brightness, 1.0);
    });
  });
}
