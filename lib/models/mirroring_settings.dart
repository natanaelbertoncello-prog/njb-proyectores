import 'dart:math' as math;

class MirroringSettings {
  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpness;
  final double hue;
  final double exposure;

  /// Balance de blancos, de -1 (más frío/azul) a 1 (más cálido/amarillo).
  final double temperature;
  final bool isAudioEnabled;
  final bool isAntiScreensaverEnabled;

  /// 'Auto' (según la pantalla del receptor), '480p', '720p', '1080p', '2K', '4K'.
  final String resolution;
  final int fps;

  /// Códec de video preferido: 'auto', 'VP8', 'VP9', 'H264' o 'AV1'.
  ///
  /// Por defecto H264: es el único que los proyectores Android decodifican
  /// por hardware con seguridad. Con VP8 (el "auto" de WebRTC) muchos
  /// proyectores decodifican por software y se traban.
  final String codec;

  /// Cómo se acomoda el video en la pantalla del proyector:
  /// 'contain' (entero, con bordes), 'cover' (llena recortando) o 'stretch' (estira).
  final String fitMode;

  static const resolutions = ['Auto', '480p', '720p', '1080p', '2K', '4K'];
  static const codecs = ['auto', 'VP8', 'VP9', 'H264', 'AV1'];
  static const fitModes = <String, ({String label, String hint})>{
    'contain': (label: 'AJUSTAR', hint: 'Se ve todo, con bordes negros si la forma no coincide (celular vertical).'),
    'cover': (label: 'RELLENAR', hint: 'Ocupa toda la pantalla recortando los bordes. Sin deformar.'),
    'stretch': (label: 'ESTIRAR', hint: 'Ocupa toda la pantalla deformando la imagen. Útil para texto grande.'),
  };

  /// Perfiles de un toque.
  static const presets = <String, ({String resolution, int fps, String codec, String hint})>{
    'TEXTO NÍTIDO': (resolution: 'Auto', fps: 15, codec: 'H264', hint: 'Planillas, PDF, presentaciones. Máxima definición por cuadro.'),
    'EQUILIBRADO': (resolution: 'Auto', fps: 30, codec: 'H264', hint: 'Uso general.'),
    'FLUIDO': (resolution: '720p', fps: 24, codec: 'H264', hint: 'Wi-Fi flojo o PC lenta: menos datos, sin cortes.'),
  };

  String? get activePreset {
    for (final e in presets.entries) {
      if (e.value.resolution == resolution && e.value.fps == fps && e.value.codec == codec) return e.key;
    }
    return null;
  }

  /// Perfiles de color de un toque (tono y exposición vuelven a 0).
  static const colorPresets =
      <String, ({double brightness, double contrast, double saturation, double temperature, String hint})>{
    'NATURAL': (brightness: 1.0, contrast: 1.0, saturation: 1.0, temperature: 0.0, hint: 'Los colores tal cual llegan, sin retoque.'),
    'VIVO': (brightness: 1.0, contrast: 1.1, saturation: 1.25, temperature: 0.0, hint: 'Más color y contraste para salas con luz.'),
    'CÁLIDO': (brightness: 1.0, contrast: 1.05, saturation: 1.05, temperature: 0.35, hint: 'Corrige el tono azulado típico de la lámpara del proyector.'),
  };

  String? get activeColorPreset {
    if (hue != 0.0 || exposure != 0.0) return null;
    for (final e in colorPresets.entries) {
      final p = e.value;
      if (p.brightness == brightness &&
          p.contrast == contrast &&
          p.saturation == saturation &&
          p.temperature == temperature) {
        return e.key;
      }
    }
    return null;
  }

  bool get isColorNeutral =>
      brightness == 1.0 && contrast == 1.0 && saturation == 1.0 && hue == 0.0 && exposure == 0.0 && temperature == 0.0;

  /// Todos los ajustes de color en una sola matriz 4x5 para [ColorFilter.matrix]
  /// (la columna de desplazamiento va en escala 0–255).
  ///
  /// Se combinan en una sola pasada a propósito: encadenar un filtro por ajuste
  /// redondea a 8 bits y recorta en cada paso, y eso lava los colores y genera
  /// saltos en los degradés. Orden: balance de blancos → saturación →
  /// contraste → brillo/exposición → tono.
  List<double> colorMatrix() {
    // Balance de blancos: al calentar se baja más el azul de lo que se sube el
    // rojo, así los blancos no se queman.
    final t = temperature;
    final rGain = t >= 0 ? 1.0 + 0.08 * t : 1.0 + 0.18 * t;
    final bGain = t >= 0 ? 1.0 - 0.18 * t : 1.0 - 0.08 * t;
    final white = <double>[
      rGain, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, bGain, 0, 0,
      0, 0, 0, 1, 0,
    ];

    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    final sr = lr * (1 - s), sg = lg * (1 - s), sb = lb * (1 - s);
    final sat = <double>[
      sr + s, sg, sb, 0, 0,
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];

    final c = contrast;
    final off = 0.5 * (1.0 - c) * 255.0;
    final con = <double>[
      c, 0, 0, 0, off,
      0, c, 0, 0, off,
      0, 0, c, 0, off,
      0, 0, 0, 1, 0,
    ];

    final b = brightness * math.pow(2.0, exposure).toDouble();
    final bri = <double>[
      b, 0, 0, 0, 0,
      0, b, 0, 0, 0,
      0, 0, b, 0, 0,
      0, 0, 0, 1, 0,
    ];

    final cosV = math.cos(hue), sinV = math.sin(hue);
    const hr = 0.213, hg = 0.715, hb = 0.072;
    final hueM = <double>[
      hr + cosV * (1 - hr) + sinV * (-hr), hg + cosV * (-hg) + sinV * (-hg), hb + cosV * (-hb) + sinV * (1 - hb), 0, 0,
      hr + cosV * (-hr) + sinV * 0.143, hg + cosV * (1 - hg) + sinV * 0.140, hb + cosV * (-hb) + sinV * (-0.283), 0, 0,
      hr + cosV * (-hr) + sinV * (-(1 - hr)), hg + cosV * (-hg) + sinV * hg, hb + cosV * (1 - hb) + sinV * hb, 0, 0,
      0, 0, 0, 1, 0,
    ];

    var m = white;
    for (final next in [sat, con, bri, hueM]) {
      m = _compose(next, m);
    }
    return m;
  }

  /// a·b como transformaciones afines 4x5: primero se aplica b, después a.
  static List<double> _compose(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var v = col == 4 ? a[row * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          v += a[row * 5 + k] * b[k * 5 + col];
        }
        out[row * 5 + col] = v;
      }
    }
    return out;
  }

  MirroringSettings({
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.sharpness = 0.0,
    this.hue = 0.0,
    this.exposure = 0.0,
    this.temperature = 0.0,
    this.isAudioEnabled = true,
    this.isAntiScreensaverEnabled = true,
    this.resolution = 'Auto',
    this.fps = 30,
    this.codec = 'H264',
    this.fitMode = 'contain',
  });

  MirroringSettings copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? sharpness,
    double? hue,
    double? exposure,
    double? temperature,
    bool? isAudioEnabled,
    bool? isAntiScreensaverEnabled,
    String? resolution,
    int? fps,
    String? codec,
    String? fitMode,
  }) {
    return MirroringSettings(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      sharpness: sharpness ?? this.sharpness,
      hue: hue ?? this.hue,
      exposure: exposure ?? this.exposure,
      temperature: temperature ?? this.temperature,
      isAudioEnabled: isAudioEnabled ?? this.isAudioEnabled,
      isAntiScreensaverEnabled: isAntiScreensaverEnabled ?? this.isAntiScreensaverEnabled,
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      codec: codec ?? this.codec,
      fitMode: fitMode ?? this.fitMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'sharpness': sharpness,
      'hue': hue,
      'exposure': exposure,
      'temperature': temperature,
      'isAudioEnabled': isAudioEnabled,
      'isAntiScreensaverEnabled': isAntiScreensaverEnabled,
      'resolution': resolution,
      'fps': fps,
      'codec': codec,
      'fitMode': fitMode,
    };
  }

  factory MirroringSettings.fromMap(Map<String, dynamic> map) {
    return MirroringSettings(
      brightness: (map['brightness'] ?? 1.0).toDouble(),
      contrast: (map['contrast'] ?? 1.0).toDouble(),
      saturation: (map['saturation'] ?? 1.0).toDouble(),
      sharpness: (map['sharpness'] ?? 0.0).toDouble(),
      hue: (map['hue'] ?? 0.0).toDouble(),
      exposure: (map['exposure'] ?? 0.0).toDouble(),
      temperature: (map['temperature'] ?? 0.0).toDouble(),
      isAudioEnabled: map['isAudioEnabled'] ?? true,
      isAntiScreensaverEnabled: map['isAntiScreensaverEnabled'] ?? true,
      resolution: map['resolution'] ?? 'Auto',
      fps: (map['fps'] ?? 30).toInt(),
      codec: map['codec'] ?? 'H264',
      fitMode: map['fitMode'] ?? 'contain',
    );
  }

  /// Resolución concreta a usar cuando está en 'Auto', según la pantalla del
  /// receptor (en píxeles físicos). Sin datos, 1080p.
  static String resolveAuto(int? receiverWidth, int? receiverHeight) {
    final h = receiverHeight ?? 0;
    final w = receiverWidth ?? 0;
    final shortSide = h < w ? h : w;
    if (shortSide <= 0) return '1080p';
    if (shortSide >= 2000) return '4K';
    if (shortSide >= 1300) return '2K';
    if (shortSide >= 1000) return '1080p';
    if (shortSide >= 700) return '720p';
    return '480p';
  }
}
