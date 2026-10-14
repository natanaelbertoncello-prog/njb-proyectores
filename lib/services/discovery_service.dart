import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonsoir/bonsoir.dart';
import '../core/app_config.dart';
import '../models/discovered_device.dart';
import 'local_network.dart';
import 'settings_store.dart';

final discoveryServiceProvider = StateNotifierProvider<DiscoveryService, List<DiscoveredDevice>>((ref) {
  return DiscoveryService();
});

/// Información que devuelve un receptor NJB en `GET /info`.
class ReceiverInfo {
  final String name;
  final String version;
  final String platform;
  final int? screenWidth;
  final int? screenHeight;

  const ReceiverInfo({
    required this.name,
    required this.version,
    required this.platform,
    this.screenWidth,
    this.screenHeight,
  });

  static ReceiverInfo? fromJson(dynamic json) {
    if (json is! Map) return null;
    if (json['app'] != 'njb-proyectores') return null;
    return ReceiverInfo(
      name: (json['name'] ?? AppConfig.receiverServiceName).toString(),
      version: (json['version'] ?? '?').toString(),
      platform: (json['platform'] ?? '?').toString(),
      screenWidth: (json['screenWidth'] as num?)?.toInt(),
      screenHeight: (json['screenHeight'] as num?)?.toInt(),
    );
  }

  String get screenLabel => screenWidth != null && screenHeight != null ? '${screenWidth}x$screenHeight' : '';
}

/// Descubre receptores NJB en la red local combinando mDNS (instantáneo cuando
/// el router lo permite) con un barrido de la subred (funciona siempre).
class DiscoveryService extends StateNotifier<List<DiscoveredDevice>> {
  DiscoveryService() : super([]) {
    startScanning();
    _periodic = Timer.periodic(const Duration(seconds: 90), (_) => _scanSubnet());
  }

  final List<BonsoirDiscovery> _scanners = [];
  final List<StreamSubscription> _subscriptions = [];
  Set<String> _selfIps = {};
  Timer? _periodic;
  bool _scanning = false;
  bool _disposed = false;

  bool get isScanning => _scanning;

  /// Reinicia el descubrimiento completo (botón "Escanear red").
  Future<void> startScanning() async {
    state = state.where((d) => d.protocol == DiscoveryProtocol.manual).toList();
    await _clearScanners();
    _selfIps = (await LocalNetwork.allIpv4()).toSet();
    unawaited(_scanSubnet());
    unawaited(_startMdns());
    unawaited(_probeLastReceiver());
  }

  /// El último proyector usado se consulta primero: aparece al instante.
  Future<void> _probeLastReceiver() async {
    final ip = await SettingsStore.getLastReceiverIp();
    if (ip == null || _selfIps.contains(ip) || _disposed) return;
    await _probeAndRegister(ip);
  }

  Future<void> _clearScanners() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    for (final scanner in _scanners) {
      try {
        await scanner.stop();
      } catch (_) {}
    }
    _subscriptions.clear();
    _scanners.clear();
  }

  Future<void> _startMdns() async {
    try {
      final discovery = BonsoirDiscovery(type: AppConfig.mdnsServiceType);
      await discovery.initialize();

      final sub = discovery.eventStream!.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            // Hay que resolverlo para conocer la IP.
            unawaited(service.resolve(discovery.serviceResolver));
          case BonsoirDiscoveryServiceResolvedEvent(:final service):
          case BonsoirDiscoveryServiceUpdatedEvent(:final service):
            final host = service.host;
            if (host == null || _selfIps.contains(host)) return;
            unawaited(_registerHost(host, service.port, DiscoveryProtocol.mdns, fallbackName: service.name));
          case BonsoirDiscoveryServiceLostEvent(:final service):
            final host = service.host;
            if (host != null) _removeHost(host, onlyIf: DiscoveryProtocol.mdns);
          default:
            break;
        }
      });

      _subscriptions.add(sub);
      _scanners.add(discovery);
      await discovery.start();
    } catch (e) {
      debugPrint('mDNS no disponible (se usa sólo el barrido de red): $e');
    }
  }

  /// Barrido de la subred: consulta `/info` en cada IP. Es la forma más
  /// confiable con routers que bloquean multicast (muy común).
  Future<void> _scanSubnet() async {
    if (_scanning || _disposed) return;
    _scanning = true;
    try {
      final subnets = _selfIps.map((ip) => ip.substring(0, ip.lastIndexOf('.'))).toSet();
      for (final subnet in subnets) {
        final pending = <Future<void>>[];
        for (int i = 1; i < 255; i++) {
          final host = '$subnet.$i';
          if (_selfIps.contains(host)) continue;
          pending.add(_probeAndRegister(host));
          if (pending.length >= 32) {
            await Future.wait(pending);
            pending.clear();
          }
        }
        await Future.wait(pending);
      }
    } finally {
      _scanning = false;
    }
  }

  Future<void> _probeAndRegister(String host) async {
    final info = await probeReceiver(host, timeout: const Duration(milliseconds: 900));
    if (info == null || _disposed) return;
    _upsert(DiscoveredDevice(
      id: host,
      name: info.name,
      host: host,
      port: AppConfig.signalingPort,
      protocol: DiscoveryProtocol.scan,
      version: info.version,
      platform: info.platform,
      isNjb: true,
      screen: info.screenLabel.isEmpty ? null : info.screenLabel,
    ));
  }

  /// Consulta `GET http://host:port/info`. Devuelve `null` si no es un receptor NJB.
  static Future<ReceiverInfo?> probeReceiver(String host, {Duration timeout = const Duration(seconds: 2)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:${AppConfig.signalingPort}/info'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      return ReceiverInfo.fromJson(jsonDecode(body));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _registerHost(String host, int port, DiscoveryProtocol protocol, {String? fallbackName}) async {
    final info = await probeReceiver(host);
    if (_disposed) return;
    _upsert(DiscoveredDevice(
      id: host,
      name: info?.name ?? _cleanName(fallbackName ?? host),
      host: host,
      port: port,
      protocol: protocol,
      version: info?.version,
      platform: info?.platform,
      isNjb: info != null,
      screen: (info?.screenLabel ?? '').isEmpty ? null : info!.screenLabel,
    ));
  }

  String _cleanName(String name) {
    if (name.contains('NJB')) return name;
    return name.split('._').first.replaceAll('_', ' ');
  }

  void _upsert(DiscoveredDevice device) {
    final index = state.indexWhere((d) => d.host == device.host);
    if (index == -1) {
      state = [...state, device];
    } else {
      final existing = state[index];
      final merged = existing.copyWith(
        name: device.isNjb ? device.name : null,
        version: device.version,
        platform: device.platform,
        isNjb: existing.isNjb || device.isNjb,
        screen: device.screen,
      );
      state = [...state]..[index] = merged;
    }
  }

  void _removeHost(String host, {DiscoveryProtocol? onlyIf}) {
    state = state.where((d) => d.host != host || (onlyIf != null && d.protocol != onlyIf)).toList();
  }

  /// Agrega un receptor por IP escrita a mano y trata de identificarlo.
  Future<bool> addManualDevice(String host) async {
    final clean = host.trim();
    if (clean.isEmpty) return false;
    final info = await probeReceiver(clean, timeout: const Duration(seconds: 3));
    _upsert(DiscoveredDevice(
      id: clean,
      name: info?.name ?? 'Receptor manual ($clean)',
      host: clean,
      port: AppConfig.signalingPort,
      protocol: DiscoveryProtocol.manual,
      version: info?.version,
      platform: info?.platform,
      isNjb: info != null,
      screen: (info?.screenLabel ?? '').isEmpty ? null : info!.screenLabel,
    ));
    return info != null;
  }

  @override
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _clearScanners();
    super.dispose();
  }
}
