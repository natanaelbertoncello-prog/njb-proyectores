import 'package:flutter_test/flutter_test.dart';
import 'package:proyectar/services/dial_service.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('DialService (botón Transmitir de YouTube)', () {
    late DialService dial;
    final launches = <String>[];
    int stops = 0;

    setUp(() {
      launches.clear();
      stops = 0;
      dial = DialService(
        localIp: '192.168.0.50',
        onLaunchYouTube: launches.add,
        onStopYouTube: () => stops++,
      );
    });

    Request req(String method, String path, {String body = ''}) =>
        Request(method, Uri.parse('http://192.168.0.50:8080/$path'), body: body);

    test('describe el dispositivo con Application-URL', () async {
      final res = await dial.handle(req('GET', 'dd.xml'));
      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(res.headers['Application-URL'], 'http://192.168.0.50:8080/apps/');
      final xml = await res.readAsString();
      expect(xml, contains('urn:dial-multiscreen-org:device:dial:1'));
      expect(xml, contains('uuid:${dial.uuid}'));
    });

    test('YouTube: parado, lanzar, corriendo, detener', () async {
      var state = await (await dial.handle(req('GET', 'apps/YouTube')))!.readAsString();
      expect(state, contains('<state>stopped</state>'));

      final launch = await dial.handle(req('POST', 'apps/YouTube', body: 'pairingCode=abc&theme=cl'));
      expect(launch!.statusCode, 201);
      expect(launch.headers['location'], 'http://192.168.0.50:8080/apps/YouTube/run');
      expect(launches, ['pairingCode=abc&theme=cl']);

      state = await (await dial.handle(req('GET', 'apps/YouTube')))!.readAsString();
      expect(state, contains('<state>running</state>'));
      expect(state, contains('rel="run"'));

      final stop = await dial.handle(req('DELETE', 'apps/YouTube/run'));
      expect(stop!.statusCode, 200);
      expect(stops, 1);
      expect(dial.youtubeRunning, isFalse);
    });

    test('otras apps (Netflix, Disney+) responden 404', () async {
      expect((await dial.handle(req('GET', 'apps/Netflix')))!.statusCode, 404);
      expect((await dial.handle(req('POST', 'apps/Disney')))!.statusCode, 404);
    });

    test('rutas ajenas se ignoran', () async {
      expect(await dial.handle(req('GET', 'info')), isNull);
      expect(await dial.handle(req('GET', 'ws')), isNull);
    });

    test('el uuid es estable y tiene formato válido', () {
      expect(dial.uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(DialService(localIp: 'x', onLaunchYouTube: (_) {}, onStopYouTube: () {}).uuid, dial.uuid);
    });
  });
}
