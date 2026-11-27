import 'package:calculator/core/inverter_energy.dart';
import 'package:calculator/core/inverter_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final noon = DateTime(2026, 11, 27, 12);

  test('istDateKey uses India time, not UTC', () {
    // 20:00 UTC on 26 Nov is 01:30 IST on 27 Nov.
    expect(istDateKey(DateTime.utc(2026, 11, 26, 20)), '2026-11-27');
  });

  test('without a reading the figures are the weather estimate', () {
    final e = resolveInverterEnergy(
      snap: null,
      logs: const [],
      capacityKwp: 5,
      electricityRate: 8,
      latitude: 17.4,
      longitude: 78.4,
      now: noon,
    );
    expect(e.isConnected, isFalse);
    expect(e.meterModeLabel, 'Weather estimate');
    expect(e.displayGenKwh, e.potentialKwh);
  });

  test('a connected reading without meter channels uses the appliance fallback', () {
    const snap = InverterSnapshot(
      brand: 'soliscloud',
      source: 'cloud',
      dateKey: '2026-11-27',
      todayGenKwh: 12,
      livePowerKw: 3.4,
    );
    final e = resolveInverterEnergy(
      snap: snap,
      logs: const [],
      capacityKwp: 5,
      electricityRate: 8,
      latitude: 17.4,
      longitude: 78.4,
      now: noon,
    );
    expect(e.isTodayReading, isTrue);
    expect(e.displayGenKwh, 12);
    expect(e.displayUsageKwh, 18.2); // default appliance load
    expect(e.importedKwh, closeTo(6.2, 0.01));
    expect(e.exportedKwh, 0);
    expect(e.selfConsumedKwh, 12);
    expect(e.isSurplus, isFalse);
    expect(e.co2AvoidedKg, closeTo(9.8, 0.01));
  });

  test('smart meter channels set export, import and self-consumption', () {
    const snap = InverterSnapshot(
      brand: 'solarman',
      source: 'cloud',
      dateKey: '2026-11-27',
      todayGenKwh: 12,
      livePowerKw: 2,
      todayUsageKwh: 10,
      todayExportKwh: 4,
      todayImportKwh: 2,
      hasSmartMeter: true,
    );
    final e = resolveInverterEnergy(
      snap: snap,
      logs: const [],
      capacityKwp: 5,
      electricityRate: 8,
      latitude: 17.4,
      longitude: 78.4,
      now: noon,
    );
    expect(e.meterModeLabel, 'Smart meter detected');
    expect(e.exportedKwh, 4);
    expect(e.importedKwh, 2);
    expect(e.selfConsumedKwh, 8);
    expect(e.netBalanceKwh, 2);
    expect(e.isSurplus, isTrue);
    expect(e.exportEarningsInr, 12); // 4 kWh x Rs 3.10 rounded
  });

  test('cumulative figures come from the daily logs', () {
    final logs = [
      const InverterDayLog(dateKey: '2026-11-27', generationKwh: 10, source: 'cloud'),
      const InverterDayLog(dateKey: '2026-11-26', generationKwh: 5.5, source: 'cloud'),
    ];
    final e = resolveInverterEnergy(
      snap: null,
      logs: logs,
      capacityKwp: 5,
      electricityRate: 8,
      latitude: 17.4,
      longitude: 78.4,
      now: noon,
    );
    expect(e.cumulativeLoggedGenKwh, 15.5);
    expect(e.loggedDays, 2);
  });

  test('recordSync keeps one log per day and the latest reading', () async {
    SharedPreferences.setMockInitialValues({});
    await InverterStore.recordSync(
      'solarman',
      'cloud',
      const InverterSyncResult(ok: true, todayGenKwh: 4, dateKey: '2026-11-27'),
    );
    await InverterStore.recordSync(
      'solarman',
      'cloud',
      const InverterSyncResult(ok: true, todayGenKwh: 9, dateKey: '2026-11-27'),
    );
    final logs = await InverterStore.loadLogs();
    expect(logs.length, 1);
    expect(logs.first.generationKwh, 9);
    final snap = await InverterStore.loadSnapshot();
    expect(snap?.todayGenKwh, 9);
  });

  test('a failed sync is not saved', () async {
    SharedPreferences.setMockInitialValues({});
    await InverterStore.recordSync('solarman', 'cloud', InverterSyncResult.failed('no data'));
    expect(await InverterStore.loadSnapshot(), isNull);
    expect(await InverterStore.loadLogs(), isEmpty);
  });
}
