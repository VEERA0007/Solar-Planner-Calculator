import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'usc_http.dart' show kUscBackendUrl;

/// USC digit counts per DISCOM, from the Worker's DISCOM table (worker/src/discoms.js).
const Map<String, List<int>> kUscLengths = {
  'TGNPDCL': [8],
  'TGSPDCL': [9, 10, 11, 12],
};

/// Single month entry returned by a live DISCOM / USC lookup.
class UscMonthEntry {
  final String month;
  final double units;
  final double amount;
  const UscMonthEntry({required this.month, required this.units, required this.amount});

  Map<String, dynamic> toJson() => {'month': month, 'units': units, 'amount': amount};
  factory UscMonthEntry.fromJson(Map<String, dynamic> j) => UscMonthEntry(
        month: (j['month'] ?? j['label'] ?? j['billMonth'] ?? '').toString(),
        units: ((j['units'] ?? j['unitsKwh'] ?? j['kwh'] ?? 0) as num?)?.toDouble() ?? 0,
        amount: ((j['amount'] ?? j['billInr'] ?? j['bill'] ?? 0) as num?)?.toDouble() ?? 0,
      );
}

/// Result of a 4-state USC / Service Number lookup.
class UscBillResult {
  final bool ok;
  final String usc;
  final String stateId;
  final String discomName;
  final String consumerName;
  final String address;
  final double avgMonthlyUnits;
  final double avgMonthlyBill;
  final List<UscMonthEntry> history;
  final String? error;
  final String? sourceLabel;

  const UscBillResult({
    required this.ok,
    required this.usc,
    this.stateId = '',
    this.discomName = '',
    this.consumerName = '',
    this.address = '',
    this.avgMonthlyUnits = 0,
    this.avgMonthlyBill = 0,
    this.history = const [],
    this.error,
    this.sourceLabel,
  });
}

/// Stored recent USC search entry (persisted in SharedPreferences).
class UscHistoryItem {
  final String usc;
  final String stateId;
  final String discomName;
  final String consumerName;
  final double avgMonthlyUnits;
  final int savedAt;

  const UscHistoryItem({
    required this.usc,
    required this.stateId,
    required this.discomName,
    required this.consumerName,
    required this.avgMonthlyUnits,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'usc': usc,
        'stateId': stateId,
        'discomName': discomName,
        'consumerName': consumerName,
        'avgMonthlyUnits': avgMonthlyUnits,
        'savedAt': savedAt,
      };

  factory UscHistoryItem.fromJson(Map<String, dynamic> j) => UscHistoryItem(
        usc: (j['usc'] as String?) ?? '',
        stateId: (j['stateId'] as String?) ?? '',
        discomName: (j['discomName'] as String?) ?? '',
        consumerName: (j['consumerName'] as String?) ?? '',
        avgMonthlyUnits: (j['avgMonthlyUnits'] as num?)?.toDouble() ?? 0,
        savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
      );
}

/// One daily generation bar from an inverter portal/API sync.
class InverterDailyLog {
  final String date;
  final double kwh;
  const InverterDailyLog({required this.date, required this.kwh});

  Map<String, dynamic> toJson() => {'date': date, 'kwh': kwh};
  factory InverterDailyLog.fromJson(Map<String, dynamic> j) => InverterDailyLog(
        date: (j['date'] ?? j['day'] ?? '').toString(),
        kwh: ((j['kwh'] ?? j['energy'] ?? j['eToday'] ?? 0) as num?)?.toDouble() ?? 0,
      );
}

/// Supported inverter brands for the 2-option Inverter Hub
/// (Option 1: Manufacturer Website Login, Option 2: API Integration).
const List<(String id, String label, String portalUrl)> kInverterBrands = [
  ('soliscloud', 'SolisCloud', 'https://www.soliscloud.com'),
  ('solarman', 'Solarman (Deye / Sofar / Havells)', 'https://home.solarmanpv.com'),
  ('growatt', 'Growatt ShineServer', 'https://server.growatt.com'),
  ('sungrow', 'Sungrow iSolarCloud', 'https://www.isolarcloud.com'),
  ('goodwe', 'GoodWe SEMS Portal', 'https://www.semsportal.com'),
];

/// Saved configuration for the 2-option Inverter Sync Hub.
class InverterConfig {
  /// Strictly two modes: 'website' (Manufacturer Website Login) or 'api' (API Integration).
  String authMode;
  String brand;
  String username;
  String apiKey;
  String stationId;
  String loggerSerial;
  String inverterSerial;
  String customEndpoint;

  InverterConfig({
    this.authMode = 'website',
    this.brand = 'soliscloud',
    this.username = '',
    this.apiKey = '',
    this.stationId = '',
    this.loggerSerial = '',
    this.inverterSerial = '',
    this.customEndpoint = '',
  });

  Map<String, dynamic> toJson() => {
        'authMode': authMode,
        'brand': brand,
        'username': username,
        'apiKey': apiKey,
        'stationId': stationId,
        'loggerSerial': loggerSerial,
        'inverterSerial': inverterSerial,
        'customEndpoint': customEndpoint,
      };

  factory InverterConfig.fromJson(Map<String, dynamic> j) => InverterConfig(
        authMode: (j['authMode'] as String?) == 'api' ? 'api' : 'website',
        brand: (j['brand'] as String?) ?? 'soliscloud',
        username: (j['username'] as String?) ?? '',
        apiKey: (j['apiKey'] as String?) ?? '',
        stationId: (j['stationId'] as String?) ?? '',
        loggerSerial: (j['loggerSerial'] as String?) ?? '',
        inverterSerial: (j['inverterSerial'] as String?) ?? '',
        customEndpoint: (j['customEndpoint'] as String?) ?? '',
      );
}

/// Latest live telemetry snapshot returned from Manufacturer Website Login or API Integration.
class InverterSnapshot {
  final String brand;
  final String authMode;
  final String plantName;
  final String plantStatus; // online | offline | standby | fault
  final String loggerStatus; // online | offline | unknown
  final double currentKw;
  final double todayKwh;
  final double monthKwh;
  final double totalKwh;
  final double ratedKw;
  final double? gridVoltageV;
  final double? inverterTempC;
  final double? batterySocPct;
  final List<InverterDailyLog> dailyLogs;
  final int syncedAt;
  final String note;

  const InverterSnapshot({
    required this.brand,
    required this.authMode,
    this.plantName = '',
    this.plantStatus = 'online',
    this.loggerStatus = 'unknown',
    this.currentKw = 0,
    this.todayKwh = 0,
    this.monthKwh = 0,
    this.totalKwh = 0,
    this.ratedKw = 0,
    this.gridVoltageV,
    this.inverterTempC,
    this.batterySocPct,
    this.dailyLogs = const [],
    required this.syncedAt,
    this.note = '',
  });

  bool get isPlantOnline => plantStatus.toLowerCase() == 'online';
  bool get isLoggerOnline => loggerStatus.toLowerCase() == 'online';

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'authMode': authMode,
        'plantName': plantName,
        'plantStatus': plantStatus,
        'loggerStatus': loggerStatus,
        'currentKw': currentKw,
        'todayKwh': todayKwh,
        'monthKwh': monthKwh,
        'totalKwh': totalKwh,
        'ratedKw': ratedKw,
        'gridVoltageV': gridVoltageV,
        'inverterTempC': inverterTempC,
        'batterySocPct': batterySocPct,
        'dailyLogs': dailyLogs.map((e) => e.toJson()).toList(),
        'syncedAt': syncedAt,
        'note': note,
      };

  factory InverterSnapshot.fromJson(Map<String, dynamic> j) => InverterSnapshot(
        brand: (j['brand'] as String?) ?? 'soliscloud',
        authMode: (j['authMode'] as String?) ?? 'website',
        plantName: (j['plantName'] as String?) ?? '',
        plantStatus: (j['plantStatus'] as String?) ?? 'online',
        loggerStatus: (j['loggerStatus'] as String?) ?? 'unknown',
        currentKw: (j['currentKw'] as num?)?.toDouble() ?? 0,
        todayKwh: (j['todayKwh'] as num?)?.toDouble() ?? 0,
        monthKwh: (j['monthKwh'] as num?)?.toDouble() ?? 0,
        totalKwh: (j['totalKwh'] as num?)?.toDouble() ?? 0,
        ratedKw: (j['ratedKw'] as num?)?.toDouble() ?? 0,
        gridVoltageV: (j['gridVoltageV'] as num?)?.toDouble(),
        inverterTempC: (j['inverterTempC'] as num?)?.toDouble(),
        batterySocPct: (j['batterySocPct'] as num?)?.toDouble(),
        dailyLogs: ((j['dailyLogs'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => InverterDailyLog.fromJson(e.cast<String, dynamic>()))
            .toList(),
        syncedAt: (j['syncedAt'] as num?)?.toInt() ?? 0,
        note: (j['note'] as String?) ?? '',
      );
}

/// Pure Dart HTTP client for optional live backend proxy (Render / Cloud Run).
class BackendService {
  static String cleanBaseUrl(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return 'https://$s';
  }

  /// The URL the app calls: the one set in Settings, otherwise the Worker built into the app.
  static String resolveBase(String raw) {
    final mine = cleanBaseUrl(raw);
    if (mine.isNotEmpty) return mine;
    return cleanBaseUrl(kUscBackendUrl);
  }

  /// Pings `/api/health` on the backend, or its root route (the Worker answers there).
  static Future<({bool ok, String message})> checkHealth(String rawBaseUrl) async {
    final base = resolveBase(rawBaseUrl);
    if (base.isEmpty) {
      return (ok: false, message: 'No backend URL is built into this app, and none is set in Settings.');
    }
    try {
      var r = await http.get(Uri.parse('$base/api/health')).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        r = await http.get(Uri.parse('$base/')).timeout(const Duration(seconds: 10));
      }
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final status = (j is Map ? j['status'] : null) ?? 'ok';
        return (ok: true, message: 'Connected ($status)');
      }
      return (ok: false, message: 'Server returned HTTP ${r.statusCode}');
    } catch (e) {
      return (ok: false, message: 'Could not reach server: $e');
    }
  }

  /// Fetches live 4-state DISCOM / USC monthly usage via `/api/utility/service-usage`.
  static Future<UscBillResult> fetchUscBill({
    required String rawBaseUrl,
    required String usc,
    required String stateId,
    required String discomId,
    required String category,
  }) async {
    final base = resolveBase(rawBaseUrl);
    final discom = discomId.trim().toUpperCase();
    final digits = usc.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return UscBillResult(ok: false, usc: usc, error: 'Enter your USC / service number.');
    }
    final lengths = kUscLengths[discom];
    if (lengths != null && !lengths.contains(digits.length)) {
      final want = lengths.length == 1 ? '${lengths.first} digits' : '${lengths.first} to ${lengths.last} digits';
      return UscBillResult(
        ok: false,
        usc: usc,
        error: '$discom USC numbers are $want. You entered ${digits.length} digits.',
      );
    }
    if (base.isEmpty) {
      return UscBillResult(ok: false, usc: usc, error: 'The live bill service is not set up in this build.');
    }
    try {
      final resp = await http
          .post(
            Uri.parse('$base/api/usc/fetch'),
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'usc': digits, 'discom': discom}),
          )
          .timeout(const Duration(seconds: 40));

      final dynamic raw = jsonDecode(resp.body);
      if (raw is! Map) {
        return UscBillResult(ok: false, usc: usc, error: 'Unexpected response from server.');
      }
      final j = raw.cast<String, dynamic>();
      if (resp.statusCode != 200 || j['ok'] == false) {
        final needsCode = resp.statusCode == 409 || j['captchaRequired'] == true;
        return UscBillResult(
          ok: false,
          usc: usc,
          error: needsCode
              ? '$discom needs a security code, which this screen does not support yet. Use the portal for now.'
              : (j['error'] ?? j['message'] ?? 'DISCOM lookup failed (HTTP ${resp.statusCode}).').toString(),
        );
      }

      final consumer = (j['consumer'] is Map) ? (j['consumer'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final rawHist = (j['months'] ?? j['history'] ?? j['monthlyHistory'] ?? const []) as List;
      final history = rawHist
          .whereType<Map>()
          .map((e) => UscMonthEntry.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.units > 0 || e.amount > 0)
          .toList();

      double avgUnits = ((j['averageMonthlyUnits'] ?? j['avgMonthlyUnits'] ?? j['monthlyUnits'] ?? 0) as num?)?.toDouble() ?? 0;
      double avgBill = ((j['averageMonthlyBill'] ?? j['avgMonthlyBill'] ?? j['monthlyBill'] ?? 0) as num?)?.toDouble() ?? 0;

      if (avgUnits <= 0 && history.isNotEmpty) {
        final withUnits = history.where((e) => e.units > 0).toList();
        if (withUnits.isNotEmpty) {
          avgUnits = withUnits.fold(0.0, (a, e) => a + e.units) / withUnits.length;
        }
      }
      if (avgBill <= 0 && history.isNotEmpty) {
        final withAmt = history.where((e) => e.amount > 0).toList();
        if (withAmt.isNotEmpty) {
          avgBill = withAmt.fold(0.0, (a, e) => a + e.amount) / withAmt.length;
        }
      }

      return UscBillResult(
        ok: avgUnits > 0 || avgBill > 0,
        usc: usc,
        stateId: stateId,
        discomName: (j['discomName'] ?? consumer['discom'] ?? discomId).toString(),
        consumerName: (consumer['name'] ?? j['consumerName'] ?? '').toString(),
        address: (consumer['address'] ?? j['address'] ?? '').toString(),
        avgMonthlyUnits: avgUnits,
        avgMonthlyBill: avgBill,
        history: history,
        sourceLabel: (j['source'] ?? j['verificationStatus'] ?? 'Live DISCOM').toString(),
        error: (avgUnits <= 0 && avgBill <= 0) ? 'No billing units returned for this service number.' : null,
      );
    } on TimeoutException {
      return UscBillResult(
        ok: false,
        usc: usc,
        error: 'The DISCOM portal did not answer in time. Try again in a minute, or use the portal.',
      );
    } catch (e) {
      return UscBillResult(ok: false, usc: usc, error: 'Live bill fetch failed. Try again in a minute.');
    }
  }

  /// Fetches live electricity unit price from `/api/tariff/realtime` if backend URL is set.
  static Future<({bool ok, double? rate, String? label, String? error})> fetchRealtimeTariff({
    required String rawBaseUrl,
    required String stateId,
    required String discomId,
    required String category,
    required double monthlyUnits,
  }) async {
    final base = resolveBase(rawBaseUrl);
    if (base.isEmpty) {
      return (ok: false, rate: null, label: null, error: 'No backend URL configured');
    }
    try {
      final uri = Uri.parse('$base/api/tariff/realtime').replace(queryParameters: {
        'stateId': stateId,
        'providerId': discomId,
        'category': category,
        'monthlyUnits': monthlyUnits.round().toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        return (ok: false, rate: null, label: null, error: 'HTTP ${resp.statusCode}');
      }
      final j = jsonDecode(resp.body);
      if (j is! Map) return (ok: false, rate: null, label: null, error: 'Invalid tariff payload');
      final rate = ((j['effectiveUnitRate'] ?? j['unitRate'] ?? j['tariff'] ?? j['rate']) as num?)?.toDouble();
      final label = (j['orderRef'] ?? j['source'] ?? j['providerName'])?.toString();
      if (rate != null && rate > 0) {
        return (ok: true, rate: rate, label: label, error: null);
      }
      return (ok: false, rate: null, label: null, error: 'No unit rate returned');
    } catch (e) {
      return (ok: false, rate: null, label: null, error: '$e');
    }
  }

  /// Syncs live inverter data using STRICTLY one of the 2 supported options:
  /// 1. `authMode == 'website'`: Manufacturer Website Login (email/username + password)
  /// 2. `authMode == 'api'`: Official API Integration (API Key + Secret or custom JSON endpoint)
  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> syncInverter({
    required String rawBaseUrl,
    required InverterConfig config,
    String password = '',
    String apiSecret = '',
  }) async {
    final isApi = config.authMode == 'api';

    // Direct custom HTTPS JSON API option works even without a backend server.
    if (isApi && config.customEndpoint.trim().isNotEmpty) {
      final endpoint = cleanBaseUrl(config.customEndpoint);
      try {
        final headers = <String, String>{'Accept': 'application/json'};
        if (config.apiKey.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
          headers['X-API-Key'] = config.apiKey.trim();
        }
        final resp = await http.get(Uri.parse(endpoint), headers: headers).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) {
          return (ok: false, snapshot: null, error: 'API endpoint returned HTTP ${resp.statusCode}.');
        }
        final dynamic raw = jsonDecode(resp.body);
        if (raw is! Map) {
          return (ok: false, snapshot: null, error: 'API response was not a JSON object.');
        }
        return (
          ok: true,
          snapshot: _parseSnapshot(raw.cast<String, dynamic>(), config.brand, 'api'),
          error: null,
        );
      } catch (e) {
        return (ok: false, snapshot: null, error: 'Direct API request failed: $e');
      }
    }

    final base = resolveBase(rawBaseUrl);
    if (base.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: isApi
            ? 'Enter either a Custom API Endpoint URL above, or configure your Backend Server URL in Settings → Display for manufacturer API signing.'
            : 'Configure your Backend Server URL in Settings → Display to log into manufacturer websites without CORS blocks.',
      );
    }

    try {
      final payload = <String, dynamic>{
        'brand': config.brand,
        'authMode': isApi ? 'api' : 'website',
        'stationId': config.stationId.trim(),
        'loggerSerial': config.loggerSerial.trim(),
        'inverterSerial': config.inverterSerial.trim(),
      };
      if (isApi) {
        payload['apiKey'] = config.apiKey.trim();
        payload['apiSecret'] = apiSecret;
      } else {
        payload['username'] = config.username.trim();
        payload['password'] = password;
      }

      final resp = await http
          .post(
            Uri.parse('$base/api/inverter/portal-sync'),
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      final dynamic raw = jsonDecode(resp.body);
      if (raw is! Map) {
        return (ok: false, snapshot: null, error: 'Unexpected server response.');
      }
      final j = raw.cast<String, dynamic>();
      if (resp.statusCode != 200 || j['ok'] == false) {
        return (
          ok: false,
          snapshot: null,
          error: (j['error'] ?? j['message'] ?? 'Inverter sync failed (HTTP ${resp.statusCode}).').toString(),
        );
      }

      final dataMap = (j['telemetry'] is Map)
          ? (j['telemetry'] as Map).cast<String, dynamic>()
          : (j['data'] is Map ? (j['data'] as Map).cast<String, dynamic>() : j);

      return (
        ok: true,
        snapshot: _parseSnapshot({...j, ...dataMap}, config.brand, config.authMode),
        error: null,
      );
    } catch (e) {
      return (ok: false, snapshot: null, error: 'Inverter sync failed: $e');
    }
  }

  static InverterSnapshot _parseSnapshot(Map<String, dynamic> j, String brand, String authMode) {
    double numVal(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final p = double.tryParse(v);
          if (p != null) return p;
        }
      }
      return 0;
    }

    double? optNum(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final p = double.tryParse(v);
          if (p != null) return p;
        }
      }
      return null;
    }

    var currentKw = numVal(['currentPowerKw', 'livePowerKw', 'powerKw', 'acPowerKw', 'pacKw']);
    if (currentKw == 0) {
      final watts = numVal(['currentPowerW', 'livePowerW', 'pac', 'acPowerW', 'powerW']);
      // These keys are always watts. Dividing by 1000 keeps a 15.7 W standby reading from showing as 15.7 kW.
      if (watts > 0) currentKw = watts / 1000;
    }

    final rawLogs = (j['dailyLogs'] ?? j['dailyGeneration'] ?? j['history'] ?? const []) as List;
    final logs = rawLogs
        .whereType<Map>()
        .map((e) => InverterDailyLog.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.date.isNotEmpty)
        .toList();

    final plantStatus = (j['plantStatus'] ?? j['inverterStatus'] ?? j['status'] ?? (currentKw > 0 ? 'online' : 'standby'))
        .toString()
        .toLowerCase();
    final loggerStatus = (j['loggerStatus'] ?? j['collectorStatus'] ?? j['dataLoggerStatus'] ?? 'online')
        .toString()
        .toLowerCase();

    return InverterSnapshot(
      brand: (j['brand'] ?? brand).toString(),
      authMode: authMode,
      plantName: (j['plantName'] ?? j['detectedPlantName'] ?? j['stationName'] ?? j['deviceName'] ?? '').toString(),
      plantStatus: plantStatus,
      loggerStatus: loggerStatus,
      currentKw: currentKw,
      todayKwh: numVal(['todayKwh', 'todayGenKwh', 'dailyEnergyKwh', 'eToday', 'todayGenerationKwh', 'dayEnergy']),
      monthKwh: numVal(['monthKwh', 'monthlyEnergyKwh', 'eMonth', 'monthEnergy']),
      totalKwh: numVal(['totalKwh', 'totalEnergyKwh', 'eTotal', 'lifetimeKwh']),
      ratedKw: numVal(['ratedKw', 'detectedCapacityKwp', 'capacityKw', 'installedCapacityKw', 'systemSizeKw']),
      gridVoltageV: optNum(['gridVoltageV', 'acVoltageV', 'uAc1']),
      inverterTempC: optNum(['inverterTempC', 'temperatureC', 'tempC']),
      batterySocPct: optNum(['batterySocPct', 'batterySoc', 'soc']),
      dailyLogs: logs,
      syncedAt: DateTime.now().millisecondsSinceEpoch,
      note: (j['note'] ?? j['message'] ?? '').toString(),
    );
  }
}
