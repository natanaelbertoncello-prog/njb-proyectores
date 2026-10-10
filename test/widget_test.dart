import 'package:flutter_test/flutter_test.dart';
import 'package:proyectar/core/app_version.dart';

void main() {
  group('AppVersion', () {
    test('parsea tags con y sin prefijo v', () {
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2.3+45'), const AppVersion(1, 2, 3, 45));
      expect(AppVersion.tryParse('v2.0.0-beta'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('1.5'), const AppVersion(1, 5, 0));
    });

    test('rechaza textos inválidos', () {
      expect(AppVersion.tryParse('abc'), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });

    test('compara correctamente', () {
      expect(const AppVersion(1, 1, 0) > const AppVersion(1, 0, 9), isTrue);
      expect(const AppVersion(2, 0, 0) > const AppVersion(1, 99, 99), isTrue);
      expect(const AppVersion(1, 0, 0, 2) > const AppVersion(1, 0, 0, 1), isTrue);
      expect(const AppVersion(1, 0, 0) < const AppVersion(1, 0, 1), isTrue);
      expect(const AppVersion(1, 0, 0) == const AppVersion(1, 0, 0), isTrue);
    });
  });
}
