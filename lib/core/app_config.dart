/// Configuración central de la app. Todo lo que antes estaba repetido
/// (puerto, nombre del servicio mDNS, etc.) vive acá.
class AppConfig {
  AppConfig._();

  static const String appName = 'NJB Proyectores';

  /// Puerto del servidor de señalización que abre el receptor.
  static const int signalingPort = 8080;

  /// Tipo de servicio mDNS que anuncia el receptor en la red.
  static const String mdnsServiceType = '_njb-mirror._tcp';

  /// Nombre con el que el receptor se anuncia en la red.
  static const String receiverServiceName = 'NJB RECEPTOR';

  /// Repositorio de GitHub (formato `usuario/repo`) desde el que se descargan
  /// las actualizaciones. Se inyecta en tiempo de compilación con
  /// `--dart-define=UPDATE_REPO=usuario/repo`.
  ///
  /// El workflow de GitHub Actions lo pasa automáticamente, así que las APK
  /// publicadas en Releases "saben" de dónde actualizarse sin tocar código.
  /// Las compilaciones locales (`tools/compilar.ps1`) lo deducen del remoto git.
  static const String updateRepo = String.fromEnvironment('UPDATE_REPO');

  static bool get updatesConfigured => updateRepo.contains('/');

  /// Cada cuánto se vuelve a consultar si hay una versión nueva.
  static const Duration updateCheckInterval = Duration(minutes: 30);

  /// Canales nativos (Android).
  static const String serviceChannel = 'com.njb.proyectores/service';
  static const String screenGuardianChannel = 'com.njb.proyectores/screen_guardian';
  static const String updaterChannel = 'com.njb.proyectores/updater';
}
