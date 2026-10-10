enum DeviceType { light, switch_, sensor, curtain, projector }

class SmartDevice {
  final String id;
  final String name;
  final DeviceType type;
  bool isOn;
  double value; // For brightness, temperature, or curtain position

  SmartDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isOn = false,
    this.value = 0.0,
  });

  SmartDevice copyWith({
    String? id,
    String? name,
    DeviceType? type,
    bool? isOn,
    double? value,
  }) {
    return SmartDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isOn: isOn ?? this.isOn,
      value: value ?? this.value,
    );
  }
}
