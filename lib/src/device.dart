import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'encoder.dart';
import 'uuids.dart';

/// A simulated Bluetooth LE peripheral.
///
/// It offers services and characteristics like a real device: values you can
/// [read], [notifications] you can listen to, and a connection you can
/// [connect] and [disconnect]. Readings change over simulated time, which
/// moves one second each time you call [tick], or on a timer after [start].
///
/// The same [seed] always produces the same readings, so tests are
/// repeatable.
abstract class SimulatedBleDevice {
  SimulatedBleDevice({
    required this.name,
    String? id,
    this.manufacturer = 'Simulated Devices',
    this.model = 'SIM-1',
    this.firmware = '1.0.0',
    int seed = 1,
    int batteryLevel = 100,
  })  : id = id ?? 'SIM:${name.hashCode.toRadixString(16).toUpperCase()}',
        _random = math.Random(seed),
        _batteryLevel = batteryLevel;

  final String name;
  final String id;
  final String manufacturer;
  final String model;
  final String firmware;
  final math.Random _random;

  /// Seconds of simulated time since the device was created.
  int get elapsedSeconds => _elapsed;
  int _elapsed = 0;

  /// Services and the characteristics each one contains, by 16-bit UUID.
  Map<int, List<int>> get services => {
        GattServices.deviceInformation: const [
          GattCharacteristicIds.manufacturerName,
          GattCharacteristicIds.modelNumber,
          GattCharacteristicIds.firmwareRevision,
        ],
        GattServices.battery: const [GattCharacteristicIds.batteryLevel],
        ...measurementServices,
      };

  /// The device-specific services, such as Heart Rate.
  @protected
  Map<int, List<int>> get measurementServices;

  bool get isConnected => _connected;
  var _connected = false;
  final _connection = StreamController<bool>.broadcast(sync: true);

  /// Emits true on connect and false on disconnect.
  Stream<bool> get connectionState => _connection.stream;

  void connect() {
    if (_connected) return;
    _connected = true;
    _connection.add(true);
  }

  /// Disconnects, like a device going out of range. Notifications stop until
  /// you [connect] again.
  void disconnect() {
    if (!_connected) return;
    _connected = false;
    _connection.add(false);
  }

  int get batteryLevel => _batteryLevel;
  int _batteryLevel;

  /// Changes the battery level and notifies listeners of Battery Level
  /// (0x2A19), for testing low-battery handling.
  set batteryLevel(int percent) {
    _batteryLevel = percent.clamp(0, 100);
    _emit(
      GattCharacteristicIds.batteryLevel,
      GattEncoder.batteryLevel(_batteryLevel),
    );
  }

  /// Reads a characteristic's current value.
  ///
  /// Throws a [StateError] if the device isn't connected, and an
  /// [ArgumentError] if it has no readable characteristic with that UUID.
  List<int> read(int characteristic) {
    if (!_connected) throw StateError('$name is not connected');
    return switch (characteristic) {
      GattCharacteristicIds.manufacturerName =>
        GattEncoder.string(manufacturer),
      GattCharacteristicIds.modelNumber => GattEncoder.string(model),
      GattCharacteristicIds.firmwareRevision => GattEncoder.string(firmware),
      GattCharacteristicIds.batteryLevel =>
        GattEncoder.batteryLevel(_batteryLevel),
      _ => readMeasurement(characteristic) ??
          (throw ArgumentError.value(
            characteristic,
            'characteristic',
            '$name has no readable characteristic with this UUID',
          )),
    };
  }

  /// Device-specific readable values, or null if [characteristic] isn't one.
  @protected
  List<int>? readMeasurement(int characteristic) => null;

  final _streams = <int, StreamController<List<int>>>{};

  /// Values the device sends for [characteristic], while connected.
  Stream<List<int>> notifications(int characteristic) => _streams
      .putIfAbsent(
        characteristic,
        () => StreamController<List<int>>.broadcast(sync: true),
      )
      .stream;

  void _emit(int characteristic, List<int> value) {
    if (!_connected) return;
    _streams[characteristic]?.add(List.unmodifiable(value));
  }

  /// Sends a value on [characteristic] if the device is connected. For
  /// measurements a device sends on demand, like a blood pressure reading.
  @protected
  void notify(int characteristic, List<int> value) =>
      _emit(characteristic, value);

  /// Moves simulated time forward by one second and sends that second's
  /// notifications.
  void tick() {
    _elapsed++;
    onTick(_elapsed).forEach(_emit);
  }

  /// The notifications to send at [second], by characteristic.
  @protected
  Map<int, List<int>> onTick(int second);

  Timer? _timer;

  /// Calls [tick] every [interval] until [stop]. A shorter interval runs
  /// simulated time faster than real time.
  void start({Duration interval = const Duration(seconds: 1)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stops the timer and closes every stream.
  Future<void> dispose() async {
    stop();
    await Future.wait([
      _connection.close(),
      for (final controller in _streams.values) controller.close(),
    ]);
  }

  /// A value that drifts smoothly between [min] and [max] over [period]
  /// seconds, with a little noise, like a real reading.
  @protected
  double drift(double min, double max, {double period = 60, double phase = 0}) {
    final position =
        (math.sin((_elapsed + phase) * 2 * math.pi / period) + 1) / 2;
    final noise = (_random.nextDouble() - 0.5) * 0.06;
    return min + (max - min) * (position + noise).clamp(0.0, 1.0);
  }
}
