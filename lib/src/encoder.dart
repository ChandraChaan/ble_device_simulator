import 'dart:convert';
import 'dart:math' as math;

/// Builds characteristic values in the byte layouts the Bluetooth SIG specs
/// define, the same bytes a real device would send.
abstract final class GattEncoder {
  /// Heart Rate Measurement (0x2A37).
  ///
  /// [skinContact] null means the sensor doesn't report contact. Rates above
  /// 255 bpm are sent in the 16-bit format.
  static List<int> heartRate({
    required int bpm,
    bool? skinContact,
    int? energyExpendedKj,
    List<double> rrIntervalsMs = const [],
  }) {
    var flags = 0;
    if (bpm > 0xFF) flags |= 0x01;
    if (skinContact != null) flags |= skinContact ? 0x06 : 0x04;
    if (energyExpendedKj != null) flags |= 0x08;
    if (rrIntervalsMs.isNotEmpty) flags |= 0x10;
    return [
      flags,
      if (bpm > 0xFF) ...uint16(bpm) else bpm,
      if (energyExpendedKj != null) ...uint16(energyExpendedKj),
      for (final rr in rrIntervalsMs) ...uint16((rr * 1024 / 1000).round()),
    ];
  }

  /// Blood Pressure Measurement (0x2A35).
  static List<int> bloodPressure({
    required double systolic,
    required double diastolic,
    double? meanArterialPressure,
    bool kPa = false,
    DateTime? timestamp,
    double? pulseRate,
    int? userId,
  }) {
    final mean = meanArterialPressure ?? diastolic + (systolic - diastolic) / 3;
    final decimals = kPa ? 1 : 0;
    var flags = kPa ? 0x01 : 0;
    if (timestamp != null) flags |= 0x02;
    if (pulseRate != null) flags |= 0x04;
    if (userId != null) flags |= 0x08;
    return [
      flags,
      ...sfloat(systolic, decimals),
      ...sfloat(diastolic, decimals),
      ...sfloat(mean, decimals),
      if (timestamp != null) ...dateTime(timestamp),
      if (pulseRate != null) ...sfloat(pulseRate, 0),
      if (userId != null) userId,
    ];
  }

  /// Temperature Measurement (0x2A1C).
  ///
  /// [type] is the body site code from the spec, such as 2 for body or 3 for
  /// ear.
  static List<int> temperature({
    required double value,
    bool fahrenheit = false,
    DateTime? timestamp,
    int? type,
  }) {
    var flags = fahrenheit ? 0x01 : 0;
    if (timestamp != null) flags |= 0x02;
    if (type != null) flags |= 0x04;
    return [
      flags,
      ...float(value, 2),
      if (timestamp != null) ...dateTime(timestamp),
      if (type != null) type,
    ];
  }

  /// PLX Continuous Measurement (0x2A5F).
  static List<int> pulseOximeter({
    required double spo2,
    required double pulseRate,
    double? perfusionIndex,
  }) {
    return [
      perfusionIndex == null ? 0 : 0x10,
      ...sfloat(spo2, 0),
      ...sfloat(pulseRate, 0),
      if (perfusionIndex != null) ...sfloat(perfusionIndex, 1),
    ];
  }

  /// Weight Measurement (0x2A9D), in kilograms or, with [imperial], pounds.
  ///
  /// [height] is in meters, or inches with [imperial], and is sent together
  /// with [bmi].
  static List<int> weight({
    required double weight,
    bool imperial = false,
    DateTime? timestamp,
    int? userId,
    double? bmi,
    double? height,
  }) {
    var flags = imperial ? 0x01 : 0;
    if (timestamp != null) flags |= 0x02;
    if (userId != null) flags |= 0x04;
    if (bmi != null && height != null) flags |= 0x08;
    return [
      flags,
      ...uint16((weight * (imperial ? 100 : 200)).round()),
      if (timestamp != null) ...dateTime(timestamp),
      if (userId != null) userId,
      if (bmi != null && height != null) ...[
        ...uint16((bmi * 10).round()),
        ...uint16((height * (imperial ? 10 : 1000)).round()),
      ],
    ];
  }

  /// Cycling Speed and Cadence Measurement (0x2A5B). Event times are in
  /// 1/1024ths of a second.
  static List<int> cyclingSpeedAndCadence({
    int? wheelRevolutions,
    int? lastWheelEventTime,
    int? crankRevolutions,
    int? lastCrankEventTime,
  }) {
    final wheel = wheelRevolutions != null && lastWheelEventTime != null;
    final crank = crankRevolutions != null && lastCrankEventTime != null;
    return [
      (wheel ? 0x01 : 0) | (crank ? 0x02 : 0),
      if (wheel) ...[
        ...uint32(wheelRevolutions % 0x100000000),
        ...uint16(lastWheelEventTime % 0x10000),
      ],
      if (crank) ...[
        ...uint16(crankRevolutions % 0x10000),
        ...uint16(lastCrankEventTime % 0x10000),
      ],
    ];
  }

  /// Cycling Power Measurement (0x2A63), with optional crank data. Crank
  /// event times are in 1/1024ths of a second.
  static List<int> cyclingPower({
    required int watts,
    int? crankRevolutions,
    int? lastCrankEventTime,
  }) {
    final crank = crankRevolutions != null && lastCrankEventTime != null;
    return [
      ...uint16(crank ? 0x0020 : 0),
      ...uint16(watts & 0xFFFF),
      if (crank) ...[
        ...uint16(crankRevolutions % 0x10000),
        ...uint16(lastCrankEventTime % 0x10000),
      ],
    ];
  }

  /// RSC Measurement (0x2A53).
  static List<int> runningSpeedAndCadence({
    required double speedMps,
    required int cadence,
    double? strideLengthM,
    double? totalDistanceM,
    bool running = false,
  }) {
    var flags = running ? 0x04 : 0;
    if (strideLengthM != null) flags |= 0x01;
    if (totalDistanceM != null) flags |= 0x02;
    return [
      flags,
      ...uint16((speedMps * 256).round()),
      cadence,
      if (strideLengthM != null) ...uint16((strideLengthM * 100).round()),
      if (totalDistanceM != null) ...uint32((totalDistanceM * 10).round()),
    ];
  }

  /// Battery Level (0x2A19).
  static List<int> batteryLevel(int percent) => [percent.clamp(0, 100)];

  /// A UTF-8 string, such as Manufacturer Name (0x2A29).
  static List<int> string(String value) => utf8.encode(value);

  static List<int> uint16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

  static List<int> uint32(int value) => [
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ];

  /// IEEE 11073 16-bit SFLOAT with [decimals] decimal places.
  static List<int> sfloat(double value, int decimals) {
    final mantissa = (value * math.pow(10, decimals)).round();
    return uint16(((-decimals & 0xF) << 12) | (mantissa & 0x0FFF));
  }

  /// IEEE 11073 32-bit FLOAT with [decimals] decimal places.
  static List<int> float(double value, int decimals) {
    final mantissa = (value * math.pow(10, decimals)).round();
    return [
      ...uint16(mantissa & 0xFFFF),
      (mantissa >> 16) & 0xFF,
      -decimals & 0xFF,
    ];
  }

  /// GATT Date Time: year, month, day, hours, minutes, seconds.
  static List<int> dateTime(DateTime time) => [
        ...uint16(time.year),
        time.month,
        time.day,
        time.hour,
        time.minute,
        time.second,
      ];
}
