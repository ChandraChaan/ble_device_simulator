import 'device.dart';
import 'encoder.dart';
import 'uuids.dart';

/// A chest strap or watch that streams heart rate and RR-intervals once a
/// second.
class SimulatedHeartRateMonitor extends SimulatedBleDevice {
  SimulatedHeartRateMonitor({
    super.name = 'Simulated HR Strap',
    super.id,
    super.seed,
    super.batteryLevel,
    this.minBpm = 62,
    this.maxBpm = 158,
  });

  /// The range the heart rate drifts within. Use 55–75 for resting, or
  /// widen it for a workout.
  int minBpm;
  int maxBpm;

  /// Whether the strap touches the skin. Set to false to test the "check
  /// your strap" state; the strap keeps sending 0 bpm like real ones do.
  bool skinContact = true;

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.heartRate: [
          GattCharacteristicIds.heartRateMeasurement,
          GattCharacteristicIds.bodySensorLocation,
        ],
      };

  @override
  List<int>? readMeasurement(int characteristic) =>
      characteristic == GattCharacteristicIds.bodySensorLocation
          ? const [1] // Chest.
          : null;

  @override
  Map<int, List<int>> onTick(int second) {
    if (!skinContact) {
      return {
        GattCharacteristicIds.heartRateMeasurement:
            GattEncoder.heartRate(bpm: 0, skinContact: false),
      };
    }
    final bpm = drift(minBpm.toDouble(), maxBpm.toDouble()).round();
    return {
      GattCharacteristicIds.heartRateMeasurement: GattEncoder.heartRate(
        bpm: bpm,
        skinContact: true,
        rrIntervalsMs: [60000 / bpm],
      ),
    };
  }
}

/// A blood pressure cuff. Like a real one, it only sends a reading when a
/// measurement finishes: call [measure].
class SimulatedBloodPressureMonitor extends SimulatedBleDevice {
  SimulatedBloodPressureMonitor({
    super.name = 'Simulated BP Cuff',
    super.id,
    super.seed,
    super.batteryLevel,
    this.systolicRange = (110, 132),
    this.diastolicRange = (70, 86),
  });

  (num, num) systolicRange;
  (num, num) diastolicRange;

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.bloodPressure: [
          GattCharacteristicIds.bloodPressureMeasurement,
        ],
      };

  @override
  Map<int, List<int>> onTick(int second) => const {};

  /// Takes a reading and sends it, time-stamped with [at] (now by default).
  void measure({DateTime? at}) {
    final systolic = drift(
      systolicRange.$1.toDouble(),
      systolicRange.$2.toDouble(),
    ).roundToDouble();
    final diastolic = drift(
      diastolicRange.$1.toDouble(),
      diastolicRange.$2.toDouble(),
      phase: 13,
    ).roundToDouble();
    notify(
      GattCharacteristicIds.bloodPressureMeasurement,
      GattEncoder.bloodPressure(
        systolic: systolic,
        diastolic: diastolic,
        meanArterialPressure:
            (diastolic + (systolic - diastolic) / 3).roundToDouble(),
        timestamp: at ?? DateTime.now(),
        pulseRate: drift(62, 84, phase: 7).roundToDouble(),
      ),
    );
  }
}

/// A thermometer that sends a body temperature every second.
class SimulatedThermometer extends SimulatedBleDevice {
  SimulatedThermometer({
    super.name = 'Simulated Thermometer',
    super.id,
    super.seed,
    super.batteryLevel,
  });

  /// Set to true to simulate a fever of about 38.5–39.5 °C.
  bool fever = false;

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.healthThermometer: [
          GattCharacteristicIds.temperatureMeasurement,
        ],
      };

  @override
  Map<int, List<int>> onTick(int second) {
    final celsius = fever ? drift(38.5, 39.5) : drift(36.4, 37.2);
    return {
      GattCharacteristicIds.temperatureMeasurement: GattEncoder.temperature(
        value: (celsius * 10).round() / 10,
        type: 3, // Ear.
      ),
    };
  }
}

/// A fingertip pulse oximeter that streams SpO2 and pulse.
class SimulatedPulseOximeter extends SimulatedBleDevice {
  SimulatedPulseOximeter({
    super.name = 'Simulated Oximeter',
    super.id,
    super.seed,
    super.batteryLevel,
  });

  /// Set to true to simulate low oxygen saturation (86–91%).
  bool lowOxygen = false;

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.pulseOximeter: [
          GattCharacteristicIds.plxContinuousMeasurement,
        ],
      };

  @override
  Map<int, List<int>> onTick(int second) {
    final spo2 = lowOxygen ? drift(86, 91) : drift(95, 99.4);
    return {
      GattCharacteristicIds.plxContinuousMeasurement: GattEncoder.pulseOximeter(
        spo2: spo2.roundToDouble(),
        pulseRate: drift(60, 90, phase: 9).roundToDouble(),
        perfusionIndex: (drift(1.5, 4.5, phase: 21) * 10).round() / 10,
      ),
    };
  }
}

/// A cycling power meter that sends power and crank revolutions, from which
/// apps calculate cadence.
class SimulatedPowerMeter extends SimulatedBleDevice {
  SimulatedPowerMeter({
    super.name = 'Simulated Power Meter',
    super.id,
    super.seed,
    super.batteryLevel,
    this.minWatts = 160,
    this.maxWatts = 320,
    this.minRpm = 78,
    this.maxRpm = 96,
  });

  int minWatts;
  int maxWatts;
  int minRpm;
  int maxRpm;
  double _revolutions = 0;

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.cyclingPower: [
          GattCharacteristicIds.cyclingPowerMeasurement,
        ],
      };

  @override
  Map<int, List<int>> onTick(int second) {
    final rpm = drift(minRpm.toDouble(), maxRpm.toDouble(), period: 40);
    _revolutions += rpm / 60;
    // When the last full revolution happened, in 1/1024ths of a second.
    final sinceLastRevolution = (_revolutions % 1) / (rpm / 60);
    return {
      GattCharacteristicIds.cyclingPowerMeasurement: GattEncoder.cyclingPower(
        watts: drift(minWatts.toDouble(), maxWatts.toDouble()).round(),
        crankRevolutions: _revolutions.floor(),
        lastCrankEventTime: ((second - sinceLastRevolution) * 1024).round(),
      ),
    };
  }
}

/// A running foot pod that sends speed, cadence and total distance.
class SimulatedRunningPod extends SimulatedBleDevice {
  SimulatedRunningPod({
    super.name = 'Simulated Foot Pod',
    super.id,
    super.seed,
    super.batteryLevel,
    this.minSpeedMps = 2.6,
    this.maxSpeedMps = 3.8,
  });

  double minSpeedMps;
  double maxSpeedMps;
  double _distance = 0;

  /// Metres run so far.
  double get distanceM => _distance;

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.runningSpeedAndCadence: [
          GattCharacteristicIds.rscMeasurement,
        ],
      };

  @override
  Map<int, List<int>> onTick(int second) {
    final speed = drift(minSpeedMps, maxSpeedMps, period: 45);
    _distance += speed;
    return {
      GattCharacteristicIds.rscMeasurement: GattEncoder.runningSpeedAndCadence(
        speedMps: speed,
        cadence: drift(158, 184, phase: 11).round(),
        totalDistanceM: _distance,
        running: true,
      ),
    };
  }
}

/// A smart scale. Call [weigh] to step on it.
class SimulatedWeightScale extends SimulatedBleDevice {
  SimulatedWeightScale({
    super.name = 'Simulated Scale',
    super.id,
    super.seed,
    super.batteryLevel,
  });

  @override
  Map<int, List<int>> get measurementServices => const {
        GattServices.weightScale: [GattCharacteristicIds.weightMeasurement],
      };

  @override
  Map<int, List<int>> onTick(int second) => const {};

  /// Sends a measurement of [kilograms]. Pass [heightM] to include BMI.
  void weigh(double kilograms, {double? heightM, int? userId, DateTime? at}) {
    notify(
      GattCharacteristicIds.weightMeasurement,
      GattEncoder.weight(
        weight: kilograms,
        timestamp: at ?? DateTime.now(),
        userId: userId,
        bmi: heightM == null ? null : kilograms / (heightM * heightM),
        height: heightM,
      ),
    );
  }
}
