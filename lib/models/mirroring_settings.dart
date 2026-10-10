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
  final String codec;

  static const resolutions = ['Auto', '480p', '720p', '1080p', '2K', '4K'];
  static const codecs = ['auto', 'VP8', 'VP9', 'H264', 'AV1'];

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
    this.codec = 'auto',
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
      codec: map['codec'] ?? 'auto',
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
