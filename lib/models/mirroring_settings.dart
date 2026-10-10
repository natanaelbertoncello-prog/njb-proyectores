class MirroringSettings {
  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpness;
  final double hue; // New: Tono/Matiz
  final double exposure; // New: Exposición Digital
  final bool isAudioEnabled;
  final bool isAntiScreensaverEnabled; // Matar screensaver de proyectores viejos
  final String resolution;
  final int fps;

  MirroringSettings({
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.sharpness = 0.0,
    this.hue = 0.0,
    this.exposure = 0.0,
    this.isAudioEnabled = true,
    this.isAntiScreensaverEnabled = true,
    this.resolution = '1080p',
    this.fps = 30,
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
      resolution: map['resolution'] ?? '1080p',
      fps: (map['fps'] ?? 30).toInt(),
    );
  }
}
