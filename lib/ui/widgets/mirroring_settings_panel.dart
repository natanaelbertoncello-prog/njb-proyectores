import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/mirroring_manager.dart';

class MirroringSettingsPanel extends ConsumerWidget {
  final bool isHome;
  const MirroringSettingsPanel({super.key, this.isHome = false});

  static const neonPink = Color(0xFFD946EF);
  static const electricCyan = Color(0xFF06B6D4);
  static const goldAccent = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mirroringState = ref.watch(mirroringProvider);
    final settings = mirroringState.settings;

    return Container(
      padding: EdgeInsets.fromLTRB(20, isHome ? 20 : 16, 20, isHome ? 20 : 32),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isHome) ...[
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'AJUSTES DE IMAGEN Y TRANSMISIÓN',
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            _buildSectionTitle('RESOLUCIÓN Y CUADROS POR SEGUNDO'),
            const SizedBox(height: 12),
            _buildResolutionSelector(context, ref, settings.resolution),
            const SizedBox(height: 14),
            _buildFpsSelector(context, ref, settings.fps),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (settings.resolution == '4K' || settings.resolution == '2K' ? Colors.amber : electricCyan).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (settings.resolution == '4K' || settings.resolution == '2K' ? Colors.amber : electricCyan).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    settings.resolution == '4K' || settings.resolution == '2K' ? Icons.warning_amber_rounded : Icons.lightbulb_outline,
                    color: settings.resolution == '4K' || settings.resolution == '2K' ? Colors.amber : electricCyan,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      settings.resolution == '4K' || settings.resolution == '2K'
                          ? 'Los proyectores chinos suelen decodificar hasta 1080p. En 2K/4K la app del proyector puede trabarse o cerrarse. Recomendado: 1080p.'
                          : 'PARA TEXTO NÍTIDO: 1080p a 15 o 24 FPS. Menos cuadros por segundo = más calidad por cuadro y letras más definidas. Para video o juegos usá 30/60.',
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(color: Colors.white10, height: 36),
            _buildSectionTitle('CALIBRACIÓN EXTREMA DE LENTE Y COLOR'),
            const SizedBox(height: 12),

            _buildSlider(
              label: 'EXPOSICIÓN',
              icon: Icons.exposure,
              value: settings.exposure,
              min: -2.0,
              max: 2.0,
              color: Colors.white,
              onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(exposure: v)),
            ),

            _buildSlider(
              label: 'BRILLO (LENTE INTENSO)',
              icon: Icons.light_mode,
              value: settings.brightness,
              min: 0.0,
              max: 4.0, 
              color: goldAccent,
              onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(brightness: v)),
            ),

            _buildSlider(
              label: 'CONTRASTE DINÁMICO',
              icon: Icons.contrast,
              value: settings.contrast,
              min: 0.0,
              max: 4.0,
              color: Colors.blueAccent,
              onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(contrast: v)),
            ),

            _buildSlider(
              label: 'SATURACIÓN / VIBRANCIA DE COLOR',
              icon: Icons.palette,
              value: settings.saturation,
              min: 0.0,
              max: 4.0,
              color: neonPink,
              onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(saturation: v)),
            ),

            _buildSlider(
              label: 'TONO (HUE ROTATION)',
              icon: Icons.color_lens,
              value: settings.hue,
              min: -3.14,
              max: 3.14,
              color: Colors.orangeAccent,
              onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(hue: v)),
            ),

            _buildSlider(
              label: 'NITIDEZ DIGITAL (DESENFOQUE LENTE)',
              icon: Icons.details,
              value: settings.sharpness,
              min: 0.0,
              max: 2.0,
              color: electricCyan,
              onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(sharpness: v)),
            ),

            const Divider(color: Colors.white10, height: 36),
            _buildSectionTitle('PROTECCIÓN ANTI-SCREENSAVER DE PROYECTOR'),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: goldAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
              ),
              child: SwitchListTile(
                title: const Text('MANTENER DESPIERTO AL PROYECTOR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                subtitle: const Text(
                  'El receptor se comporta como YouTube: mantiene un wakelock, una sesión multimedia activa, '
                  'audio en reproducción y simula actividad periódica para que el proyector no lance su protector de pantalla. '
                  'Para eliminarlo del todo, ejecutá tools/configurar_proyector.ps1 desde la PC (una sola vez).',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                secondary: const Icon(Icons.shield, color: goldAccent, size: 22),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                value: settings.isAntiScreensaverEnabled,
                activeThumbColor: goldAccent,
                onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(isAntiScreensaverEnabled: v)),
              ),
            ),

            const Divider(color: Colors.white10, height: 36),
            _buildSectionTitle('AUDIO Y SONIDO'),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: neonPink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: neonPink.withValues(alpha: 0.3)),
              ),
              child: SwitchListTile(
                title: const Text('TRANSMITIR AUDIO AL PROYECTOR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                subtitle: const Text('Desactiva si prefieres reproducir el sonido en parlantes o audífonos locales', style: TextStyle(color: Colors.white54, fontSize: 10)),
                secondary: const Icon(Icons.volume_up, color: neonPink, size: 22),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                value: settings.isAudioEnabled,
                activeThumbColor: neonPink,
                onChanged: (v) => ref.read(mirroringProvider.notifier).updateSettings(settings.copyWith(isAudioEnabled: v)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.orbitron(
        color: Colors.white70,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildResolutionSelector(BuildContext context, WidgetRef ref, String currentRes) {
    final resolutions = ['480p', '720p', '1080p', '2K', '4K'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: resolutions.map((res) {
        final isSelected = res == currentRes;
        return ChoiceChip(
          label: Text(res, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          selected: isSelected,
          selectedColor: neonPink,
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isSelected ? neonPink : Colors.transparent),
          ),
          onSelected: (selected) {
            if (selected) {
              ref.read(mirroringProvider.notifier).updateSettings(
                ref.read(mirroringProvider).settings.copyWith(resolution: res),
              );
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildFpsSelector(BuildContext context, WidgetRef ref, int currentFps) {
    // 15 y 24 fps: ideales para texto, planillas y presentaciones (más
    // bitrate por cuadro = letras más nítidas). 60 para video o juegos.
    final fpsList = [15, 24, 30, 60];
    return Row(
      children: [
        const Text('FPS:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: fpsList.map((fps) {
              final isSelected = fps == currentFps;
              return ChoiceChip(
                label: Text('$fps FPS', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                selected: isSelected,
                selectedColor: electricCyan,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isSelected ? electricCyan : Colors.transparent),
                ),
                onSelected: (selected) {
                  if (selected) {
                    ref.read(mirroringProvider.notifier).updateSettings(
                      ref.read(mirroringProvider).settings.copyWith(fps: fps),
                    );
                  }
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required Color color,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(value * 100).toInt()}%',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: color,
            inactiveColor: Colors.white10,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
