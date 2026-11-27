import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/core/inverter_sync.dart';

void main() {
  test('parses a successful sync with telemetry', () {
    final r = InverterSyncResult.fromJson({
      'ok': true,
      'providerName': 'SolisCloud',
      'detectedPlantName': 'Roof 9.9 kW',
      'detectedModelName': 'S6-GR1P10K',
      'telemetry': {'todayGenKwh': 31.4, 'livePowerKw': 4.2, 'lifetimeKwh': 12034, 'syncedAtIst': '27/11/2026 09:00', 'statusNote': 'Live'},
    });
    expect(r.ok, isTrue);
    expect(r.error, isNull);
    expect(r.plantName, 'Roof 9.9 kW');
    expect(r.model, 'S6-GR1P10K');
    expect(r.todayGenKwh, 31.4);
    expect(r.lifetimeKwh, 12034);
    expect(r.syncedAtIst, '27/11/2026 09:00');
  });

  test('lists plants when the account needs a choice', () {
    final r = InverterSyncResult.fromJson({
      'ok': false,
      'requiresPlantSelection': true,
      'discoveredPlants': [
        {'stationId': '111', 'plantName': 'Home', 'capacityKwp': 5},
        {'stationId': '', 'plantName': 'skipped'},
      ],
    });
    expect(r.ok, isFalse);
    expect(r.needsPlant, isTrue);
    expect(r.plants.length, 1);
    expect(r.plants.first.stationId, '111');
    expect(r.plants.first.capacityKwp, 5.0);
  });

  test('failure gives the portal message and no data', () {
    final r = InverterSyncResult.fromJson({'ok': false, 'error': 'Wrong password'});
    expect(r.error, 'Wrong password');
    expect(r.todayGenKwh, isNull);
  });

  test('brand list starts with auto-detect and has no duplicates', () {
    expect(kInverterBrands.first.id, 'auto');
    final ids = kInverterBrands.map((b) => b.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('logger address becomes status-page candidates and never keeps a login', () {
    expect(HttpInverterSync.loggerCandidates('192.168.1.50'), [
      'http://192.168.1.50/status.html',
      'http://192.168.1.50/status_a.html',
      'http://192.168.1.50/inverter.json',
    ]);
    expect(HttpInverterSync.loggerCandidates('http://10.10.100.254/status.html'), ['http://10.10.100.254/status.html']);
    expect(HttpInverterSync.loggerCandidates('admin:admin@192.168.1.50'), isNull);
    expect(HttpInverterSync.loggerCandidates('   '), isNull);
  });

  test('connection modes are the three the backend supports', () {
    expect(InverterConnectMode.values.length, 3);
  });
}
