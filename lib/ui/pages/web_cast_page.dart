import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/discovered_device.dart';
import '../../services/signaling_service.dart';

/// "Proyectar una página web": el receptor abre la página en su propio
/// navegador y desde acá se lo maneja como un control remoto. El celular o
/// la PC quedan libres para hacer otra cosa.
class WebCastPage extends StatefulWidget {
  final DiscoveredDevice device;
  const WebCastPage({super.key, required this.device});

  @override
  State<WebCastPage> createState() => _WebCastPageState();
}

class _WebCastPageState extends State<WebCastPage> {
  static const neonPink = Color(0xFFD946EF);
  static const electricCyan = Color(0xFF06B6D4);
  static const goldAccent = Color(0xFFF59E0B);
  static const darkBg = Color(0xFF0A0512);

  final _urlController = TextEditingController();
  SignalingService? _signaling;
  bool _connected = false;
  bool _connecting = true;
  String? _error;
  String? _openUrl;
  bool _desktopMode = true;
  double _zoom = 1.0;
  Timer? _scrollRepeat;

  static const _quick = <({String label, String url, IconData icon})>[
    (label: 'YouTube', url: 'https://www.youtube.com', icon: Icons.play_circle_fill),
    (label: 'Google', url: 'https://www.google.com', icon: Icons.search),
    (label: 'Drive', url: 'https://drive.google.com', icon: Icons.folder),
    (label: 'Canva', url: 'https://www.canva.com', icon: Icons.brush),
  ];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final s = SignalingService();
    s.onDisconnected = (reason) {
      if (!mounted || !identical(_signaling, s)) return;
      setState(() {
        _connected = false;
        _error = reason;
      });
    };
    _signaling = s;
    try {
      await s.connectControl(widget.device.host);
      if (mounted) {
        setState(() {
          _connected = true;
          _connecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _open(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return;
    if (!url.contains('://')) {
      // "youtube.com" → https://youtube.com ; "cómo hacer pan" → búsqueda.
      final looksLikeDomain = RegExp(r'^[\w.-]+\.[a-z]{2,}(/.*)?$', caseSensitive: false).hasMatch(url);
      url = looksLikeDomain ? 'https://$url' : 'https://www.google.com/search?q=${Uri.encodeQueryComponent(url)}';
    }
    _signaling?.sendWeb('open', {'url': url, 'desktop': _desktopMode});
    setState(() {
      _openUrl = url;
      _zoom = 1.0;
    });
    FocusScope.of(context).unfocus();
  }

  void _cmd(String cmd, [Map<String, dynamic> args = const {}]) => _signaling?.sendWeb(cmd, args);

  void _zoomBy(double delta) {
    _zoom = (_zoom + delta).clamp(0.5, 3.0);
    _cmd('zoom', {'factor': _zoom});
    setState(() {});
  }

  void _startScroll(int dy) {
    _cmd('scroll', {'dy': dy});
    _scrollRepeat?.cancel();
    _scrollRepeat = Timer.periodic(const Duration(milliseconds: 120), (_) => _cmd('scroll', {'dy': dy ~/ 2}));
  }

  void _stopScroll() {
    _scrollRepeat?.cancel();
    _scrollRepeat = null;
  }

  @override
  void dispose() {
    _scrollRepeat?.cancel();
    _urlController.dispose();
    // Sólo se cierra la sesión de control: la página sigue abierta en el proyector.
    _signaling?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        title: Text('PROYECTAR PÁGINA WEB', style: GoogleFonts.orbitron(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _buildStatus(d),
            const SizedBox(height: 18),
            _buildHowItWorks(),
            const SizedBox(height: 18),
            _buildUrlBox(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quick
                  .map((q) => ActionChip(
                        avatar: Icon(q.icon, size: 16, color: electricCyan),
                        label: Text(q.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(color: electricCyan.withValues(alpha: 0.3)),
                        onPressed: _connected ? () => _open(q.url) : null,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            _buildRemote(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(DiscoveredDevice d) {
    final Color color = _connected ? Colors.greenAccent : (_connecting ? electricCyan : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_connected ? Icons.cast_connected : Icons.cast, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name.toUpperCase(), style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  _connecting
                      ? 'Conectando con ${d.host}…'
                      : (_connected ? 'Control remoto conectado' : (_error ?? 'Sin conexión')),
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_connected && !_connecting)
            TextButton(onPressed: _connect, child: const Text('REINTENTAR', style: TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: goldAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline, color: goldAccent, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'El proyector abre la página con su propio navegador: no se captura ni se comprime nada, '
              'y podés usar el celular o la PC para otra cosa. Desde acá lo manejás como un control remoto.',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _urlController,
          enabled: _connected,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: _open,
          decoration: InputDecoration(
            hintText: 'Dirección o búsqueda, ej: youtube.com',
            hintStyle: const TextStyle(color: Colors.white30),
            prefixIcon: const Icon(Icons.language, color: neonPink),
            suffixIcon: IconButton(
              icon: const Icon(Icons.send, color: neonPink),
              onPressed: _connected ? () => _open(_urlController.text) : null,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: neonPink)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: neonPink.withValues(alpha: 0.4))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: neonPink, width: 2)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('VISTA:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            ChoiceChip(
              label: const Text('ESCRITORIO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              selected: _desktopMode,
              selectedColor: electricCyan,
              labelStyle: TextStyle(color: _desktopMode ? Colors.black : Colors.white70),
              onSelected: (_) => _switchMode(true),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('CELULAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              selected: !_desktopMode,
              selectedColor: electricCyan,
              labelStyle: TextStyle(color: !_desktopMode ? Colors.black : Colors.white70),
              onSelected: (_) => _switchMode(false),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Escritorio: la página se ve como en una PC. Celular: letras más grandes, mejor para leer de lejos.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  void _switchMode(bool desktop) {
    setState(() => _desktopMode = desktop);
    if (_openUrl != null) _open(_openUrl!);
  }

  Widget _buildRemote() {
    final enabled = _connected;
    Widget btn(IconData icon, String label, VoidCallback? onTap, {Color color = Colors.white, VoidCallback? onDown, VoidCallback? onUp}) {
      return Expanded(
        child: GestureDetector(
          onTapDown: onDown != null && enabled ? (_) => onDown() : null,
          onTapUp: onUp != null && enabled ? (_) => onUp() : null,
          onTapCancel: onUp != null && enabled ? onUp : null,
          child: ElevatedButton(
            onPressed: enabled ? (onTap ?? () {}) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONTROL REMOTO', style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(
          _openUrl != null ? 'Mostrando: $_openUrl' : 'Todavía no abriste ninguna página.',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Row(children: [
          btn(Icons.keyboard_arrow_up, 'SUBIR', null, onDown: () => _startScroll(-400), onUp: _stopScroll),
          const SizedBox(width: 8),
          btn(Icons.keyboard_arrow_down, 'BAJAR', null, onDown: () => _startScroll(400), onUp: _stopScroll),
          const SizedBox(width: 8),
          btn(Icons.vertical_align_top, 'INICIO', () => _cmd('top')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          btn(Icons.arrow_back, 'ATRÁS', () => _cmd('back')),
          const SizedBox(width: 8),
          btn(Icons.arrow_forward, 'ADELANTE', () => _cmd('forward')),
          const SizedBox(width: 8),
          btn(Icons.refresh, 'RECARGAR', () => _cmd('reload')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          btn(Icons.zoom_out, 'ZOOM −', () => _zoomBy(-0.1)),
          const SizedBox(width: 8),
          btn(Icons.zoom_in, 'ZOOM + (${(_zoom * 100).round()}%)', () => _zoomBy(0.1)),
          const SizedBox(width: 8),
          btn(Icons.play_arrow, 'PLAY/PAUSA', () => _cmd('playpause'), color: electricCyan),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          btn(Icons.fullscreen, 'VIDEO A PANTALLA COMPLETA', () => _cmd('fullscreen'), color: goldAccent),
          const SizedBox(width: 8),
          btn(Icons.close, 'CERRAR EN EL PROYECTOR', () {
            _cmd('close');
            setState(() => _openUrl = null);
          }, color: Colors.redAccent),
        ]),
        const SizedBox(height: 14),
        const Text(
          'Mantené apretado SUBIR o BAJAR para desplazarte seguido. Si cerrás esta pantalla, la página sigue en el proyector.',
          style: TextStyle(color: Colors.white30, fontSize: 10),
        ),
      ],
    );
  }
}
