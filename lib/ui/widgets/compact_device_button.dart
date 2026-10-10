import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/smart_device.dart';
import '../../services/iot_service.dart';

class CompactDeviceButton extends ConsumerWidget {
  final SmartDevice device;

  const CompactDeviceButton({super.key, required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accentPink = Color(0xFFD946EF);
    const goldAccent = Color(0xFFF59E0B);
    
    final activeColor = device.type == DeviceType.projector ? goldAccent : accentPink;

    return GestureDetector(
      onTap: () => ref.read(iotServiceProvider.notifier).toggleDevice(device.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: device.isOn ? activeColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: device.isOn ? activeColor : Colors.white.withValues(alpha: 0.1),
            width: 1.5,
          ),
          boxShadow: device.isOn ? [
            BoxShadow(
              color: activeColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIcon(device.type),
              color: device.isOn ? activeColor : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                device.name,
                style: TextStyle(
                  color: device.isOn ? Colors.white : Colors.white70,
                  fontWeight: device.isOn ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: device.isOn ? activeColor : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: device.isOn ? [
                  BoxShadow(color: activeColor, blurRadius: 4)
                ] : [],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(DeviceType type) {
    switch (type) {
      case DeviceType.light: return Icons.lightbulb_outline;
      case DeviceType.curtain: return Icons.curtains;
      case DeviceType.projector: return Icons.videocam_outlined;
      case DeviceType.switch_: return Icons.power_settings_new;
      case DeviceType.sensor: return Icons.sensors;
    }
  }
}
