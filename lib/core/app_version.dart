import 'package:package_info_plus/package_info_plus.dart';

/// Versión semántica simple (`1.2.3`, opcionalmente con `+build`).
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  static const zero = AppVersion(0, 0, 0);

  /// Acepta `1.2.3`, `v1.2.3`, `1.2.3+45`, `v1.2.3-beta` (ignora el sufijo).
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

    int build = 0;
    final plus = text.indexOf('+');
    if (plus != -1) {
      build = int.tryParse(text.substring(plus + 1)) ?? 0;
      text = text.substring(0, plus);
    }
    final dash = text.indexOf('-');
    if (dash != -1) text = text.substring(0, dash);

    final parts = text.split('.');
    if (parts.isEmpty) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      nums.add(n);
    }
    while (nums.length < 3) {
      nums.add(0);
    }
    return AppVersion(nums[0], nums[1], nums[2], build);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() => '$major.$minor.$patch';

  String get withBuild => build > 0 ? '$this+$build' : toString();
}

/// Versión de la app instalada, leída una sola vez del paquete.
class CurrentVersion {
  CurrentVersion._();

  static AppVersion? _cached;
  static String _label = '';

  static Future<AppVersion> get() async {
    if (_cached != null) return _cached!;
    try {
      final info = await PackageInfo.fromPlatform();
      final parsed = AppVersion.tryParse(info.version) ?? AppVersion.zero;
      _cached = AppVersion(
        parsed.major,
        parsed.minor,
        parsed.patch,
        int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (_) {
      _cached = AppVersion.zero;
    }
    _label = 'v${_cached!.withBuild}';
    return _cached!;
  }

  /// Etiqueta lista para mostrar (vacía hasta que se llame a [get]).
  static String get label => _label;
}
