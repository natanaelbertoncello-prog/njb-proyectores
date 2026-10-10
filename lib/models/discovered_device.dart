enum DiscoveryProtocol { mdns, scan, manual }

class DiscoveredDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final DiscoveryProtocol protocol;

  /// Versión de la app que corre en el receptor (si se pudo consultar).
  final String? version;

  /// Sistema operativo del receptor (android, windows, ...).
  final String? platform;

  /// `true` si respondió al endpoint `/info` como un receptor NJB.
  final bool isNjb;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.protocol,
    this.version,
    this.platform,
    this.isNjb = false,
  });

  DiscoveredDevice copyWith({
    String? name,
    DiscoveryProtocol? protocol,
    String? version,
    String? platform,
    bool? isNjb,
  }) {
    return DiscoveredDevice(
      id: id,
      name: name ?? this.name,
      host: host,
      port: port,
      protocol: protocol ?? this.protocol,
      version: version ?? this.version,
      platform: platform ?? this.platform,
      isNjb: isNjb ?? this.isNjb,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
