import 'package:ble_device_simulator/ble_device_simulator.dart';
import 'package:ble_gatt_parser/ble_gatt_parser.dart';
import 'package:test/test.dart';

// Every encoder is checked by parsing its bytes with ble_gatt_parser, an
// independent implementation of the same Bluetooth SIG specs.
void main() {
  final time = DateTime(2026, 10, 27, 9, 30, 15);

  test('heart rate round-trips, including RR-intervals and contact', () {
    final hr = HeartRateMeasurement.parse(GattEncoder.heartRate(
      bpm: 72,
      skinContact: true,
      energyExpendedKj: 310,
      rrIntervalsMs: [833.0, 812.5],
    ));
    expect(hr.bpm, 72);
    expect(hr.sensorContact, SensorContact.detected);
    expect(hr.energyExpendedKj, 310);
    expect(hr.rrIntervalsMs[0], closeTo(833, 1));
    expect(hr.rrIntervalsMs[1], closeTo(812.5, 1));
  });

  test('heart rate uses the 16-bit format above 255 bpm', () {
    final bytes = GattEncoder.heartRate(bpm: 300);
    expect(bytes.first & 0x01, 1);
    expect(HeartRateMeasurement.parse(bytes).bpm, 300);
    expect(
      HeartRateMeasurement.parse(GattEncoder.heartRate(bpm: 60)).sensorContact,
      SensorContact.notSupported,
    );
  });

  test('blood pressure round-trips in mmHg and kPa', () {
    final mmHg = BloodPressureMeasurement.parse(GattEncoder.bloodPressure(
      systolic: 121,
      diastolic: 79,
      timestamp: time,
      pulseRate: 66,
      userId: 2,
    ));
    expect(mmHg.systolic, 121);
    expect(mmHg.diastolic, 79);
    expect(mmHg.meanArterialPressure, 93);
    expect(mmHg.timestamp, time);
    expect(mmHg.pulseRate, 66);
    expect(mmHg.userId, 2);

    final kPa = BloodPressureMeasurement.parse(
      GattEncoder.bloodPressure(systolic: 16.1, diastolic: 10.5, kPa: true),
    );
    expect(kPa.unit, PressureUnit.kPa);
    expect(kPa.systolic, closeTo(16.1, 1e-9));
  });

  test('temperature round-trips with type and time stamp', () {
    final t = TemperatureMeasurement.parse(
      GattEncoder.temperature(value: 36.85, timestamp: time, type: 3),
    );
    expect(t.value, closeTo(36.85, 1e-9));
    expect(t.unit, TemperatureUnit.celsius);
    expect(t.timestamp, time);
    expect(t.type, TemperatureType.ear);
    expect(
      TemperatureMeasurement.parse(
        GattEncoder.temperature(value: 98.6, fahrenheit: true),
      ).unit,
      TemperatureUnit.fahrenheit,
    );
  });

  test('pulse oximeter round-trips', () {
    final plx = PlxContinuousMeasurement.parse(
      GattEncoder.pulseOximeter(spo2: 97, pulseRate: 64, perfusionIndex: 3.2),
    );
    expect(plx.spo2, 97);
    expect(plx.pulseRate, 64);
    expect(plx.pulseAmplitudeIndex, closeTo(3.2, 1e-9));
  });

  test('weight round-trips with BMI and height', () {
    final w = WeightMeasurement.parse(GattEncoder.weight(
      weight: 72.4,
      timestamp: time,
      userId: 1,
      bmi: 23.6,
      height: 1.752,
    ));
    expect(w.weight, closeTo(72.4, 0.005));
    expect(w.unit, WeightUnit.kilograms);
    expect(w.userId, 1);
    expect(w.bmi, closeTo(23.6, 1e-9));
    expect(w.height, closeTo(1.752, 1e-9));
    expect(
      WeightMeasurement.parse(GattEncoder.weight(weight: 160.2, imperial: true))
          .weight,
      closeTo(160.2, 0.01),
    );
  });

  test('cycling speed and cadence round-trips and wraps', () {
    final csc = CscMeasurement.parse(GattEncoder.cyclingSpeedAndCadence(
      wheelRevolutions: 0x100000000 + 5,
      lastWheelEventTime: 70000,
      crankRevolutions: 0x10000 + 3,
      lastCrankEventTime: 1024,
    ));
    expect(csc.wheelRevolutions, 5);
    expect(csc.lastWheelEventTime, 70000 - 0x10000);
    expect(csc.crankRevolutions, 3);
    expect(csc.lastCrankEventTime, 1024);
  });

  test('cycling power round-trips, including negative power', () {
    final cp = CyclingPowerMeasurement.parse(GattEncoder.cyclingPower(
      watts: 245,
      crankRevolutions: 812,
      lastCrankEventTime: 4096,
    ));
    expect(cp.powerWatts, 245);
    expect(cp.crankRevolutions, 812);
    expect(cp.lastCrankEventTime, 4096);
    expect(
      CyclingPowerMeasurement.parse(GattEncoder.cyclingPower(watts: -12))
          .powerWatts,
      -12,
    );
  });

  test('running speed and cadence round-trips', () {
    final rsc = RscMeasurement.parse(GattEncoder.runningSpeedAndCadence(
      speedMps: 3.5,
      cadence: 172,
      strideLengthM: 1.21,
      totalDistanceM: 5012.3,
      running: true,
    ));
    expect(rsc.speedMps, 3.5);
    expect(rsc.cadence, 172);
    expect(rsc.strideLengthM, closeTo(1.21, 1e-9));
    expect(rsc.totalDistanceM, closeTo(5012.3, 1e-9));
    expect(rsc.isRunning, isTrue);
  });

  test('battery level is clamped and strings are UTF-8', () {
    expect(BatteryLevel.parse(GattEncoder.batteryLevel(140)).percent, 100);
    expect(
      (GattParser.parse(
        GattCharacteristics.manufacturerName,
        GattEncoder.string('Acme Health'),
      ) as GattString)
          .value,
      'Acme Health',
    );
  });

  test('uuid128 expands short UUIDs the way BLE plugins report them', () {
    expect(uuid128(0x2A37), '00002a37-0000-1000-8000-00805f9b34fb');
  });
}
