# ble_device_simulator

[![pub package](https://img.shields.io/pub/v/ble_device_simulator.svg)](https://pub.dev/packages/ble_device_simulator)
[![CI](https://github.com/ChandraChaan/ble_device_simulator/actions/workflows/ci.yml/badge.svg)](https://github.com/ChandraChaan/ble_device_simulator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Build and test Bluetooth LE health and fitness apps without hardware.**

Simulated heart-rate straps, blood pressure cuffs, thermometers, pulse oximeters, power meters, foot pods and scales that send the exact bytes real devices send, following the Bluetooth SIG specs.

- **Write tests for BLE code**: in CI, on every developer's laptop, with no device in a drawer somewhere
- **Reproduce edge cases on demand**: a slipped strap, a fever, low oxygen, a flat battery, a dropped connection
- **Deterministic**: the same seed always gives the same readings, and simulated time only moves when you say so
- **Real bytes**: every notification is checked in this package's tests by parsing it with [ble_gatt_parser](https://pub.dev/packages/ble_gatt_parser)
- **Pure Dart**: works in Flutter widget tests, plain Dart tests and on the web

```dart
final strap = SimulatedHeartRateMonitor()..connect();

strap.notifications(GattCharacteristicIds.heartRateMeasurement).listen((bytes) {
  print(GattParser.parse('2a37', bytes)); // HeartRateMeasurement(bpm: 74, ...)
});

strap.tick();               // one second of simulated time
strap.skinContact = false;  // the strap slips off
strap.batteryLevel = 5;     // battery warning
strap.disconnect();         // out of range
```

## Install

```bash
dart pub add dev:ble_device_simulator
```

Add it as a regular dependency instead if you also want simulated devices in a demo or debug build.

## Devices

| Class | Service | Sends | Edge cases |
|---|---|---|---|
| `SimulatedHeartRateMonitor` | Heart Rate (0x180D) | bpm and RR-intervals every second | `skinContact = false`, custom bpm range |
| `SimulatedBloodPressureMonitor` | Blood Pressure (0x1810) | A reading when you call `measure()` | Custom systolic and diastolic ranges |
| `SimulatedThermometer` | Health Thermometer (0x1809) | Ear temperature every second | `fever = true` |
| `SimulatedPulseOximeter` | Pulse Oximeter (0x1822) | SpO2, pulse and perfusion index | `lowOxygen = true` |
| `SimulatedPowerMeter` | Cycling Power (0x1818) | Watts and crank revolutions, for cadence | Custom power and rpm ranges |
| `SimulatedRunningPod` | Running Speed and Cadence (0x1814) | Speed, cadence and distance | Custom speed range |
| `SimulatedWeightScale` | Weight Scale (0x181D) | A measurement when you call `weigh()` | Optional BMI and height |

Every device also has Device Information (manufacturer, model, firmware) and Battery (0x180F), with `read()`, `connect()`, `disconnect()`, `connectionState`, `batteryLevel` and `services`.

## Testing a Flutter app

Put a small interface between your app and your BLE plugin, and use the simulator in tests:

```dart
abstract class HeartRateSource {
  Stream<List<int>> get measurements;
}

/// In the app: flutter_blue_plus, flutter_reactive_ble or your own plugin.
class BluetoothHeartRateSource implements HeartRateSource {
  BluetoothHeartRateSource(this.characteristic);
  final BluetoothCharacteristic characteristic;

  @override
  Stream<List<int>> get measurements => characteristic.onValueReceived;
}

/// In tests and demos.
class SimulatedHeartRateSource implements HeartRateSource {
  SimulatedHeartRateSource(this.device);
  final SimulatedHeartRateMonitor device;

  @override
  Stream<List<int>> get measurements =>
      device.notifications(GattCharacteristicIds.heartRateMeasurement);
}
```

```dart
testWidgets('shows a warning when the strap slips', (tester) async {
  final strap = SimulatedHeartRateMonitor()..connect();
  await tester.pumpWidget(HeartRateScreen(source: SimulatedHeartRateSource(strap)));

  strap.tick();
  await tester.pump();
  expect(find.textContaining('bpm'), findsOneWidget);

  strap.skinContact = false;
  strap.tick();
  await tester.pump();
  expect(find.text('Check your strap'), findsOneWidget);
});
```

## Time

Simulated time only moves when you call `tick()`, which advances one second and sends that second's notifications synchronously. That keeps tests fast and predictable. For demos, `start(interval: ...)` ticks on a timer: a shorter interval runs simulated time faster. Call `stop()` or `dispose()` when you're done.

## Encoders

The devices are built on `GattEncoder`, which you can also use directly to build any measurement by hand:

```dart
final bytes = GattEncoder.bloodPressure(
  systolic: 142,
  diastolic: 91,
  pulseRate: 88,
  timestamp: DateTime(2026, 1, 1, 8),
);
```

It covers heart rate, blood pressure, temperature, pulse oximetry, weight, cycling speed and cadence, cycling power, running speed and cadence, battery level and strings, plus the IEEE 11073 SFLOAT and FLOAT number formats.

## About the author

Built by [Chandra ObulaReddy](https://chandrachaan.com), a Flutter architect who has shipped Bluetooth LE and wearable integrations for safety, healthcare and fitness products. See also [ble_gatt_parser](https://pub.dev/packages/ble_gatt_parser), which parses the bytes these devices send.
