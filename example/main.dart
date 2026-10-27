import 'package:ble_device_simulator/ble_device_simulator.dart';

/// Connects to a simulated heart-rate strap and prints its notifications.
void main() {
  final strap = SimulatedHeartRateMonitor(minBpm: 60, maxBpm: 90)..connect();

  strap
      .notifications(GattCharacteristicIds.heartRateMeasurement)
      .listen((bytes) {
    // These are the same bytes a real strap sends. Pass them to your parser,
    // for example GattParser.parse from package:ble_gatt_parser.
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    print('t=${strap.elapsedSeconds}s  0x2A37  $hex');
  });

  // Advance simulated time by five seconds, synchronously.
  for (var i = 0; i < 5; i++) {
    strap.tick();
  }

  strap.skinContact = false;
  strap.tick();
  print('Strap slipped: the flags byte now reports no skin contact.');

  strap.disconnect();
}
