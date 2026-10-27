/// 16-bit UUIDs of the Bluetooth SIG services the simulated devices offer.
abstract final class GattServices {
  static const deviceInformation = 0x180A;
  static const healthThermometer = 0x1809;
  static const heartRate = 0x180D;
  static const battery = 0x180F;
  static const bloodPressure = 0x1810;
  static const runningSpeedAndCadence = 0x1814;
  static const cyclingSpeedAndCadence = 0x1816;
  static const cyclingPower = 0x1818;
  static const weightScale = 0x181D;
  static const pulseOximeter = 0x1822;
}

/// 16-bit UUIDs of the characteristics the simulated devices read or notify.
abstract final class GattCharacteristicIds {
  static const modelNumber = 0x2A24;
  static const firmwareRevision = 0x2A26;
  static const manufacturerName = 0x2A29;
  static const batteryLevel = 0x2A19;
  static const temperatureMeasurement = 0x2A1C;
  static const bloodPressureMeasurement = 0x2A35;
  static const heartRateMeasurement = 0x2A37;
  static const bodySensorLocation = 0x2A38;
  static const rscMeasurement = 0x2A53;
  static const cscMeasurement = 0x2A5B;
  static const plxContinuousMeasurement = 0x2A5F;
  static const cyclingPowerMeasurement = 0x2A63;
  static const weightMeasurement = 0x2A9D;
}

/// The full 128-bit form of a 16-bit Bluetooth SIG UUID, as plugins like
/// flutter_blue_plus report it.
String uuid128(int shortUuid) =>
    '0000${shortUuid.toRadixString(16).padLeft(4, '0')}'
    '-0000-1000-8000-00805f9b34fb';
