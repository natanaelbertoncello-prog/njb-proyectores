import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/app_config.dart';
import 'core/app_version.dart';
import 'services/update_service.dart';
import 'ui/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  @override
  void initState() {
    super.initState();
    CurrentVersion.get();
    ref.read(updateProvider.notifier).startPeriodicChecks();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
