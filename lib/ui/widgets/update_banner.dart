import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/update_service.dart';

/// Tarjeta que aparece cuando hay una versión nueva (o mientras se descarga).
class UpdateBanner extends ConsumerWidget {
  final bool compact;
  const UpdateBanner({super.key, this.compact = false});

  static const goldAccent = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider);
    final show = update.hasUpdate || (update.status == UpdateStatus.error && update.release != null);
    if (!show) return const SizedBox.shrink();

    final notifier = ref.read(updateProvider.notifier);
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final canSelfInstall = !kIsWeb && (Platform.isAndroid || Platform.isWindows);
    final version = update.release?.version.toString() ?? '';

    String title;
    IconData icon;
    switch (update.status) {
      case UpdateStatus.downloading:
        title = 'DESCARGANDO VERSIÓN $version';
        icon = Icons.downloading;
      case UpdateStatus.readyToInstall:
      case UpdateStatus.installing:
        title = 'INSTALANDO VERSIÓN $version';
        icon = Icons.system_update;
      case UpdateStatus.error:
        title = 'ERROR AL ACTUALIZAR';
        icon = Icons.error_outline;
      default:
        title = 'NUEVA VERSIÓN $version DISPONIBLE';
        icon = Icons.new_releases;
    }

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 0 : 16),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 12),
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: const Color(0xFF130D21).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: goldAccent.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: goldAccent.withValues(alpha: 0.2), blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: goldAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                ),
              ),
              if (update.status == UpdateStatus.available || update.status == UpdateStatus.error)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: notifier.dismiss,
                ),
            ],
          ),
          if (update.message != null) ...[
            const SizedBox(height: 4),
            Text(update.message!, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
          if (update.status == UpdateStatus.downloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: update.progress > 0 ? update.progress : null,
                minHeight: 5,
                color: goldAccent,
                backgroundColor: Colors.white10,
              ),
            ),
          ],
          if (update.status == UpdateStatus.available ||
              update.status == UpdateStatus.readyToInstall ||
              update.status == UpdateStatus.error) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(canSelfInstall ? Icons.system_update : Icons.open_in_new, size: 14),
                  label: Text(
                    update.status == UpdateStatus.readyToInstall
                        ? 'INSTALAR'
                        : (canSelfInstall ? 'ACTUALIZAR AHORA' : 'DESCARGAR'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                  onPressed: () {
                    if (update.status == UpdateStatus.readyToInstall) {
                      notifier.install();
                    } else {
                      notifier.downloadAndInstall();
                    }
                  },
                ),
                if (!isAndroid) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: notifier.openReleasePage,
                    child: const Text('VER NOVEDADES', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
