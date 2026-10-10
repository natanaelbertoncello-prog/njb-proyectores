import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

class SourcePickerDialog extends StatefulWidget {
  const SourcePickerDialog({super.key});

  @override
  State<SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<SourcePickerDialog> {
  List<DesktopCapturerSource> _sources = [];
  bool _isLoading = true;

  /// Ventanas cuya miniatura salió completamente negra: el capturador de
  /// Windows que usa la librería (GDI) no puede leer ventanas aceleradas por
  /// GPU (navegadores, Electron, juegos). Se avisa antes de elegirlas.
  final Set<String> _blackSources = {};

  static final RegExp _browserRegex = RegExp(
    r'chrome|edge|firefox|brave|opera|vivaldi|chromium',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoading = true);
    try {
      final sources = await desktopCapturer.getSources(types: [
        SourceType.Screen,
        SourceType.Window,
      ]);
      if (mounted) {
        setState(() {
          _sources = sources;
          _isLoading = false;
        });
      }
      _analyzeThumbnails(sources);
    } catch (e) {
      debugPrint('Error cargando fuentes de pantalla: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _analyzeThumbnails(List<DesktopCapturerSource> sources) async {
    final black = <String>{};
    for (final source in sources) {
      final bytes = source.thumbnail;
      if (bytes == null || bytes.isEmpty || source.id.contains('screen')) continue;
      try {
        if (await _isMostlyBlack(bytes)) black.add(source.id);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _blackSources
          ..clear()
          ..addAll(black);
      });
    }
  }

  static Future<bool> _isMostlyBlack(List<int> png) async {
    final image = await decodeImageFromList(Uint8List.fromList(png));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      final total = image.width * image.height;
      if (total == 0) return false;
      final step = (total / 400).ceil().clamp(1, total);
      int sampled = 0, dark = 0;
      for (int i = 0; i < total; i += step) {
        final o = i * 4;
        final r = data.getUint8(o), g = data.getUint8(o + 1), b = data.getUint8(o + 2);
        if (r < 12 && g < 12 && b < 12) dark++;
        sampled++;
      }
      return sampled > 0 && dark / sampled > 0.985;
    } finally {
      image.dispose();
    }
  }

  bool _isProblematic(DesktopCapturerSource s) =>
      _blackSources.contains(s.id) || _browserRegex.hasMatch(s.name);

  Future<void> _onSourceTap(DesktopCapturerSource source, {required bool isScreen}) async {
    if (isScreen || !_isProblematic(source)) {
      Navigator.pop(context, source);
      return;
    }

    final screens = _sources.where((s) => s.id.contains('screen')).toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF130D21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ESTA VENTANA SE VE EN NEGRO', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text(
          'Windows no deja capturar ventanas con aceleración por GPU (navegadores, Spotify, Discord, juegos): '
          'llegan al proyector como un rectángulo negro.\n\n'
          'Opciones:\n'
          '• Transmitir la PC COMPLETA y maximizar la app que querés mostrar (recomendado).\n'
          '• En Chrome/Edge: Configuración → Sistema → desactivar "Usar aceleración por hardware", '
          'reiniciar el navegador y volver a intentar.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'anyway'),
            child: const Text('TRANSMITIR IGUAL', style: TextStyle(color: Colors.white38)),
          ),
          if (screens.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF06B6D4), foregroundColor: Colors.black),
              icon: const Icon(Icons.monitor, size: 16),
              label: const Text('USAR PC COMPLETA', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.pop(ctx, 'screen'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'anyway') {
      Navigator.pop(context, source);
    } else if (choice == 'screen') {
      Navigator.pop(context, screens.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    const neonPink = Color(0xFFD946EF);
    const goldAccent = Color(0xFFF59E0B);
    const darkBg = Color(0xFF130D21);

    final screens = _sources.where((s) => s.id.contains('screen')).toList();
    final windows = _sources.where((s) => !s.id.contains('screen') && s.name.trim().isNotEmpty).toList();

    return DefaultTabController(
      length: 2,
      child: Dialog(
        backgroundColor: darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: neonPink.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Container(
          width: 680,
          height: 560,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECCIONA LA FUENTE A TRANSMITIR',
                        style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Puedes transmitir tu PC completa o una sola App independiente (ej. PowerPoint, Chrome)',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: neonPink),
                          )
                        : const Icon(Icons.refresh, color: neonPink),
                    tooltip: 'Actualizar lista de ventanas',
                    onPressed: _loadSources,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: neonPink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  tabs: [
                    Tab(
                      height: 42,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.monitor, size: 18),
                          const SizedBox(width: 8),
                          Text('PC COMPLETA (${screens.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 42,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.window, size: 18),
                          const SizedBox(width: 8),
                          Text('UNA SOLA APP (${windows.length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        _buildVirtualDisplayHint(goldAccent),
                        Expanded(child: _buildSourceGrid(screens, isScreen: true)),
                      ],
                    ),
                    Column(
                      children: [
                        _buildBrowserHint(neonPink),
                        Expanded(child: _buildSourceGrid(windows, isScreen: false)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVirtualDisplayHint(Color accentColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: accentColor, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'TIP: Si deseas una pantalla extra independiente, crea una Pantalla Virtual en Windows. Aparecerá en esta lista para que la selecciones.',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserHint(Color accentColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.open_in_browser, color: accentColor, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Las ventanas con aceleración por GPU (Chrome, Edge, Firefox, Spotify, juegos) Windows las entrega en NEGRO. '
              'Las marcadas en rojo no van a verse: para esas usá "PC COMPLETA" con la app maximizada.',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceGrid(List<DesktopCapturerSource> sources, {required bool isScreen}) {
    if (sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.desktop_access_disabled, color: Colors.white24, size: 40),
            SizedBox(height: 12),
            Text('No se encontraron aplicaciones o pantallas abiertas', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.25,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        return _buildSourceCard(sources[index], isScreen: isScreen);
      },
    );
  }

  Widget _buildSourceCard(DesktopCapturerSource source, {required bool isScreen}) {
    const neonPink = Color(0xFFD946EF);
    const electricCyan = Color(0xFF06B6D4);
    final problematic = !isScreen && _isProblematic(source);
    final themeColor = problematic ? Colors.redAccent : (isScreen ? electricCyan : neonPink);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _onSourceTap(source, isScreen: isScreen),
        child: Ink(
          decoration: BoxDecoration(
            color: (problematic ? Colors.redAccent : Colors.white).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (problematic ? Colors.redAccent : Colors.white).withValues(alpha: problematic ? 0.5 : 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    image: source.thumbnail != null
                        ? DecorationImage(
                            image: MemoryImage(source.thumbnail!),
                            fit: BoxFit.contain,
                          )
                        : null,
                  ),
                  child: source.thumbnail == null
                      ? Icon(isScreen ? Icons.monitor : Icons.window, color: themeColor.withValues(alpha: 0.5), size: 36)
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      problematic
                          ? (_blackSources.contains(source.id) ? 'SE CAPTURA EN NEGRO' : 'NAVEGADOR: SE VE EN NEGRO')
                          : (isScreen ? 'PANTALLA ENTERA' : 'VENTANA DE APP'),
                      style: TextStyle(color: themeColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
