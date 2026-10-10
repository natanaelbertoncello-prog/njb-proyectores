import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Utilidades para conocer las direcciones IP locales del equipo.
///
/// `network_info_plus` sólo devuelve la IP de la interfaz Wi-Fi. Un proyector
/// o una PC conectados por cable Ethernet devuelven `null`, así que caemos a
/// enumerar las interfaces de red del sistema.
class LocalNetwork {
  LocalNetwork._();

  /// IP principal para anunciar el receptor (Wi-Fi primero, luego Ethernet).
  static Future<String?> primaryIp() async {
    try {
      final wifi = await NetworkInfo().getWifiIP();
      if (wifi != null && wifi.isNotEmpty && wifi != '0.0.0.0') return wifi;
    } catch (e) {
      debugPrint('No se pudo leer la IP Wi-Fi: $e');
    }
    final all = await allIpv4();
    return all.isEmpty ? null : all.first;
  }

  /// Todas las IPv4 privadas del equipo, sin loopback.
  static Future<List<String>> allIpv4() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivate(ip)) result.add(ip);
        }
      }
    } catch (e) {
      debugPrint('No se pudieron listar las interfaces de red: $e');
    }
    // Priorizar redes "normales" (192.168.x.x) sobre adaptadores virtuales.
    result.sort((a, b) {
      int score(String ip) => ip.startsWith('192.168.') ? 0 : (ip.startsWith('10.') ? 1 : 2);
      return score(a).compareTo(score(b));
    });
    return result;
  }

  static bool _isPrivate(String ip) {
    if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }
}
