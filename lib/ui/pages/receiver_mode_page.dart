import 'dart:math' as math;
import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/app_config.dart';
import '../../core/app_version.dart';
import '../../services/local_network.dart';
import '../../services/screen_guardian.dart';
import '../../services/signaling_service.dart';
import '../../models/mirroring_settings.dart';
import '../widgets/update_banner.dart';

/// Pantalla que corre en el proyector: espera un emisor y muestra su video.
class ReceiverModePage extends ConsumerStatefulWidget {
  const ReceiverModePage({super.key});

  @override
  ConsumerState<ReceiverModePage> createState() => _ReceiverModePageState();
}

class _ReceiverModePageState extends ConsumerState<ReceiverModePage> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  SignalingService? _signalingService;
  BonsoirBroadcast? _broadcast;
  String? _localIp;
  String? _startupError;
  bool _isConnected = false;
  String? _lastDisconnectReason;
  PeerInfo? _senderPeer;
  MirroringSettings _settings = MirroringSettings();

  // Guardián anti-screensaver (nativo en Android).
  ScreenGuardianStatus _guardian = const ScreenGuardianStatus();
  Timer? _guardianRefresh;

  // Estadísticas reales de la conexión (WebRTC getStats).
  double _currentBitrateMbps = 0.0;
  int _fpsReal = 0;
  double? _rttMs;
  double _prevBytesReceived = 0;
  DateTime? _prevStatsTime;
  Timer? _statsTimer;

  // Visibilidad del HUD.
  bool _showControls = true;
  Timer? _hideTimer;

  static const neonPink = Color(0xFFD946EF);
  static const goldAccent = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _initialize();
    _startStatsTimer();
    _startHideTimer();
    _startKeepAlive();
  }

  // ---------------------------------------------------------------------------
  // Anti-screensaver
  // ---------------------------------------------------------------------------

  Future<void> _startKeepAlive() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock: $e');
    }

    // Si la app recibió permisos por ADB, esto apaga el screensaver del sistema
    // de forma permanente. Si no, no hace nada y seguimos con las otras capas.
    await ScreenGuardian.applySystemSettings();
    await _applyGuardian();

    _guardianRefresh = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      final status = await ScreenGuardian.status();
      if (mounted) setState(() => _guardian = status);
    });
  }

  Future<void> _applyGuardian() async {
    final status = _settings.isAntiScreensaverEnabled
        ? await ScreenGuardian.start()
        : await (() async {
            await ScreenGuardian.stop();
            return ScreenGuardian.status();
          })();
    if (mounted) setState(() => _guardian = status);
  }

  // ---------------------------------------------------------------------------
  // HUD
  // ---------------------------------------------------------------------------

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _handleInteraction() {
    if (!_showControls) setState(() => _showControls = true);
    _startHideTimer();
  }

  void _handleHover(PointerHoverEvent event) {
    // El guardián nativo inyecta un movimiento de mouse en la esquina (0,0)
    // para mantener despierto al proyector; no debe mostrar el HUD.
    if (event.position.dx <= 4 && event.position.dy <= 4) return;
    _handleInteraction();
  }

  // ---------------------------------------------------------------------------
  // Estadísticas
  // ---------------------------------------------------------------------------

  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final pc = _signalingService?.peerConnection;
      if (!_isConnected || pc == null) return;

      List<StatsReport> reports;
      try {
        reports = await pc.getStats();
      } catch (_) {
        return;
      }
      double? bytesReceived;
      int? fps;
      double? rttMs;

      for (final report in reports) {
        if (report.type == 'inbound-rtp' && report.values['kind'] == 'video') {
          bytesReceived = _asDouble(report.values['bytesReceived']);
          fps = _asDouble(report.values['framesPerSecond'])?.round();
        } else if (report.type == 'candidate-pair' &&
            report.values['state'] == 'succeeded' &&
            report.values['currentRoundTripTime'] != null) {
          rttMs = (_asDouble(report.values['currentRoundTripTime']) ?? 0) * 1000;
        }
      }

      final now = DateTime.now();
      double bitrateMbps = _currentBitrateMbps;
      if (bytesReceived != null && _prevStatsTime != null) {
        final seconds = now.difference(_prevStatsTime!).inMilliseconds / 1000;
        if (seconds > 0) {
          bitrateMbps = ((bytesReceived - _prevBytesReceived) * 8) / seconds / 1000000;
        }
      }
      if (bytesReceived != null) {
        _prevBytesReceived = bytesReceived;
        _prevStatsTime = now;
      }

      if (mounted) {
        setState(() {
          _currentBitrateMbps = bitrateMbps < 0 ? 0 : bitrateMbps;
          if (fps != null) _fpsReal = fps;
          _rttMs = rttMs;
        });
      }
    });
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  // ---------------------------------------------------------------------------
  // Servidor
  // ---------------------------------------------------------------------------

  Future<void> _initialize() async {
    await _remoteRenderer.initialize();
    await CurrentVersion.get();

    _localIp = await LocalNetwork.primaryIp();

    final signaling = SignalingService();
    signaling.onPeerInfo = (peer) {
      if (mounted) setState(() => _senderPeer = peer);
    };
    signaling.onDisconnected = _onSenderLost;
    _signalingService = signaling;

    try {
      await signaling.startServer(
        onRemoteStream: (stream) {
          if (!mounted) return;
          setState(() {
            _remoteRenderer.srcObject = stream;
            _isConnected = true;
            _lastDisconnectReason = null;
            _prevBytesReceived = 0;
            _prevStatsTime = null;
          });
        },
        onSettings: (newSettings) {
          if (!mounted) return;
          final guardianChanged = newSettings.isAntiScreensaverEnabled != _settings.isAntiScreensaverEnabled;
          setState(() => _settings = newSettings);
          if (guardianChanged) _applyGuardian();
        },
      );
    } catch (e) {
      debugPrint('No se pudo iniciar el servidor receptor: $e');
      if (mounted) {
        setState(() => _startupError = 'No se pudo abrir el puerto ${AppConfig.signalingPort}: $e');
      }
      return;
    }

    try {
      _broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: AppConfig.receiverServiceName,
          type: AppConfig.mdnsServiceType,
          port: AppConfig.signalingPort,
        ),
      );
      await _broadcast!.initialize();
      await _broadcast!.start();
    } catch (e) {
      // Sin mDNS igual nos encuentran por barrido de red o IP manual.
      debugPrint('Anuncio mDNS no disponible: $e');
    }

    if (mounted) setState(() {});
  }

  void _onSenderLost(String reason) {
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _remoteRenderer.srcObject = null;
      _lastDisconnectReason = reason;
      _senderPeer = null;
      _fpsReal = 0;
      _currentBitrateMbps = 0;
      _rttMs = null;
      _showControls = true;
    });
    _startHideTimer();
  }

  @override
  void dispose() {
    _guardianRefresh?.cancel();
    _statsTimer?.cancel();
    _hideTimer?.cancel();
    ScreenGuardian.stop();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _remoteRenderer.srcObject = null;
    _remoteRenderer.dispose();
    _signalingService?.dispose();
    _broadcast?.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleInteraction,
        child: MouseRegion(
          onHover: _handleHover,
          child: Stack(
            children: [
              Center(
                child: _isConnected ? _buildFilteredVideo() : _buildWaitingUI(),
              ),

              // Aviso de actualización (siempre visible, aunque el HUD esté oculto).
              const Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(child: UpdateBanner(compact: true)),
              ),

              IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 40,
                        left: 20,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        top: 40,
                        right: 20,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPill(
                              icon: _guardian.systemScreensaverDisabled ? Icons.verified : Icons.shield,
                              text: _settings.isAntiScreensaverEnabled || _guardian.systemScreensaverDisabled
                                  ? _guardian.summary
                                  : 'PROTECCIÓN DESACTIVADA',
                              color: _settings.isAntiScreensaverEnabled || _guardian.systemScreensaverDisabled
                                  ? goldAccent
                                  : Colors.white24,
                              textColor: Colors.black,
                            ),
                            const SizedBox(width: 8),
                            if (_isConnected)
                              _buildPill(
                                icon: Icons.circle,
                                text: 'RECEPTOR EN VIVO',
                                color: Colors.redAccent,
                                textColor: Colors.white,
                              ),
                          ],
                        ),
                      ),

                      if (_isConnected)
                        Positioned(
                          bottom: 24,
                          left: 20,
                          right: 20,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: neonPink.withValues(alpha: 0.6), width: 1),
                                  ),
                                  child: Text(
                                    '${_settings.resolution} @ ${_fpsReal}FPS | ${_currentBitrateMbps.toStringAsFixed(1)} Mbps'
                                    '${_senderPeer != null ? ' | EMISOR ${_senderPeer!.platform.toUpperCase()} v${_senderPeer!.version}' : ''}',
                                    style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6)),
                                ),
                                child: Text(
                                  _rttMs != null ? 'LATENCIA: ${_rttMs!.toStringAsFixed(0)}ms' : 'LATENCIA: --',
                                  style: GoogleFonts.orbitron(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill({required IconData icon, required String text, required Color color, required Color textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 10),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredVideo() {
    final double exp = math.pow(2.0, _settings.exposure).toDouble();
    final double b = _settings.brightness * exp;
    final List<double> brightnessMatrix = <double>[
      b, 0.0, 0.0, 0.0, 0.0,
      0.0, b, 0.0, 0.0, 0.0,
      0.0, 0.0, b, 0.0, 0.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];

    final double c = _settings.contrast + (_settings.sharpness * 0.6);
    final double off = 0.5 * (1.0 - c);
    final List<double> contrastMatrix = <double>[
      c, 0.0, 0.0, 0.0, off * 255.0,
      0.0, c, 0.0, 0.0, off * 255.0,
      0.0, 0.0, c, 0.0, off * 255.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];

    final double s = _settings.saturation;
    final double invS = 1.0 - s;
    final double r = 0.2126 * invS;
    final double g = 0.7152 * invS;
    final double bl = 0.0722 * invS;
    final List<double> saturationMatrix = <double>[
      r + s, g, bl, 0.0, 0.0,
      r, g + s, bl, 0.0, 0.0,
      r, g, bl + s, 0.0, 0.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];

    final double hue = _settings.hue;
    final double cosVal = math.cos(hue);
    final double sinVal = math.sin(hue);
    const double lumR = 0.213;
    const double lumG = 0.715;
    const double lumB = 0.072;
    final List<double> hueMatrix = <double>[
      lumR + cosVal * (1 - lumR) + sinVal * (-lumR), lumG + cosVal * (-lumG) + sinVal * (-lumG), lumB + cosVal * (-lumB) + sinVal * (1 - lumB), 0, 0,
      lumR + cosVal * (-lumR) + sinVal * (0.143), lumG + cosVal * (1 - lumG) + sinVal * (0.140), lumB + cosVal * (-lumB) + sinVal * (-0.283), 0, 0,
      lumR + cosVal * (-lumR) + sinVal * (-(1 - lumR)), lumG + cosVal * (-lumG) + sinVal * (lumG), lumB + cosVal * (1 - lumB) + sinVal * (lumB), 0, 0,
      0, 0, 0, 1, 0,
    ];

    final bool isNeutral = _settings.brightness == 1.0 &&
        _settings.contrast == 1.0 &&
        _settings.saturation == 1.0 &&
        _settings.sharpness == 0.0 &&
        _settings.hue == 0.0 &&
        _settings.exposure == 0.0;

    final video = RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      mirror: false,
      filterQuality: FilterQuality.high,
    );

    // Con los ajustes en neutro evitamos cuatro pasadas de filtro de color:
    // en proyectores con GPU débil se nota en la fluidez.
    if (isNeutral) {
      return Container(color: Colors.black, child: Center(child: video));
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(hueMatrix),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(brightnessMatrix),
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(contrastMatrix),
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(saturationMatrix),
                child: video,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingUI() {
    final version = CurrentVersion.label;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [Color(0xFF2E1065), Colors.black],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo.png', height: 130),
          const SizedBox(height: 36),
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: neonPink),
          ),
          const SizedBox(height: 24),
          Text(
            'MODO RECEPTOR NJB',
            style: GoogleFonts.orbitron(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: goldAccent.withValues(alpha: 0.5)),
            ),
            child: Text(
              _startupError ??
                  (_localIp != null
                      ? 'IP: $_localIp:${AppConfig.signalingPort}  |  Esperando conexión…'
                      : 'Obteniendo dirección IP de red local…'),
              style: GoogleFonts.orbitron(
                color: _startupError != null ? Colors.redAccent : goldAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (_lastDisconnectReason != null) ...[
            const SizedBox(height: 12),
            Text(
              'Última sesión: $_lastDisconnectReason',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Abrí la app en tu PC o celular y elegí este receptor  •  $version',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
