import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/smart_device.dart';
import '../../services/iot_service.dart';

class DeviceCard extends ConsumerWidget {
  final SmartDevice device;

  const DeviceCard({super.key, required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accentPink = Color(0xFFD946EF);
    const primaryPurple = Color(0xFF6B21A8);

    return GestureDetector(
      onTap: () => ref.read(iotServiceProvider.notifier).toggleDevice(device.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: device.isOn ? primaryPurple.withValues(alpha: 0.15) : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: device.isOn ? accentPink : Colors.white.withValues(alpha: 0.05),
            width: 2,
          ),
          boxShadow: device.isOn ? [
            BoxShadow(
              color: accentPink.withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  _getIcon(device.type),
                  color: device.isOn ? accentPink : Colors.white.withValues(alpha: 0.5),
                  size: 28,
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: device.isOn,
                    onChanged: (_) => ref.read(iotServiceProvider.notifier).toggleDevice(device.id),
                    activeThumbColor: accentPink,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              device.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              device.isOn ? 'Activado' : 'Desactivado',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(DeviceType type) {
    switch (type) {
      case DeviceType.light:
        return Icons.lightbulb_outline;
      case DeviceType.curtain:
        return Icons.curtains;
      case DeviceType.projector:
        return Icons.videocam_outlined;
      case DeviceType.switch_:
        return Icons.power_settings_new;
      case DeviceType.sensor:
        return Icons.sensors;
    }
  }
}
