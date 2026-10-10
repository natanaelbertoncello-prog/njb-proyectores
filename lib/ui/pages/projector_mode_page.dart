import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/mirroring_manager.dart';
import '../widgets/source_picker_dialog.dart';
import '../widgets/mirroring_settings_panel.dart';

class ProjectorModePage extends ConsumerStatefulWidget {
  final String? receiverIp;
  const ProjectorModePage({super.key, this.receiverIp});

  @override
  ConsumerState<ProjectorModePage> createState() => _ProjectorModePageState();
}

class _ProjectorModePageState extends ConsumerState<ProjectorModePage> {
  bool _showControls = true;
  Timer? _hideTimer;

  static const neonPink = Color(0xFFD946EF);
  static const electricCyan = Color(0xFF06B6D4);
  static const goldAccent = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMirroring();
    });
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _handleInteraction() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
  }

  Future<void> _initializeMirroring() async {
    if (ref.read(mirroringProvider).status == MirroringStatus.mirroring) {
      return;
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final source = await showDialog<DesktopCapturerSource>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const SourcePickerDialog(),
      );

      if (source != null) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          ref.read(mirroringProvider.notifier).startMirroring(
            source: source,
            receiverIp: widget.receiverIp,
          );
        }
      } else {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } else {
      ref.read(mirroringProvider.notifier).startMirroring(
        receiverIp: widget.receiverIp,
      );
    }
  }

  void _showSettings() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF130D21),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => const MirroringSettingsPanel(),
    ).then((_) => _startHideTimer());
  }

  @override
  Widget build(BuildContext context) {
    final mirroringState = ref.watch(mirroringProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. VIDEO RENDERER
          Center(
            child: _buildMirroringContent(mirroringState),
          ),
          
          // 2. INTERACTION MOUSE/GESTURE DETECTOR
          Positioned.fill(
            child: MouseRegion(
              onHover: (_) => _handleInteraction(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _handleInteraction,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          
          // 3. HUD GLASSMORPHIC CONTROLS
          IgnorePointer(
            ignoring: !_showControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Stack(
                children: [
                  // Top Glass Backdrop
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 120,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top Action Bar
                  Positioned(
                    top: 40,
                    left: 20,
                    right: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ...[
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  _hideTimer?.cancel();
                                  final source = await showDialog<DesktopCapturerSource>(
                                    context: context,
                                    builder: (context) => const SourcePickerDialog(),
                                  );
                                  if (source != null && mounted) {
                                    ref.read(mirroringProvider.notifier).startMirroring(
                                      source: source,
                                      receiverIp: widget.receiverIp,
                                    );
                                  }
                                  _startHideTimer();
                                },
                                icon: const Icon(Icons.swap_horiz, size: 16),
                                label: Text(
                                  mirroringState.lastSource != null && !mirroringState.lastSource!.id.contains('screen')
                                      ? 'CAMBIAR VENTANA'
                                      : 'CAMBIAR PANTALLA',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: neonPink,
                                  foregroundColor: Colors.black,
                                  elevation: 6,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                              ),
                            ],
                          ],
                        ),

                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                elevation: 6,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              icon: const Icon(Icons.stop, size: 16),
                              label: const Text('DETENER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              onPressed: () {
                                ref.read(mirroringProvider.notifier).stopMirroring();
                                Navigator.of(context).pop();
                              },
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: electricCyan),
                                ),
                                child: const Icon(Icons.tune, color: electricCyan, size: 20),
                              ),
                              onPressed: _showSettings,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bottom HUD Status Bar
                  Positioned(
                    bottom: 30,
                    left: 20,
                    right: 20,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: electricCyan.withValues(alpha: 0.5), width: 1),
                          boxShadow: [
                            BoxShadow(color: electricCyan.withValues(alpha: 0.2), blurRadius: 12)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "PROYECTANDO EN ${mirroringState.settings.resolution} @ ${mirroringState.settings.fps}FPS"
                              "${mirroringState.receiverPeer != null ? '  →  ${mirroringState.receiverPeer!.name} v${mirroringState.receiverPeer!.version}' : (widget.receiverIp != null ? '  →  ${widget.receiverIp}' : '')}",
                              style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                            ),
                            if (mirroringState.settings.isAntiScreensaverEnabled) ...[
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: goldAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(Icons.shield, color: Colors.black, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      "ANTI-SCREENSAVER ACTIVO",
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMirroringContent(MirroringState state) {
    switch (state.status) {
      case MirroringStatus.idle:
      case MirroringStatus.connecting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(strokeWidth: 3, color: neonPink),
            ),
            const SizedBox(height: 24),
            Text(
              'INICIANDO TRANSMISIÓN NJB...',
              style: GoogleFonts.orbitron(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            if (state.statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                state.statusMessage!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      case MirroringStatus.mirroring:
        return RTCVideoView(
          state.localRenderer!,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        );
      case MirroringStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 70),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                state.errorMessage ?? 'Error desconocido',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _initializeMirroring(),
              style: ElevatedButton.styleFrom(backgroundColor: neonPink, foregroundColor: Colors.black),
              child: const Text('REINTENTAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
    }
  }
}
