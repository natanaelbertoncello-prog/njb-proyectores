import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_config.dart';
import 'core/app_version.dart';
import 'models/discovered_device.dart';
import 'services/discovery_service.dart';
import 'services/settings_store.dart';
import 'services/share_service.dart';
import 'services/update_service.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/receiver_mode_page.dart';
import 'ui/pages/web_cast_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle(AppConfig.appName);
    } catch (_) {}
  }
  runApp(
    const ProviderScope(
      child: ProyectarApp(),
    ),
  );
}

class ProyectarApp extends StatelessWidget {
  const ProyectarApp({super.key});

  // Colores inspirados en el logo NJB
  static const Color primaryPurple = Color(0xFF6B21A8);
  static const Color accentPink = Color(0xFFD946EF);
  static const Color goldAccent = Color(0xFFF59E0B);
  static const Color darkBg = Color(0xFF0F0716);

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: darkBg,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryPurple,
              primary: primaryPurple,
              secondary: accentPink,
              tertiary: goldAccent,
              brightness: Brightness.dark,
              surface: darkBg,
            ),
            textTheme: GoogleFonts.orbitronTextTheme(
              ThemeData.dark().textTheme,
            ).copyWith(
              bodyLarge: GoogleFonts.poppins(color: Colors.white),
              bodyMedium: GoogleFonts.poppins(color: Colors.white70),
            ),
          ),
          home: const _AppBootstrap(child: HomePage()),
        );
      },
    );
  }
}

/// Arranca las tareas de fondo que necesitan el `ProviderScope` ya montado.
class _AppBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  const _AppBootstrap({required this.child});

  @override
  ConsumerState<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<_AppBootstrap> {
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    CurrentVersion.get();
    ref.read(updateProvider.notifier).startPeriodicChecks();
    _initShare();
    _autoReceiver();
  }

  /// "Este equipo es el proyector": entra directo al modo receptor.
  Future<void> _autoReceiver() async {
    if (!await SettingsStore.getAutoReceiver()) return;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiverModePage()));
  }

  Future<void> _initShare() async {
    await ShareService.init();
    _shareSub = ShareService.stream.listen(_handleShared);
    final initial = await ShareService.takeInitial();
    if (initial != null) {
      // Le damos un momento al descubrimiento de receptores.
      await Future.delayed(const Duration(milliseconds: 1500));
      _handleShared(initial);
    }
  }

  Future<void> _handleShared(String text) async {
    final url = ShareService.extractUrl(text) ?? text.trim();
    if (url.isEmpty || !mounted) return;

    var devices = ref.read(discoveryServiceProvider).where((d) => d.isNjb).toList();
    if (devices.isEmpty) {
      // Esperar un poco al barrido de red.
      await Future.delayed(const Duration(seconds: 3));
      devices = ref.read(discoveryServiceProvider).where((d) => d.isNjb).toList();
    }
    if (!mounted) return;

    DiscoveredDevice? target;
    if (devices.length == 1) {
      target = devices.first;
    } else if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se encontró ningún proyector en modo receptor. Abrí el modo receptor y volvé a compartir.'),
      ));
      return;
    } else {
      target = await showDialog<DiscoveredDevice>(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: const Color(0xFF130D21),
          title: const Text('¿En qué proyector?', style: TextStyle(color: Colors.white, fontSize: 15)),
          children: devices
              .map((d) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, d),
                    child: Text('${d.name}  (${d.host})', style: const TextStyle(color: Colors.white70)),
                  ))
              .toList(),
        ),
      );
    }
    if (target == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebCastPage(device: target!, initialUrl: url)));
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
