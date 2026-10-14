import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/discovered_device.dart';
import '../../services/signaling_service.dart';

/// "Proyectar una página web": el receptor abre la página en su propio
/// navegador y desde acá se lo maneja como un control remoto con touchpad y
/// teclado. El celular o la PC quedan libres para hacer otra cosa.
class WebCastPage extends StatefulWidget {
  final DiscoveredDevice device;

  /// Si viene (por ejemplo desde "Compartir"), se abre apenas conecta.
  final String? initialUrl;

  const WebCastPage({super.key, required this.device, this.initialUrl});

  @override
  State<WebCastPage> createState() => _WebCastPageState();
}

class _WebCastPageState extends State<WebCastPage> {
  static const neonPink = Color(0xFFD946EF);
  static const electricCyan = Color(0xFF06B6D4);
  static const goldAccent = Color(0xFFF59E0B);
  static const darkBg = Color(0xFF0A0512);

  final _urlController = TextEditingController();
  final _typeController = TextEditingController();
  SignalingService? _signaling;
  bool _connected = false;
  bool _connecting = true;
  String? _error;
  String? _openUrl;
  bool _desktopMode = true;
  double _zoom = 1.0;
  Timer? _scrollRepeat;

  // Touchpad → puntero en el proyector (fracción 0..1 de su pantalla).
  Offset _cursor = const Offset(0.5, 0.5);
  DateTime _lastCursorSend = DateTime.fromMillisecondsSinceEpoch(0);
  double _scrollAccum = 0;
  bool _twoFingers = false;

  static const _quick = <({String label, String url, IconData icon, Color color})>[
    (label: 'YouTube', url: 'https://www.youtube.com', icon: Icons.play_circle_fill, color: Color(0xFFFF0000)),
    (label: 'Netflix', url: 'https://www.netflix.com', icon: Icons.movie, color: Color(0xFFE50914)),
    (label: 'Disney+', url: 'https://www.disneyplus.com', icon: Icons.auto_awesome, color: Color(0xFF3B7BFF)),
    (label: 'Prime Video', url: 'https://www.primevideo.com', icon: Icons.smart_display, color: Color(0xFF00A8E1)),
    (label: 'Google', url: 'https://www.google.com', icon: Icons.search, color: Color(0xFF4285F4)),
    (label: 'Drive', url: 'https://drive.google.com', icon: Icons.folder, color: Color(0xFFFBBC04)),
    (label: 'Canva', url: 'https://www.canva.com', icon: Icons.brush, color: Color(0xFF00C4CC)),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) _urlController.text = widget.initialUrl!;
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
        if (widget.initialUrl != null && _openUrl == null) _open(widget.initialUrl!);
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

  // --- Touchpad ----------------------------------------------------------------

  void _moveCursor(Offset delta, Size padSize) {
    // Sensibilidad: recorrer el touchpad entero mueve ~1.6 pantallas.
    final fx = (_cursor.dx + delta.dx / padSize.width * 1.6).clamp(0.0, 1.0);
    final fy = (_cursor.dy + delta.dy / padSize.height * 1.6).clamp(0.0, 1.0);
    _cursor = Offset(fx, fy);
    final now = DateTime.now();
    if (now.difference(_lastCursorSend).inMilliseconds >= 25) {
      _lastCursorSend = now;
      _cmd('cursor', {'fx': fx, 'fy': fy});
    }
  }

  void _scrollAtCursor(double dy) {
    _scrollAccum += dy * 2.2;
    if (_scrollAccum.abs() >= 24) {
      _cmd('scroll', {'dy': _scrollAccum.round(), 'fx': _cursor.dx, 'fy': _cursor.dy});
      _scrollAccum = 0;
    }
  }

  void _click({bool double_ = false}) {
    _cmd(double_ ? 'dblclick' : 'click', {'fx': _cursor.dx, 'fy': _cursor.dy});
  }

  // --- Teclado -------------------------------------------------------------------

  void _sendText({bool enter = false}) {
    final text = _typeController.text;
    if (text.isNotEmpty) _cmd('type', {'text': text});
    if (enter) _cmd('key', {'key': 'Enter'});
    _typeController.clear();
  }

  @override
  void dispose() {
    _scrollRepeat?.cancel();
    _urlController.dispose();
    _typeController.dispose();
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
            const SizedBox(height: 14),
            _buildUrlBox(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quick
                  .map((q) => ActionChip(
                        avatar: Icon(q.icon, size: 16, color: q.color),
                        label: Text(q.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(color: q.color.withValues(alpha: 0.4)),
                        onPressed: _connected ? () => _open(q.url) : null,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
            const Text(
              'Netflix, Disney+ y Prime Video usan protección de video (DRM): en algunos proyectores el navegador '
              'integrado reproduce en calidad estándar o no reproduce. Si pasa, usá la app propia del proyector.',
              style: TextStyle(color: Colors.white30, fontSize: 10),
            ),
            const SizedBox(height: 20),
            _buildTouchpad(),
            const SizedBox(height: 16),
            _buildKeyboard(),
            const SizedBox(height: 20),
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
                      : (_connected
                          ? (_openUrl != null ? 'Mostrando: $_openUrl' : 'Control remoto conectado. El proyector abre la página solo.')
                          : (_error ?? 'Sin conexión')),
                  style: TextStyle(color: color, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        const SizedBox(height: 8),
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
      ],
    );
  }

  void _switchMode(bool desktop) {
    setState(() => _desktopMode = desktop);
    if (_openUrl != null) _open(_openUrl!);
  }

  Widget _buildTouchpad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TOUCHPAD', style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 230);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _connected ? () => _click() : null,
              onDoubleTap: _connected ? () => _click(double_: true) : null,
              onScaleStart: (d) {
                _twoFingers = d.pointerCount >= 2;
                _scrollAccum = 0;
              },
              onScaleUpdate: (d) {
                if (!_connected) return;
                if (d.pointerCount >= 2) {
                  _twoFingers = true;
                  _scrollAtCursor(-d.focalPointDelta.dy);
                } else if (!_twoFingers) {
                  _moveCursor(d.focalPointDelta, size);
                }
              },
              onScaleEnd: (_) => _twoFingers = false,
              child: Container(
                height: size.height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [neonPink.withValues(alpha: 0.12), electricCyan.withValues(alpha: 0.10)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, color: Colors.white.withValues(alpha: 0.25), size: 42),
                      const SizedBox(height: 10),
                      Text(
                        'DESLIZÁ para mover el puntero  •  TOCÁ para hacer clic\nDOBLE TOQUE = doble clic  •  DOS DEDOS = desplazar',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildKeyboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TECLADO REMOTO', style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        const Text(
          'Hacé clic en un campo del proyector con el touchpad y escribí acá. El autocompletado de tu celular '
          'te rellena usuario y contraseña; el proyector recuerda la sesión, así que iniciás sesión una sola vez.',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _typeController,
                enabled: _connected,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.send,
                autofillHints: const [AutofillHints.username, AutofillHints.password, AutofillHints.email],
                onSubmitted: (_) => _sendText(enter: true),
                decoration: InputDecoration(
                  hintText: 'Escribir en el proyector…',
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Icons.keyboard, color: goldAccent),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: goldAccent)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: goldAccent.withValues(alpha: 0.4))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: goldAccent, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _keyButton(Icons.backspace_outlined, 'BORRAR', () => _cmd('key', {'key': 'Backspace'})),
            const SizedBox(width: 6),
            _keyButton(Icons.keyboard_return, 'ENTER', () => _sendText(enter: true), color: goldAccent),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              onPressed: _connected ? () => _sendText() : null,
              icon: const Icon(Icons.send, size: 14),
              label: const Text('ENVIAR SIN ENTER', style: TextStyle(fontSize: 10)),
            ),
            TextButton.icon(
              onPressed: _connected ? () => _cmd('key', {'key': 'Tab'}) : null,
              icon: const Icon(Icons.keyboard_tab, size: 14),
              label: const Text('TAB', style: TextStyle(fontSize: 10)),
            ),
            TextButton.icon(
              onPressed: _connected ? () => _cmd('key', {'key': 'Escape'}) : null,
              icon: const Icon(Icons.close, size: 14),
              label: const Text('ESC', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _keyButton(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white70}) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _connected ? onTap : null,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NAVEGACIÓN Y VIDEO', style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 10),
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
          btn(Icons.play_arrow, 'PLAY / PAUSA', () => _cmd('playpause'), color: electricCyan),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          btn(Icons.volume_down, 'VOL −', () => _cmd('volume', {'direction': 'down'})),
          const SizedBox(width: 8),
          btn(Icons.volume_up, 'VOL +', () => _cmd('volume', {'direction': 'up'})),
          const SizedBox(width: 8),
          btn(Icons.volume_off, 'SILENCIO', () => _cmd('volume', {'direction': 'mute'})),
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
