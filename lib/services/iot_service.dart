import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/smart_device.dart';

final iotServiceProvider = StateNotifierProvider<IotService, List<SmartDevice>>((ref) {
  return IotService();
});

/// Control de domótica (luces, cortinas, encendido del proyector).
///
/// Todavía no hay integración real (MQTT / Tuya / Home Assistant), así que la
/// lista arranca vacía y la sección no se muestra en la pantalla principal.
/// Antes había dispositivos de ejemplo que no hacían nada y confundían.
class IotService extends StateNotifier<List<SmartDevice>> {
  IotService() : super(const []);

  void toggleDevice(String id) {
    state = [
      for (final device in state)
        if (device.id == id) device.copyWith(isOn: !device.isOn) else device,
    ];
  }

  void updateValue(String id, double value) {
    state = [
      for (final device in state)
        if (device.id == id) device.copyWith(value: value) else device,
    ];
  }
}
