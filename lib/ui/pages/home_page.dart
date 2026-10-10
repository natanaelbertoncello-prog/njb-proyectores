import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_version.dart';
import '../../services/discovery_service.dart';
import '../../services/iot_service.dart';
import '../../core/mirroring_manager.dart';
import '../../models/discovered_device.dart';
import '../widgets/mirroring_settings_panel.dart';
import '../widgets/compact_device_button.dart';
import '../widgets/update_banner.dart';
import 'projector_mode_page.dart';
import 'receiver_mode_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const primaryPurple = Color(0xFF6B21A8);
  static const neonPink = Color(0xFFD946EF);
  static const electricCyan = Color(0xFF06B6D4);
  static const goldAccent = Color(0xFFF59E0B);
  static const darkBg = Color(0xFF0A0512);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveredDevices = ref.watch(discoveryServiceProvider);
    final mirroringState = ref.watch(mirroringProvider);
    final smartDevices = ref.watch(iotServiceProvider);

    return Scaffold(
      backgroundColor: darkBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildHeroHeader(context, mirroringState),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Aviso de versión nueva (sólo aparece cuando hay una)
                  const UpdateBanner(),

                  // Discovered Devices Section
                  _buildSectionHeader(
                    title: 'PROYECTORES Y RECEPTORES',
                    subtitle: 'Dispositivos detectados automáticamente en tu red Wi-Fi',
                    icon: Icons.cell_tower,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeaderIconButton(
                          icon: Icons.add_link,
                          color: goldAccent,
                          tooltip: 'Conectar por IP',
                          onPressed: () => _showManualIPDialog(context, ref),
                        ),
                        const SizedBox(width: 8),
                        _buildHeaderIconButton(
                          icon: Icons.sync,
                          color: electricCyan,
                          tooltip: 'Escanear red',
                          onPressed: () => ref.read(discoveryServiceProvider.notifier).startScanning(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (discoveredDevices.isEmpty)
                    _buildDiscoveryPlaceholder()
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: discoveredDevices.length,
                      itemBuilder: (context, index) {
                        return _buildDeviceCard(context, ref, discoveredDevices[index], mirroringState);
                      },
                    ),

                  const SizedBox(height: 24),

                  // Receiver Mode Card
                  _buildReceiverModeCard(context),

                  // Smart Room & Projector Controls (IoT)
                  if (smartDevices.isNotEmpty) ...[
                    const SizedBox(height: 36),
                    _buildSectionHeader(
                      title: 'DOMÓTICA Y CONTROL DE SALA',
                      subtitle: 'Encendido de proyector, luces y cortinas de proyección',
                      icon: Icons.hub,
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 2.7,
                      ),
                      itemCount: smartDevices.length,
                      itemBuilder: (context, index) {
                        return CompactDeviceButton(device: smartDevices[index]);
                      },
                    ),
                  ],

                  const SizedBox(height: 36),

                  // Global Mirroring Settings
                  _buildSectionHeader(
                    title: 'CALIBRACIÓN Y AJUSTES GLOBALES',
                    subtitle: 'Calidad de transmisión, nitidez y protección anti-screensaver',
                    icon: Icons.tune,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const MirroringSettingsPanel(isHome: true),
                  ),

                  // Active Stop Mirroring FAB Button
                  if (mirroringState.status == MirroringStatus.mirroring) ...[
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          elevation: 12,
                          shadowColor: Colors.redAccent.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.stop_circle, size: 22),
                        label: const Text(
                          'DETENER TRANSMISIÓN EN VIVO',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
                        ),
                        onPressed: () {
                          ref.read(mirroringProvider.notifier).stopMirroring();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, MirroringState mirroringState) {
    return SliverAppBar(
      expandedHeight: 220.0,
      floating: false,
      pinned: true,
      backgroundColor: darkBg,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Image.asset(
          'assets/logo.png',
          height: 38,
          fit: BoxFit.contain,
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF8B5CF6),
                    Color(0xFF6B21A8),
                    Color(0xFF0F0716),
                  ],
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: 0.12,
                child: Image.asset('assets/logo.png', height: 210),
              ),
            ),
            Positioned(
              bottom: 60,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: neonPink.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: mirroringState.status == MirroringStatus.mirroring ? Colors.greenAccent : electricCyan,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: mirroringState.status == MirroringStatus.mirroring ? Colors.greenAccent : electricCyan,
                                blurRadius: 6,
                              )
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mirroringState.status == MirroringStatus.mirroring
                              ? 'TRANSMITIENDO EN VIVO'
                              : 'SISTEMA LISTO Y ESCANEANDO',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 40,
              right: 20,
              child: Text(
                CurrentVersion.label,
                style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    IconData? icon,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: neonPink),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            if (trailing != null) trailing,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 18),
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDiscoveryPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: neonPink.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: neonPink),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscando proyectores en tu red local...',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Abre la app en el proyector o presiona + para conectar por IP',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, WidgetRef ref, DiscoveredDevice device, MirroringState state) {
    final isNjbDevice = device.isNjb || device.name.contains('NJB');
    final accentColor = isNjbDevice ? neonPink : goldAccent;
    final details = <String>[
      'IP: ${device.host}:${device.port}',
      if (device.version != null) 'v${device.version}',
      if (device.platform != null) device.platform!.toUpperCase(),
      if (device.screen != null) 'PANTALLA ${device.screen}',
      if (!device.isNjb && device.protocol == DiscoveryProtocol.manual) 'SIN VERIFICAR',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProjectorModePage(
                  receiverIp: device.host,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isNjbDevice ? Icons.verified : Icons.cast_connected,
                    size: 22,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name.toUpperCase(),
                        style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              details.join('  •  '),
                              style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'PROYECTAR',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 10, color: Colors.black),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiverModeCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            neonPink.withValues(alpha: 0.15),
            electricCyan.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: neonPink.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: neonPink.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const ReceiverModePage()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: neonPink.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: neonPink.withValues(alpha: 0.5)),
                  ),
                  child: const Icon(Icons.settings_input_antenna, color: neonPink, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'USAR COMO RECEPTOR HD/4K',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Convierte esta pantalla en un receptor para recibir transmisiones desde tu PC o teléfono',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showManualIPDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF130D21),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: goldAccent.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: const [
            Icon(Icons.add_link, color: goldAccent, size: 22),
            SizedBox(width: 10),
            Text('Conexión por IP Manual', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa la dirección IP de tu proyector chino o pantalla receptora.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Ejemplo: 192.168.1.45',
                hintStyle: const TextStyle(color: Colors.white30, fontWeight: FontWeight.normal),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: goldAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: goldAccent, width: 2),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = controller.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              final found = await ref.read(discoveryServiceProvider.notifier).addManualDevice(ip);
              messenger.showSnackBar(SnackBar(
                content: Text(found
                    ? 'Receptor NJB encontrado en $ip'
                    : 'En $ip no respondió ningún receptor NJB. Verificá que el modo receptor esté abierto. Se agregó igual.'),
                backgroundColor: found ? Colors.green.shade800 : Colors.orange.shade900,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: goldAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('CONECTAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
