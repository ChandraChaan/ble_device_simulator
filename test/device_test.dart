import 'package:ble_device_simulator/ble_device_simulator.dart';
import 'package:ble_gatt_parser/ble_gatt_parser.dart';
import 'package:test/test.dart';

List<GattValue> _collect(SimulatedBleDevice device, int uuid, int ticks) {
  final values = <GattValue>[];
  final sub = device.notifications(uuid).listen(
        (bytes) => values.add(GattParser.parse(uuid, bytes)),
      );
  for (var i = 0; i < ticks; i++) {
    device.tick();
  }
  sub.cancel();
  return values;
}

void main() {
  group('SimulatedBleDevice', () {
    test('only notifies while connected', () {
      final strap = SimulatedHeartRateMonitor();
      const hr = GattCharacteristicIds.heartRateMeasurement;
      expect(_collect(strap, hr, 3), isEmpty);
      strap.connect();
      expect(_collect(strap, hr, 3), hasLength(3));
      strap.disconnect();
      expect(_collect(strap, hr, 3), isEmpty);
    });

    test('reports connection changes', () {
      final strap = SimulatedHeartRateMonitor();
      final states = <bool>[];
      strap.connectionState.listen(states.add);
      strap
        ..connect()
        ..connect()
        ..disconnect();
      expect(states, [true, false]);
    });

    test('reads device information and battery', () {
      final strap = SimulatedHeartRateMonitor(batteryLevel: 64)..connect();
      final manufacturer = GattParser.parse(
        GattCharacteristics.manufacturerName,
        strap.read(GattCharacteristicIds.manufacturerName),
      ) as GattString;
      expect(manufacturer.value, 'Simulated Devices');
      expect(
        BatteryLevel.parse(strap.read(GattCharacteristicIds.batteryLevel))
            .percent,
        64,
      );
      expect(
        BodySensorLocation.parse(
          strap.read(GattCharacteristicIds.bodySensorLocation),
        ).location,
        SensorLocation.chest,
      );
    });

    test('rejects reads when disconnected or unknown', () {
      final strap = SimulatedHeartRateMonitor();
      expect(
        () => strap.read(GattCharacteristicIds.batteryLevel),
        throwsStateError,
      );
      strap.connect();
      expect(() => strap.read(0x2A99), throwsArgumentError);
    });

    test('notifies battery changes', () {
      final strap = SimulatedHeartRateMonitor()..connect();
      final levels = <int>[];
      strap
          .notifications(GattCharacteristicIds.batteryLevel)
          .listen((bytes) => levels.add(BatteryLevel.parse(bytes).percent));
      strap.batteryLevel = 15;
      expect(levels, [15]);
      expect(strap.batteryLevel, 15);
    });

    test('lists its services', () {
      final services = SimulatedHeartRateMonitor().services;
      expect(services.keys, contains(GattServices.heartRate));
      expect(services.keys, contains(GattServices.battery));
      expect(services.keys, contains(GattServices.deviceInformation));
    });

    test('the same seed gives the same readings', () {
      List<int> bpms(int seed) => _collect(
            SimulatedHeartRateMonitor(seed: seed)..connect(),
            GattCharacteristicIds.heartRateMeasurement,
            10,
          ).map((v) => (v as HeartRateMeasurement).bpm).toList();
      expect(bpms(7), bpms(7));
    });

    test('start runs on a timer until stop', () async {
      final strap = SimulatedHeartRateMonitor()..connect();
      var count = 0;
      strap
          .notifications(GattCharacteristicIds.heartRateMeasurement)
          .listen((_) => count++);
      strap.start(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      strap.stop();
      final stopped = count;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(stopped, greaterThan(2));
      expect(count, stopped);
      await strap.dispose();
    });
  });

  test('heart rate stays in range and reports lost contact', () {
    final strap = SimulatedHeartRateMonitor(minBpm: 60, maxBpm: 80)..connect();
    final readings = _collect(
      strap,
      GattCharacteristicIds.heartRateMeasurement,
      120,
    ).cast<HeartRateMeasurement>();
    for (final hr in readings) {
      expect(hr.bpm, inInclusiveRange(60, 80));
      expect(hr.rrIntervalsMs.single, closeTo(60000 / hr.bpm, 1));
    }
    strap.skinContact = false;
    final lost = _collect(strap, GattCharacteristicIds.heartRateMeasurement, 1)
        .single as HeartRateMeasurement;
    expect(lost.sensorContact, SensorContact.notDetected);
  });

  test('blood pressure cuff sends a reading only when measuring', () {
    final cuff = SimulatedBloodPressureMonitor()..connect();
    final readings = <BloodPressureMeasurement>[];
    cuff
        .notifications(GattCharacteristicIds.bloodPressureMeasurement)
        .listen((b) => readings.add(BloodPressureMeasurement.parse(b)));
    cuff.tick();
    expect(readings, isEmpty);
    final at = DateTime(2026, 10, 27, 8);
    cuff.measure(at: at);
    expect(readings, hasLength(1));
    expect(readings.single.systolic, inInclusiveRange(110, 132));
    expect(readings.single.diastolic, inInclusiveRange(70, 86));
    expect(readings.single.timestamp, at);
    expect(readings.single.pulseRate, isNotNull);
  });

  test('thermometer simulates a fever', () {
    final thermometer = SimulatedThermometer()..connect();
    const uuid = GattCharacteristicIds.temperatureMeasurement;
    final normal =
        _collect(thermometer, uuid, 30).cast<TemperatureMeasurement>();
    expect(normal.every((t) => t.celsius >= 36.4 && t.celsius <= 37.2), isTrue);
    thermometer.fever = true;
    final fever =
        _collect(thermometer, uuid, 30).cast<TemperatureMeasurement>();
    expect(fever.every((t) => t.celsius >= 38.5 && t.celsius <= 39.5), isTrue);
  });

  test('pulse oximeter simulates low oxygen', () {
    final oximeter = SimulatedPulseOximeter()..connect();
    const uuid = GattCharacteristicIds.plxContinuousMeasurement;
    oximeter.lowOxygen = true;
    final readings =
        _collect(oximeter, uuid, 30).cast<PlxContinuousMeasurement>();
    expect(readings.every((r) => r.spo2 >= 86 && r.spo2 <= 91), isTrue);
  });

  test('power meter crank data gives a realistic cadence', () {
    final meter = SimulatedPowerMeter(minRpm: 80, maxRpm: 90)..connect();
    final readings = _collect(
      meter,
      GattCharacteristicIds.cyclingPowerMeasurement,
      60,
    ).cast<CyclingPowerMeasurement>();
    for (var i = 1; i < readings.length; i++) {
      final cadence = readings[i].cadenceSince(readings[i - 1]);
      if (cadence != null) expect(cadence, inInclusiveRange(70, 100));
      expect(readings[i].powerWatts, inInclusiveRange(160, 320));
    }
  });

  test('running pod accumulates distance', () {
    final pod = SimulatedRunningPod()..connect();
    final readings = _collect(pod, GattCharacteristicIds.rscMeasurement, 20)
        .cast<RscMeasurement>();
    expect(readings.last.totalDistanceM, closeTo(pod.distanceM, 0.1));
    expect(readings.last.totalDistanceM,
        greaterThan(readings.first.totalDistanceM!));
    expect(readings.every((r) => r.isRunning), isTrue);
  });

  test('scale sends a weight with BMI', () {
    final scale = SimulatedWeightScale()..connect();
    final readings = <WeightMeasurement>[];
    scale
        .notifications(GattCharacteristicIds.weightMeasurement)
        .listen((b) => readings.add(WeightMeasurement.parse(b)));
    scale.weigh(70, heightM: 1.75);
    expect(readings.single.weight, closeTo(70, 0.005));
    expect(readings.single.bmi, closeTo(22.9, 0.05));
  });
}
