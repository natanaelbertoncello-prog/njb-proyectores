import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../core/app_config.dart';
import '../../core/app_version.dart';
import '../../services/dial_service.dart';
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

  // Navegador integrado ("proyectar una página web").
  WebViewController? _web;
  String? _webUrl;
  bool _webLoading = false;
  Widget? _webFullscreen;
  void Function()? _webFullscreenHide;

  // Puntero remoto (touchpad del celular) sobre el navegador.
  Offset _cursor = const Offset(0.5, 0.5); // fracción del tamaño de pantalla
  bool _cursorVisible = false;
  Timer? _cursorHide;

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  // youtube.com/tv sólo acepta navegadores de Smart TV.
  static const _tvUa =
      'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 76.0.3809.146/6.0 TV Safari/537.36';

  // Receptor DIAL: botón "Transmitir" de la app de YouTube.
  DialService? _dial;
  bool _youtubeCast = false;

  // Estadísticas reales de la conexión (WebRTC getStats).
  double _currentBitrateMbps = 0.0;
  int _fpsReal = 0;
  int _frameWidth = 0;
  int _frameHeight = 0;
  String _codec = '';
  double? _rttMs;
  double _prevBytesReceived = 0;
  DateTime? _prevStatsTime;
  Timer? _statsTimer;

  // Visibilidad del HUD.
  bool _showControls = true;
  Timer? _hideTimer;

  static const neonPink = Color(0xFFD946EF);
  static const goldAccent = Color(0xFFF59E0B);

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _initialize();
    _startStatsTimer();
    _startHideTimer();
    _startKeepAlive();
    if (_isDesktop) {
      // Una PC como receptor: pantalla completa, sin barra de título.
      windowManager.setFullScreen(true).catchError((_) {});
    }
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
      int w = 0, h = 0;
      String? codecId;
      final codecs = <String, String>{};

      for (final report in reports) {
        if (report.type == 'codec') {
          codecs[report.id] = (report.values['mimeType'] ?? '').toString();
        } else if (report.type == 'inbound-rtp' && report.values['kind'] == 'video') {
          bytesReceived = _asDouble(report.values['bytesReceived']);
          fps = _asDouble(report.values['framesPerSecond'])?.round();
          w = _asDouble(report.values['frameWidth'])?.toInt() ?? 0;
          h = _asDouble(report.values['frameHeight'])?.toInt() ?? 0;
          codecId = report.values['codecId']?.toString();
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
          if (w > 0) {
            _frameWidth = w;
            _frameHeight = h;
          }
          if (codecId != null) _codec = (codecs[codecId] ?? '').replaceFirst('video/', '');
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

  // ---------------------------------------------------------------------------
  // Navegador integrado
  // ---------------------------------------------------------------------------

  bool get _webSupported => !kIsWeb && Platform.isAndroid;

  WebViewController _createWebController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _webLoading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _webLoading = false);
        },
        onWebResourceError: (e) => debugPrint('WebView: ${e.description}'),
      ));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: (widget, onHidden) {
          if (!mounted) return;
          setState(() {
            _webFullscreen = widget;
            _webFullscreenHide = onHidden;
          });
        },
        onHideCustomWidget: () {
          if (!mounted) return;
          setState(() {
            _webFullscreen = null;
            _webFullscreenHide = null;
          });
        },
      );
    }
    return controller;
  }

  Future<void> _onWebCommand(Map<String, dynamic> cmd) async {
    final action = cmd['cmd']?.toString();
    debugPrint('Web: $cmd');

    if (action == 'open') {
      final url = cmd['url']?.toString();
      if (url == null || url.isEmpty) return;
      if (!_webSupported) {
        // Windows/Linux como receptor: abrimos el navegador del sistema.
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('No se pudo abrir $url: $e');
        }
        return;
      }
      await _openInWebView(url, cmd['desktop'] == false ? _mobileUa : _desktopUa);
      return;
    }

    final web = _web;
    if (web == null || _webUrl == null) return;
    try {
      switch (action) {
        case 'cursor':
          _showCursor(Offset(_frac(cmd['fx']), _frac(cmd['fy'])));
        case 'click':
        case 'dblclick':
          final at = Offset(_frac(cmd['fx']), _frac(cmd['fy']));
          _showCursor(at);
          await web.runJavaScript(_jsClick(at.dx, at.dy, double_: action == 'dblclick'));
        case 'type':
          await web.runJavaScript(_jsType(cmd['text']?.toString() ?? ''));
        case 'key':
          await web.runJavaScript(_jsKey(cmd['key']?.toString() ?? ''));
        case 'scroll':
          final dy = (cmd['dy'] as num?)?.toInt() ?? 300;
          if (cmd['fx'] != null && cmd['fy'] != null) {
            // Desplaza el contenedor que está bajo el puntero (listas internas, chats…).
            await web.runJavaScript(_jsScrollAt(_frac(cmd['fx']), _frac(cmd['fy']), dy));
          } else {
            await web.scrollBy(0, dy);
          }
        case 'top':
          await web.runJavaScript('window.scrollTo({top:0,behavior:"smooth"})');
        case 'back':
          if (await web.canGoBack()) await web.goBack();
        case 'forward':
          if (await web.canGoForward()) await web.goForward();
        case 'reload':
          await web.reload();
        case 'zoom':
          final factor = (cmd['factor'] as num?)?.toDouble() ?? 1.0;
          await web.runJavaScript('document.body.style.zoom="$factor"');
        case 'playpause':
          await web.runJavaScript(
            '(function(){var v=document.querySelector("video");if(v){if(v.paused){v.play();}else{v.pause();}}})()',
          );
        case 'volume':
          final direction = cmd['direction']?.toString() ?? 'up';
          // Volumen del sistema (Android) + volumen del video de la página.
          if (!kIsWeb && Platform.isAndroid) {
            try {
              await const MethodChannel(AppConfig.serviceChannel).invokeMethod('adjustVolume', {'direction': direction});
            } catch (_) {}
          }
          await web.runJavaScript(
            '(function(d){var v=document.querySelector("video");if(!v)return;'
            'if(d==="mute"){v.muted=!v.muted;return;}'
            'v.muted=false;v.volume=Math.max(0,Math.min(1,v.volume+(d==="up"?0.1:-0.1)));})(${jsonEncode(direction)})',
          );
        case 'fullscreen':
          await web.runJavaScript(
            '(function(){var b=document.querySelector(".ytp-fullscreen-button");if(b){b.click();return;}'
            'var v=document.querySelector("video");if(v&&v.requestFullscreen){v.requestFullscreen();}})()',
          );
        case 'close':
          _closeWeb();
      }
    } catch (e) {
      debugPrint('Orden web $action falló: $e');
    }
  }

  static double _frac(dynamic v) => ((v as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);

  void _showCursor(Offset at) {
    _cursorHide?.cancel();
    _cursorHide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _cursorVisible = false);
    });
    if (mounted) {
      setState(() {
        _cursor = at;
        _cursorVisible = true;
      });
    }
  }

  // --- JavaScript inyectado en la página -------------------------------------
  // Las coordenadas llegan como fracción (0..1) de la pantalla; la página las
  // convierte a sus propios píxeles CSS, así no importa el zoom ni la escala.

  static String _jsClick(double fx, double fy, {bool double_ = false}) => '''
(function(fx,fy,dbl){
  var x=fx*window.innerWidth, y=fy*window.innerHeight;
  var el=document.elementFromPoint(x,y); if(!el) return;
  var o={bubbles:true,cancelable:true,clientX:x,clientY:y,screenX:x,screenY:y,view:window,button:0};
  function fire(t,C){ try{ el.dispatchEvent(new C(t,o)); }catch(e){} }
  fire('pointerdown',PointerEvent); fire('mousedown',MouseEvent);
  fire('pointerup',PointerEvent); fire('mouseup',MouseEvent);
  fire('click',MouseEvent);
  if(dbl){ fire('dblclick',MouseEvent); }
  var f=el; while(f && !(f.tagName==='INPUT'||f.tagName==='TEXTAREA'||f.isContentEditable)) f=f.parentElement;
  if(f && f.focus) f.focus();
})($fx,$fy,${double_ ? 'true' : 'false'});''';

  static String _jsType(String text) => '''
(function(t){
  var el=document.activeElement; if(!el||el===document.body){ return; }
  if(el.isContentEditable){ document.execCommand('insertText',false,t); return; }
  var proto=(el.tagName==='TEXTAREA')?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
  var d=Object.getOwnPropertyDescriptor(proto,'value');
  var v=(el.value||'')+t;
  if(d&&d.set){ d.set.call(el,v); } else { el.value=v; }
  el.dispatchEvent(new Event('input',{bubbles:true}));
  el.dispatchEvent(new Event('change',{bubbles:true}));
})(${jsonEncode(text)});''';

  static String _jsKey(String key) => '''
(function(k){
  var el=document.activeElement||document.body;
  var codes={Enter:13,Backspace:8,Tab:9,Escape:27,ArrowUp:38,ArrowDown:40,ArrowLeft:37,ArrowRight:39,' ':32};
  var kc=codes[k]||0;
  var o={key:k,code:k,keyCode:kc,which:kc,bubbles:true,cancelable:true};
  var down=new KeyboardEvent('keydown',o); el.dispatchEvent(down);
  el.dispatchEvent(new KeyboardEvent('keypress',o));
  if(k==='Backspace' && !down.defaultPrevented && (el.tagName==='INPUT'||el.tagName==='TEXTAREA')){
    var proto=(el.tagName==='TEXTAREA')?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
    var d=Object.getOwnPropertyDescriptor(proto,'value'); var v=(el.value||'').slice(0,-1);
    if(d&&d.set){ d.set.call(el,v); } else { el.value=v; }
    el.dispatchEvent(new Event('input',{bubbles:true}));
  }
  if(k==='Enter' && !down.defaultPrevented && el.form && el.tagName==='INPUT'){
    if(el.form.requestSubmit){ el.form.requestSubmit(); } else { el.form.submit(); }
  }
  if(k===' ' && !down.defaultPrevented){ var v=document.querySelector('video'); if(v){ v.paused?v.play():v.pause(); } }
  el.dispatchEvent(new KeyboardEvent('keyup',o));
})(${jsonEncode(key)});''';

  static String _jsScrollAt(double fx, double fy, int dy) => '''
(function(fx,fy,dy){
  var x=fx*window.innerWidth, y=fy*window.innerHeight;
  var el=document.elementFromPoint(x,y);
  while(el){
    var s=getComputedStyle(el).overflowY;
    if((s==='auto'||s==='scroll')&&el.scrollHeight>el.clientHeight+4){ el.scrollBy({top:dy,behavior:'instant'}); return; }
    el=el.parentElement;
  }
  window.scrollBy({top:dy,behavior:'instant'});
})($fx,$fy,$dy);''';

  Future<void> _openInWebView(String url, String userAgent, {bool fromYouTubeCast = false}) async {
    if (!_webSupported) return;
    _web ??= _createWebController();
    await _web!.setUserAgent(userAgent);
    await _web!.loadRequest(Uri.parse(url));
    if (mounted) {
      setState(() {
        _webUrl = url;
        _webLoading = true;
        _showControls = false;
        _youtubeCast = fromYouTubeCast;
      });
    }
  }

  void _closeWeb() {
    _cursorHide?.cancel();
    _cursorVisible = false;
    _webFullscreenHide?.call();
    _web?.loadRequest(Uri.parse('about:blank'));
    if (_youtubeCast) _dial?.markYouTubeStopped();
    if (mounted) {
      setState(() {
        _webUrl = null;
        _webFullscreen = null;
        _webFullscreenHide = null;
        _youtubeCast = false;
        _showControls = true;
      });
      _startHideTimer();
    }
  }

  // --- YouTube "Transmitir" (DIAL) ----------------------------------------------

  Future<void> _startDial() async {
    final ip = _localIp;
    if (ip == null) return;
    final dial = DialService(
      localIp: ip,
      onLaunchYouTube: (query) {
        // YouTube manda `pairingCode=…&theme=cl&…`; youtube.com/tv usa ese
        // código para emparejarse con el celular que apretó "Transmitir".
        final url = 'https://www.youtube.com/tv${query.isNotEmpty ? '?$query' : ''}';
        if (_webSupported) {
          _openInWebView(url, _tvUa, fromYouTubeCast: true);
        } else {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
      onStopYouTube: () {
        if (_youtubeCast) _closeWeb();
      },
    );
    _dial = dial;
    await dial.start();
  }

  Future<void> _initialize() async {
    await _remoteRenderer.initialize();
    _remoteRenderer.onResize = () {
      if (mounted) setState(() {});
    };
    await CurrentVersion.get();

    _localIp = await LocalNetwork.primaryIp();

    final signaling = SignalingService();
    signaling.onPeerInfo = (peer) {
      if (mounted) setState(() => _senderPeer = peer);
    };
    signaling.onDisconnected = _onSenderLost;
    signaling.onWebCommand = _onWebCommand;
    _signalingService = signaling;

    try {
      await signaling.startServer(
        extraHandler: (request) async => _dial?.handle(request),
        onRemoteStream: (stream) {
          if (!mounted) return;
          // Llega video: si había una página web abierta, la cerramos.
          if (_webUrl != null) _closeWeb();
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

    await _startDial();

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
      _frameWidth = 0;
      _frameHeight = 0;
      _codec = '';
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
    _cursorHide?.cancel();
    ScreenGuardian.stop();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _remoteRenderer.srcObject = null;
    _remoteRenderer.dispose();
    _webFullscreenHide?.call();
    _dial?.dispose();
    _signalingService?.dispose();
    _broadcast?.stop();
    if (_isDesktop) windowManager.setFullScreen(false).catchError((_) {});
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

              // Navegador integrado, por encima del video o de la espera.
              if (_webUrl != null && _web != null)
                Positioned.fill(child: WebViewWidget(controller: _web!)),
              if (_webUrl != null && _webLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 3, color: neonPink, backgroundColor: Colors.transparent),
                ),
              // Video en pantalla completa pedido por la página (YouTube, etc.)
              if (_webFullscreen != null) Positioned.fill(child: _webFullscreen!),

              // Puntero del touchpad remoto.
              if (_webUrl != null && _cursorVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(
                        children: [
                          Positioned(
                            left: _cursor.dx * c.maxWidth - 4,
                            top: _cursor.dy * c.maxHeight - 2,
                            child: const _RemoteCursor(),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                icon: Icon(_webUrl != null ? Icons.web_asset_off : Icons.close, color: Colors.white),
                                tooltip: _webUrl != null ? 'Cerrar página web' : 'Salir del modo receptor',
                                onPressed: () => _webUrl != null ? _closeWeb() : Navigator.pop(context),
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
                                    '${_frameWidth > 0 ? '${_frameWidth}x$_frameHeight' : _settings.resolution} @ ${_fpsReal}FPS | ${_currentBitrateMbps.toStringAsFixed(1)} Mbps'
                                    '${_codec.isNotEmpty ? ' | $_codec' : ''}'
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

    final Widget video;
    switch (_settings.fitMode) {
      case 'cover':
        video = RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: false,
          filterQuality: FilterQuality.high,
        );
      case 'stretch':
        final vw = _remoteRenderer.videoWidth.toDouble();
        final vh = _remoteRenderer.videoHeight.toDouble();
        video = vw > 0 && vh > 0
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: vw,
                    height: vh,
                    child: RTCVideoView(
                      _remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      mirror: false,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              )
            : RTCVideoView(_remoteRenderer, mirror: false, filterQuality: FilterQuality.high);
      default:
        video = RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          mirror: false,
          filterQuality: FilterQuality.high,
        );
    }

    // Con los ajustes en neutro evitamos cuatro pasadas de filtro de color:
    // en proyectores con GPU débil se nota en la fluidez.
    if (isNeutral) {
      return Container(color: Colors.black, child: SizedBox.expand(child: video));
    }

    return Container(
      color: Colors.black,
      child: SizedBox.expand(
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
          if (_dial != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.cast, color: Colors.white38, size: 14),
                SizedBox(width: 6),
                Text(
                  'También aparece en el botón "Transmitir" de la app de YouTube',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Flecha de mouse clásica (blanca con borde negro) para el puntero remoto.
class _RemoteCursor extends StatelessWidget {
  const _RemoteCursor();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(26, 34), painter: _CursorPainter());
  }
}

class _CursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 24)
      ..lineTo(6, 19)
      ..lineTo(10, 30)
      ..lineTo(14, 28)
      ..lineTo(10, 18)
      ..lineTo(18, 18)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
