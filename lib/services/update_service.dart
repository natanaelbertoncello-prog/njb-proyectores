import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_config.dart';
import '../core/app_version.dart';

enum UpdateStatus {
  idle,
  notConfigured,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  installing,
  error,
}

class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  const ReleaseAsset({required this.name, required this.url, required this.size});
}

class ReleaseInfo {
  final AppVersion version;
  final String tagName;
  final String title;
  final String notes;
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
  });

  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name']?.toString();
    final version = AppVersion.tryParse(tag);
    if (tag == null || version == null) return null;
    final assets = <ReleaseAsset>[];
    for (final a in (json['assets'] as List? ?? [])) {
      if (a is Map) {
        assets.add(ReleaseAsset(
          name: a['name']?.toString() ?? '',
          url: a['browser_download_url']?.toString() ?? '',
          size: (a['size'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    return ReleaseInfo(
      version: version,
      tagName: tag,
      title: json['name']?.toString() ?? tag,
      notes: json['body']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      assets: assets,
    );
  }

  /// Asset correcto para este dispositivo.
  ReleaseAsset? assetFor({required List<String> abis}) {
    if (Platform.isAndroid) {
      for (final abi in abis) {
        for (final a in assets) {
          if (a.name.endsWith('.apk') && a.name.contains(abi)) return a;
        }
      }
      for (final a in assets) {
        if (a.name.endsWith('.apk') && a.name.contains('universal')) return a;
      }
      return null;
    }
    if (Platform.isWindows) {
      for (final a in assets) {
        if (a.name.contains('windows') && a.name.endsWith('.zip')) return a;
      }
    }
    return null;
  }
}

class UpdateState {
  final UpdateStatus status;
  final ReleaseInfo? release;
  final double progress;
  final String? message;
  final String? downloadedPath;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.progress = 0,
    this.message,
    this.downloadedPath,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    ReleaseInfo? release,
    double? progress,
    String? message,
    String? downloadedPath,
  }) {
    return UpdateState(
      status: status ?? this.status,
      release: release ?? this.release,
      progress: progress ?? this.progress,
      message: message,
      downloadedPath: downloadedPath ?? this.downloadedPath,
    );
  }

  bool get hasUpdate =>
      status == UpdateStatus.available ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.readyToInstall ||
      status == UpdateStatus.installing;
}

final updateProvider = StateNotifierProvider<UpdateService, UpdateState>((ref) {
  return UpdateService();
});

/// Consulta GitHub Releases, descarga la APK correcta y lanza el instalador.
///
/// En Windows sólo avisa y abre la página de descarga.
class UpdateService extends StateNotifier<UpdateState> {
  UpdateService() : super(const UpdateState());

  static const _updater = MethodChannel(AppConfig.updaterChannel);
  Timer? _timer;
  bool _busy = false;

  /// Si es `true`, en Android se descarga e instala sola al detectar versión nueva.
  bool autoInstall = true;

  void startPeriodicChecks() {
    _timer?.cancel();
    // Pequeña espera para no competir con el arranque de la app.
    Timer(const Duration(seconds: 4), () => check());
    _timer = Timer.periodic(AppConfig.updateCheckInterval, (_) => check());
  }

  Future<void> check({bool manual = false}) async {
    if (!AppConfig.updatesConfigured) {
      state = state.copyWith(
        status: UpdateStatus.notConfigured,
        message: 'Esta compilación no tiene configurado el repositorio de actualizaciones.',
      );
      return;
    }
    if (_busy) return;
    if (!manual && state.hasUpdate) return;

    _busy = true;
    state = state.copyWith(status: UpdateStatus.checking, message: 'Buscando actualizaciones…');
    try {
      final current = await CurrentVersion.get();
      final uri = Uri.https('api.github.com', '/repos/${AppConfig.updateRepo}/releases/latest');
      final response = await http.get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'njb-proyectores',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) {
        state = state.copyWith(status: UpdateStatus.upToDate, message: 'Todavía no hay versiones publicadas.');
        return;
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub respondió ${response.statusCode}');
      }

      final release = ReleaseInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      if (release == null) throw const FormatException('Respuesta de GitHub inválida');

      if (release.version > current) {
        state = state.copyWith(
          status: UpdateStatus.available,
          release: release,
          message: 'Nueva versión ${release.version} disponible (tenés ${current.toString()}).',
        );
        if (autoInstall && Platform.isAndroid) {
          _busy = false;
          await downloadAndInstall();
        }
      } else {
        state = state.copyWith(
          status: UpdateStatus.upToDate,
          release: release,
          message: 'Estás al día (v$current).',
        );
      }
    } catch (e) {
      debugPrint('Comprobación de actualización falló: $e');
      state = state.copyWith(status: UpdateStatus.error, message: 'No se pudo consultar actualizaciones: $e');
    } finally {
      _busy = false;
    }
  }

  /// Android: descarga la APK y abre el instalador del sistema.
  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null || _busy) return;

    if (!Platform.isAndroid) {
      await openReleasePage();
      return;
    }

    _busy = true;
    try {
      List<String> abis = const [];
      try {
        final result = await _updater.invokeMethod<List>('getAbis');
        abis = result?.map((e) => e.toString()).toList() ?? const [];
      } catch (_) {}

      final asset = release.assetFor(abis: abis);
      if (asset == null) {
        throw Exception('La versión ${release.version} no tiene una APK compatible con este equipo (${abis.join(', ')}).');
      }

      state = state.copyWith(status: UpdateStatus.downloading, progress: 0, message: 'Descargando ${asset.name}…');

      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/${asset.name}');
      if (await file.exists()) await file.delete();

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(asset.url));
        request.headers['User-Agent'] = 'njb-proyectores';
        final response = await client.send(request).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('Descarga falló con código ${response.statusCode}');
        }
        final total = response.contentLength ?? asset.size;
        int received = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) {
              final p = received / total;
              if ((p - state.progress) >= 0.01) {
                state = state.copyWith(
                  status: UpdateStatus.downloading,
                  progress: p,
                  message: 'Descargando ${(p * 100).toStringAsFixed(0)}%',
                );
              }
            }
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }

      state = state.copyWith(
        status: UpdateStatus.readyToInstall,
        progress: 1,
        downloadedPath: file.path,
        message: 'Descarga completa. Instalando…',
      );
      _busy = false;
      await install();
    } catch (e) {
      debugPrint('Descarga de actualización falló: $e');
      state = state.copyWith(status: UpdateStatus.error, message: 'Error al actualizar: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> install() async {
    final path = state.downloadedPath;
    if (path == null || !Platform.isAndroid) return;
    state = state.copyWith(status: UpdateStatus.installing, message: 'Confirmá la instalación en pantalla…');
    try {
      final result = await _updater.invokeMethod<String>('installApk', {'path': path});
      if (result == 'needs_permission') {
        state = state.copyWith(
          status: UpdateStatus.readyToInstall,
          message: 'Permití "Instalar apps desconocidas" para esta app y volvé a intentar.',
        );
      }
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, message: 'No se pudo iniciar la instalación: $e');
    }
  }

  Future<void> openReleasePage() async {
    final url = state.release?.htmlUrl;
    if (url == null || url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('No se pudo abrir $url: $e');
    }
  }

  void dismiss() {
    state = state.copyWith(status: UpdateStatus.idle, message: null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
