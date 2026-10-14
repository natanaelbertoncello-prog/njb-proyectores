import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import '../core/app_config.dart';

/// Receptor DIAL (DIscovery And Launch): el protocolo abierto con el que la
/// app de YouTube encuentra "televisores" en la red y les pide que abran un
/// video. Con esto el botón "Transmitir" de YouTube muestra a este receptor.
///
/// Partes:
///  1. SSDP (UDP multicast 239.255.255.250:1900): respondemos a los M-SEARCH
///     que buscan `urn:dial-multiscreen-org:service:dial:1`.
///  2. HTTP (en el servidor del receptor, puerto 8080):
///     `GET /dd.xml` describe el dispositivo; `GET|POST /apps/YouTube` informa
///     o lanza la app; `DELETE /apps/YouTube/run` la cierra.
///  3. Al lanzar, abrimos `https://www.youtube.com/tv?<parámetros>` en el
///     navegador integrado: ese sitio se empareja con el celular usando el
///     `pairingCode` que manda YouTube.
///
/// Netflix, Disney+ y Prime Video usan Google Cast (propietario, con
/// certificados de hardware y DRM): no se puede emular. Sólo YouTube.
class DialService {
  DialService({
    required this.localIp,
    required this.onLaunchYouTube,
    required this.onStopYouTube,
  });

  final String localIp;
  final void Function(String launchQuery) onLaunchYouTube;
  final VoidCallback onStopYouTube;

  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;
  static const _dialSearchTarget = 'urn:dial-multiscreen-org:service:dial:1';
  static const _serviceChannel = MethodChannel(AppConfig.serviceChannel);

  RawDatagramSocket? _socket;
  Timer? _notifyTimer;
  bool _youtubeRunning = false;
  bool _disposed = false;

  bool get youtubeRunning => _youtubeRunning;

  /// Identificador estable del dispositivo (mismo mientras no cambie el nombre del equipo).
  late final String uuid = _makeUuid();

  String get _baseUrl => 'http://$localIp:${AppConfig.signalingPort}';

  // ---------------------------------------------------------------------------
  // SSDP
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (!kIsWeb && Platform.isAndroid) {
      // Android descarta el multicast salvo que la app tome un MulticastLock.
      try {
        await _serviceChannel.invokeMethod('multicastLock', {'on': true});
      } catch (e) {
        debugPrint('MulticastLock: $e');
      }
    }

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _ssdpPort, reuseAddress: true);
      socket.multicastHops = 4;
      socket.broadcastEnabled = true;
      final group = InternetAddress(_ssdpAddress);
      bool joined = false;
      try {
        socket.joinMulticast(group);
        joined = true;
      } catch (_) {}
      try {
        for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          try {
            socket.joinMulticast(group, iface);
            joined = true;
          } catch (_) {}
        }
      } catch (_) {}
      if (!joined) debugPrint('SSDP: no se pudo unir al grupo multicast');

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram != null) _onDatagram(socket, datagram);
      });
      _socket = socket;
      debugPrint('DIAL/SSDP escuchando en :$_ssdpPort (uuid $uuid)');

      _sendNotify();
      _notifyTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sendNotify());
    } catch (e) {
      debugPrint('SSDP no disponible: $e');
    }
  }

  void _onDatagram(RawDatagramSocket socket, Datagram d) {
    final text = utf8.decode(d.data, allowMalformed: true);
    if (!text.startsWith('M-SEARCH')) return;
    final st = _header(text, 'ST') ?? '';
    final wanted = st == _dialSearchTarget || st == 'ssdp:all' || st == 'upnp:rootdevice';
    if (!wanted) return;

    final reply = [
      'HTTP/1.1 200 OK',
      'CACHE-CONTROL: max-age=1800',
      'EXT:',
      'LOCATION: $_baseUrl/dd.xml',
      'SERVER: Linux/3.0 UPnP/1.0 NJB/1.0',
      'ST: $_dialSearchTarget',
      'USN: uuid:$uuid::$_dialSearchTarget',
      'BOOTID.UPNP.ORG: 1',
      'CONFIGID.UPNP.ORG: 1',
      '',
      '',
    ].join('\r\n');
    // Pequeña espera aleatoria como pide SSDP, y respuesta unicast al que preguntó.
    Future.delayed(Duration(milliseconds: 50 + DateTime.now().millisecond % 200), () {
      try {
        socket.send(utf8.encode(reply), d.address, d.port);
      } catch (_) {}
    });
  }

  void _sendNotify() {
    final socket = _socket;
    if (socket == null || _disposed) return;
    final msg = [
      'NOTIFY * HTTP/1.1',
      'HOST: $_ssdpAddress:$_ssdpPort',
      'CACHE-CONTROL: max-age=1800',
      'LOCATION: $_baseUrl/dd.xml',
      'NT: $_dialSearchTarget',
      'NTS: ssdp:alive',
      'SERVER: Linux/3.0 UPnP/1.0 NJB/1.0',
      'USN: uuid:$uuid::$_dialSearchTarget',
      '',
      '',
    ].join('\r\n');
    try {
      socket.send(utf8.encode(msg), InternetAddress(_ssdpAddress), _ssdpPort);
    } catch (_) {}
  }

  static String? _header(String msg, String name) {
    for (final line in msg.split('\n')) {
      final i = line.indexOf(':');
      if (i > 0 && line.substring(0, i).trim().toUpperCase() == name.toUpperCase()) {
        return line.substring(i + 1).trim();
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // HTTP (se monta en el servidor del receptor)
  // ---------------------------------------------------------------------------

  /// Devuelve una respuesta si la ruta es de DIAL; `null` si no es nuestra.
  Future<Response?> handle(Request request) async {
    final path = request.url.path;

    if (request.method == 'GET' && path == 'dd.xml') {
      return Response.ok(_deviceDescription(), headers: {
        'content-type': 'application/xml; charset=utf-8',
        'Application-URL': '$_baseUrl/apps/',
        'access-control-allow-origin': '*',
      });
    }

    if (!path.startsWith('apps/')) return null;
    final parts = path.split('/');
    final app = parts.length > 1 ? parts[1] : '';
    final isRun = parts.length > 2 && parts[2] == 'run';

    if (app != 'YouTube') {
      // Netflix, Disney+, etc. preguntan y hay que decirles que no está.
      return Response.notFound('Not Found');
    }

    switch (request.method) {
      case 'GET':
        return Response.ok(_youtubeState(), headers: {
          'content-type': 'application/xml; charset=utf-8',
          'access-control-allow-origin': '*',
        });
      case 'POST':
        final body = await request.readAsString();
        _youtubeRunning = true;
        onLaunchYouTube(body);
        return Response(201, headers: {'location': '$_baseUrl/apps/YouTube/run', 'content-length': '0'});
      case 'DELETE':
        if (isRun || true) {
          _youtubeRunning = false;
          onStopYouTube();
          return Response.ok('');
        }
      case 'OPTIONS':
        return Response.ok('', headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
          'access-control-allow-headers': '*',
        });
    }
    return Response(405);
  }

  /// La página de YouTube cerró o el usuario la cerró desde el proyector.
  void markYouTubeStopped() => _youtubeRunning = false;

  String _deviceDescription() => '''<?xml version="1.0" encoding="UTF-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:dial-multiscreen-org:device:dial:1</deviceType>
    <friendlyName>${AppConfig.receiverServiceName}</friendlyName>
    <manufacturer>NJB</manufacturer>
    <modelName>NJB Proyectores</modelName>
    <modelNumber>1</modelNumber>
    <UDN>uuid:$uuid</UDN>
    <serviceList>
      <service>
        <serviceType>urn:dial-multiscreen-org:service:dial:1</serviceType>
        <serviceId>urn:dial-multiscreen-org:serviceId:dial</serviceId>
        <controlURL>/apps</controlURL>
        <eventSubURL></eventSubURL>
        <SCPDURL></SCPDURL>
      </service>
    </serviceList>
  </device>
</root>''';

  String _youtubeState() => '''<?xml version="1.0" encoding="UTF-8"?>
<service xmlns="urn:dial-multiscreen-org:schemas:dial" dialVer="2.1">
  <name>YouTube</name>
  <options allowStop="true"/>
  <state>${_youtubeRunning ? 'running' : 'stopped'}</state>
  ${_youtubeRunning ? '<link rel="run" href="run"/>' : ''}
</service>''';

  static String _makeUuid() {
    String seed = 'njb';
    try {
      seed = Platform.localHostname;
    } catch (_) {}
    // UUID v5-ish derivado del nombre del equipo (estable entre reinicios).
    final bytes = utf8.encode('njb-proyectores:$seed');
    final h = List<int>.filled(16, 0);
    for (int i = 0; i < bytes.length; i++) {
      h[i % 16] = (h[i % 16] * 31 + bytes[i]) & 0xff;
    }
    h[6] = (h[6] & 0x0f) | 0x50;
    h[8] = (h[8] & 0x3f) | 0x80;
    final hex = h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> dispose() async {
    _disposed = true;
    _notifyTimer?.cancel();
    try {
      // Avisar que nos vamos.
      final socket = _socket;
      if (socket != null) {
        final bye = [
          'NOTIFY * HTTP/1.1',
          'HOST: $_ssdpAddress:$_ssdpPort',
          'NT: $_dialSearchTarget',
          'NTS: ssdp:byebye',
          'USN: uuid:$uuid::$_dialSearchTarget',
          '',
          '',
        ].join('\r\n');
        socket.send(utf8.encode(bye), InternetAddress(_ssdpAddress), _ssdpPort);
      }
    } catch (_) {}
    _socket?.close();
    _socket = null;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _serviceChannel.invokeMethod('multicastLock', {'on': false});
      } catch (_) {}
    }
  }
}
