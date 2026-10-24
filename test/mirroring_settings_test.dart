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
      expect(restored.temperature, 0.0);
    });

    test('la temperatura sobrevive el viaje por JSON', () {
      final restored = MirroringSettings.fromMap(
        jsonDecode(jsonEncode(MirroringSettings(temperature: 0.4).toMap())) as Map<String, dynamic>,
      );
      expect(restored.temperature, 0.4);
    });
  });

  group('colorMatrix', () {
    // Aplica una matriz 4x5 a un color RGB opaco (escala 0–255).
    List<double> apply(List<double> m, List<double> rgb) => [
          for (var r = 0; r < 3; r++)
            m[r * 5] * rgb[0] + m[r * 5 + 1] * rgb[1] + m[r * 5 + 2] * rgb[2] + m[r * 5 + 3] * 255 + m[r * 5 + 4],
        ];

    test('en neutro es la identidad', () {
      final s = MirroringSettings();
      expect(s.isColorNeutral, isTrue);
      final out = apply(s.colorMatrix(), [10, 128, 240]);
      expect(out[0], closeTo(10, 1e-6));
      expect(out[1], closeTo(128, 1e-6));
      expect(out[2], closeTo(240, 1e-6));
    });

    test('el contraste no mueve el gris medio', () {
      final out = apply(MirroringSettings(contrast: 1.6).colorMatrix(), [127.5, 127.5, 127.5]);
      for (final v in out) {
        expect(v, closeTo(127.5, 1e-6));
      }
    });

    test('combina contraste y brillo en el orden correcto', () {
      // Contraste 2 y después brillo 0.5: 200 → 272.5 → 136.25, sin recortar en el medio.
      final out = apply(MirroringSettings(contrast: 2, brightness: 0.5).colorMatrix(), [200, 200, 200]);
      expect(out[0], closeTo(136.25, 1e-6));
    });

    test('cálido baja el azul y frío baja el rojo', () {
      final warm = apply(MirroringSettings(temperature: 1).colorMatrix(), [200, 200, 200]);
      expect(warm[2], lessThan(200));
      expect(warm[0], greaterThan(200));
      final cool = apply(MirroringSettings(temperature: -1).colorMatrix(), [200, 200, 200]);
      expect(cool[0], lessThan(200));
      expect(cool[2], greaterThan(200));
    });

    test('reconoce los perfiles de color', () {
      final p = MirroringSettings.colorPresets['CÁLIDO']!;
      final s = MirroringSettings(
        brightness: p.brightness,
        contrast: p.contrast,
        saturation: p.saturation,
        temperature: p.temperature,
      );
      expect(s.activeColorPreset, 'CÁLIDO');
      expect(MirroringSettings().activeColorPreset, 'NATURAL');
      expect(MirroringSettings(hue: 0.3).activeColorPreset, isNull);
    });
  });
}
