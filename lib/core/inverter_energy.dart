import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inverter_sync.dart';
import 'sun.dart';

/// India date (yyyy-mm-dd), so readings match the server's IST day.
String istDateKey([DateTime? now]) {
  final u = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

double _r1(double v) => (v * 10).roundToDouble() / 10;
double _r2(double v) => (v * 100).roundToDouble() / 100;
double _clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));

/// The latest successful reading on this phone.
class InverterSnapshot {
  final String brand;
  final String source;
  final String dateKey;
  final double todayGenKwh;
  final double livePowerKw;
  final double? todayUsageKwh;
  final double? todayExportKwh;
  final double? todayImportKwh;
  final bool hasSmartMeter;
  final double? lifetimeKwh;
  final String? plantName;
  final String? model;
  final String? syncedAtIst;

  const InverterSnapshot({
    required this.brand,
    required this.source,
    required this.dateKey,
    required this.todayGenKwh,
    required this.livePowerKw,
    this.todayUsageKwh,
    this.todayExportKwh,
    this.todayImportKwh,
    this.hasSmartMeter = false,
    this.lifetimeKwh,
    this.plantName,
    this.model,
    this.syncedAtIst,
  });

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'source': source,
        'dateKey': dateKey,
        'todayGenKwh': todayGenKwh,
        'livePowerKw': livePowerKw,
        'todayUsageKwh': todayUsageKwh,
        'todayExportKwh': todayExportKwh,
        'todayImportKwh': todayImportKwh,
        'hasSmartMeter': hasSmartMeter,
        'lifetimeKwh': lifetimeKwh,
        'plantName': plantName,
        'model': model,
        'syncedAtIst': syncedAtIst,
      };

  static double? _n(Object? v) => v is num ? v.toDouble() : null;

  factory InverterSnapshot.fromJson(Map<String, dynamic> j) => InverterSnapshot(
        brand: (j['brand'] ?? '').toString(),
        source: (j['source'] ?? 'cloud').toString(),
        dateKey: (j['dateKey'] ?? '').toString(),
        todayGenKwh: _n(j['todayGenKwh']) ?? 0.0,
        livePowerKw: _n(j['livePowerKw']) ?? 0.0,
        todayUsageKwh: _n(j['todayUsageKwh']),
        todayExportKwh: _n(j['todayExportKwh']),
        todayImportKwh: _n(j['todayImportKwh']),
        hasSmartMeter: j['hasSmartMeter'] == true,
        lifetimeKwh: _n(j['lifetimeKwh']),
        plantName: j['plantName']?.toString(),
        model: j['model']?.toString(),
        syncedAtIst: j['syncedAtIst']?.toString(),
      );

  /// Builds a snapshot from a successful sync. Null when the result has no generation figure.
  static InverterSnapshot? fromResult(String brand, String source, InverterSyncResult r) {
    final gen = r.todayGenKwh;
    if (!r.ok || gen == null) return null;
    return InverterSnapshot(
      brand: brand,
      source: source,
      dateKey: r.dateKey ?? istDateKey(),
      todayGenKwh: gen,
      livePowerKw: r.livePowerKw ?? 0.0,
      todayUsageKwh: r.todayUsageKwh,
      todayExportKwh: r.todayExportKwh,
      todayImportKwh: r.todayImportKwh,
      hasSmartMeter: r.hasSmartMeter,
      lifetimeKwh: r.lifetimeKwh,
      plantName: r.plantName,
      model: r.model,
      syncedAtIst: r.syncedAtIst,
    );
  }
}

/// One day's readings, kept for the history list.
class InverterDayLog {
  final String dateKey;
  final double generationKwh;
  final double? usageKwh;
  final double? exportKwh;
  final double? importKwh;
  final String source;

  const InverterDayLog({
    required this.dateKey,
    required this.generationKwh,
    this.usageKwh,
    this.exportKwh,
    this.importKwh,
    required this.source,
  });

  factory InverterDayLog.fromSnapshot(InverterSnapshot s) => InverterDayLog(
        dateKey: s.dateKey,
        generationKwh: s.todayGenKwh,
        usageKwh: s.todayUsageKwh,
        exportKwh: s.todayExportKwh,
        importKwh: s.todayImportKwh,
        source: s.source,
      );

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'generationKwh': generationKwh,
        'usageKwh': usageKwh,
        'exportKwh': exportKwh,
        'importKwh': importKwh,
        'source': source,
      };

  factory InverterDayLog.fromJson(Map<String, dynamic> j) => InverterDayLog(
        dateKey: (j['dateKey'] ?? '').toString(),
        generationKwh: (j['generationKwh'] is num) ? (j['generationKwh'] as num).toDouble() : 0.0,
        usageKwh: j['usageKwh'] is num ? (j['usageKwh'] as num).toDouble() : null,
        exportKwh: j['exportKwh'] is num ? (j['exportKwh'] as num).toDouble() : null,
        importKwh: j['importKwh'] is num ? (j['importKwh'] as num).toDouble() : null,
        source: (j['source'] ?? '').toString(),
      );
}

/// Keeps the latest reading and one log per day on this phone. Nothing is sent anywhere.
class InverterStore {
  static const _snapKey = 'inverter_snapshot';
  static const _logKey = 'inverter_daily_logs';
  static const _maxLogs = 400;

  /// Bumped after every save, so screens can redraw.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static Future<InverterSnapshot?> loadSnapshot() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_snapKey);
      if (raw == null) return null;
      return InverterSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Newest first.
  static Future<List<InverterDayLog>> loadLogs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_logKey);
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List)
          .map((e) => InverterDayLog.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort((a, b) => b.dateKey.compareTo(a.dateKey));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Saves a successful sync: the latest reading, and today's log (replaces today's earlier entry).
  static Future<void> recordSync(String brand, String source, InverterSyncResult r) async {
    final snap = InverterSnapshot.fromResult(brand, source, r);
    if (snap == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_snapKey, jsonEncode(snap.toJson()));
      final logs = (await loadLogs()).where((l) => l.dateKey != snap.dateKey).toList();
      logs.insert(0, InverterDayLog.fromSnapshot(snap));
      final trimmed = logs.take(_maxLogs).toList();
      await p.setString(_logKey, jsonEncode(trimmed.map((l) => l.toJson()).toList()));
      version.value++;
    } catch (_) {
      // Storage can fail on a locked device; the on-screen result still shows.
    }
  }
}

/// Today's energy picture, the same figures the web app shows.
class InverterEnergy {
  final bool isConnected;
  final bool isTodayReading;
  final String meterModeLabel;
  final double potentialKwh; // weather-based estimate for the day
  final double displayGenKwh; // real reading when connected, else estimate
  final double displayLiveKw;
  final double? performanceRatioPct;
  final double displayUsageKwh;
  final double displayLiveUsageKw;
  final double selfConsumedKwh;
  final double exportedKwh;
  final double importedKwh;
  final double netBalanceKwh;
  final bool isSurplus;
  final int solarCoveragePercent;
  final double exportTariffInr;
  final int selfSavingsInr;
  final int exportEarningsInr;
  final int totalSavingsInr;
  final double co2AvoidedKg;
  final double cumulativeLoggedGenKwh;
  final int loggedDays;

  const InverterEnergy({
    required this.isConnected,
    required this.isTodayReading,
    required this.meterModeLabel,
    required this.potentialKwh,
    required this.displayGenKwh,
    required this.displayLiveKw,
    required this.performanceRatioPct,
    required this.displayUsageKwh,
    required this.displayLiveUsageKw,
    required this.selfConsumedKwh,
    required this.exportedKwh,
    required this.importedKwh,
    required this.netBalanceKwh,
    required this.isSurplus,
    required this.solarCoveragePercent,
    required this.exportTariffInr,
    required this.selfSavingsInr,
    required this.exportEarningsInr,
    required this.totalSavingsInr,
    required this.co2AvoidedKg,
    required this.cumulativeLoggedGenKwh,
    required this.loggedDays,
  });
}

/// Port of the web app's resolveInverterTelemetry. Weather inputs fall back to the same defaults.
InverterEnergy resolveInverterEnergy({
  required InverterSnapshot? snap,
  required List<InverterDayLog> logs,
  required double capacityKwp,
  required double electricityRate,
  double exportTariffInr = 3.1,
  required double latitude,
  required double longitude,
  double? ghiWm2,
  double? cloudPercent,
  double? tempC,
  double? psh,
  double? applianceDailyKwh,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final cap = capacityKwp > 0 ? capacityKwp : 5.0;
  final ghi = ghiWm2 ?? 850.0;
  final cloud = cloudPercent ?? 15.0;

  // 1. Weather-based potential for the day.
  final sunAlt = solarPosition(t, latitude, longitude).alt;
  final isSunUp = sunAlt > 0;
  final cellTemp = (tempC ?? 28.0) + (ghi / 800) * 25;
  final tempDerate = _clamp(1 - math.max(0.0, cellTemp - 25) * 0.0038, 0.85, 1.02);
  final cloudRatio = math.max(0.4, 1 - (cloud / 100) * 0.7);
  final effectivePsh = _clamp((psh ?? 5.5) * cloudRatio, 2.5, 7.5);
  final potential = math.max(1.0, _r1(cap * effectivePsh * tempDerate * 0.96));
  final sinAlt = isSunUp ? math.sin(sunAlt * math.pi / 180) : 0.0;
  final weatherLiveKw = isSunUp
      ? _r2(math.max(0.1, math.min(cap * 0.98, cap * (ghi / 1000) * sinAlt * tempDerate * cloudRatio)))
      : 0.0;

  // 2. The real reading, when connected.
  final s = snap;
  final connected = s != null;
  final isToday = s != null && s.dateKey == istDateKey(t);
  final actual = s != null ? _r1(s.todayGenKwh) : null;
  final displayGen = actual ?? potential;
  final displayLive = s != null ? _r2(s.livePowerKw) : weatherLiveKw;
  final pr = (actual != null && potential > 0) ? _r1(math.min(200.0, actual / potential * 100)) : null;

  // 3. Meter channels, when the inverter reports them.
  final hasChannels = s != null &&
      (s.hasSmartMeter || s.todayUsageKwh != null || s.todayExportKwh != null || s.todayImportKwh != null);
  double? meteredUsage;
  if (s != null && hasChannels && s.todayUsageKwh != null) {
    meteredUsage = _r1(s.todayUsageKwh!);
  } else if (s != null && hasChannels && actual != null && s.todayExportKwh != null && s.todayImportKwh != null) {
    meteredUsage = _r1(math.max(0.1, actual - s.todayExportKwh! + s.todayImportKwh!));
  }
  final fallbackUsage = math.max(1.0, _r1(applianceDailyKwh ?? 18.2));
  final displayUsage = meteredUsage ?? fallbackUsage;

  final hour = t.hour;
  final loadMult = (hour >= 18 && hour <= 22)
      ? 1.45
      : (hour >= 7 && hour <= 10)
          ? 1.25
          : (hour >= 11 && hour <= 16)
              ? 1.1
              : 0.65;
  final displayLiveUsage = _r2(displayUsage / 24 * loadMult);

  // 4. Export, import and the balance for the day.
  final meteredExport = (s != null && hasChannels) ? s.todayExportKwh : null;
  final meteredImport = (s != null && hasChannels) ? s.todayImportKwh : null;

  final double selfConsumed;
  final double exported;
  final double imported;
  final double net;
  if (meteredExport != null || meteredImport != null) {
    exported = meteredExport != null ? _r1(meteredExport) : math.max(0.0, _r1(displayGen - displayUsage));
    imported = meteredImport != null ? _r1(meteredImport) : math.max(0.0, _r1(displayUsage - displayGen));
    selfConsumed = _r1(math.max(0.0, displayGen - exported));
    net = _r1(exported - imported);
  } else {
    selfConsumed = _r1(math.min(displayGen, displayUsage));
    exported = _r1(math.max(0.0, displayGen - displayUsage));
    imported = _r1(math.max(0.0, displayUsage - displayGen));
    net = _r1(displayGen - displayUsage);
  }
  final coverage = displayUsage > 0 ? math.min(300, (displayGen / displayUsage * 100).round()) : 0;

  // 5. Money and carbon.
  final selfSavings = (selfConsumed * electricityRate).round();
  final exportEarnings = (exported * exportTariffInr).round();

  final cumulative = logs.fold<double>(0.0, (a, l) => a + l.generationKwh);

  return InverterEnergy(
    isConnected: connected,
    isTodayReading: isToday,
    meterModeLabel: !connected
        ? 'Weather estimate'
        : hasChannels
            ? 'Smart meter detected'
            : 'Generation only · appliance load',
    potentialKwh: potential,
    displayGenKwh: displayGen,
    displayLiveKw: displayLive,
    performanceRatioPct: pr,
    displayUsageKwh: displayUsage,
    displayLiveUsageKw: displayLiveUsage,
    selfConsumedKwh: selfConsumed,
    exportedKwh: exported,
    importedKwh: imported,
    netBalanceKwh: net,
    isSurplus: net >= 0,
    solarCoveragePercent: coverage,
    exportTariffInr: exportTariffInr,
    selfSavingsInr: selfSavings,
    exportEarningsInr: exportEarnings,
    totalSavingsInr: selfSavings + exportEarnings,
    co2AvoidedKg: _r1(displayGen * 0.82),
    cumulativeLoggedGenKwh: _r1(cumulative),
    loggedDays: logs.length,
  );
}
