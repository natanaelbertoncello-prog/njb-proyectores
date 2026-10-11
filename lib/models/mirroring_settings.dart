class MirroringSettings {
  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpness;
  final double hue;
  final double exposure;
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

  static const resolutions = ['Auto', '480p', '720p', '1080p', '2K', '4K'];
  static const codecs = ['auto', 'VP8', 'VP9', 'H264', 'AV1'];

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

  MirroringSettings({
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.sharpness = 0.0,
    this.hue = 0.0,
    this.exposure = 0.0,
    this.isAudioEnabled = true,
    this.isAntiScreensaverEnabled = true,
    this.resolution = 'Auto',
    this.fps = 30,
    this.codec = 'H264',
  });

  MirroringSettings copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? sharpness,
    double? hue,
    double? exposure,
    bool? isAudioEnabled,
    bool? isAntiScreensaverEnabled,
    String? resolution,
    int? fps,
    String? codec,
  }) {
    return MirroringSettings(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      sharpness: sharpness ?? this.sharpness,
      hue: hue ?? this.hue,
      exposure: exposure ?? this.exposure,
      isAudioEnabled: isAudioEnabled ?? this.isAudioEnabled,
      isAntiScreensaverEnabled: isAntiScreensaverEnabled ?? this.isAntiScreensaverEnabled,
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      codec: codec ?? this.codec,
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
      'isAudioEnabled': isAudioEnabled,
      'isAntiScreensaverEnabled': isAntiScreensaverEnabled,
      'resolution': resolution,
      'fps': fps,
      'codec': codec,
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
      isAudioEnabled: map['isAudioEnabled'] ?? true,
      isAntiScreensaverEnabled: map['isAntiScreensaverEnabled'] ?? true,
      resolution: map['resolution'] ?? 'Auto',
      fps: (map['fps'] ?? 30).toInt(),
      codec: map['codec'] ?? 'H264',
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
