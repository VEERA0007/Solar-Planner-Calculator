import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Single month entry returned by a live DISCOM / USC lookup.
class UscMonthEntry {
  final String month;
  final double units;
  final double amount;
  final bool verified;
  const UscMonthEntry({
    required this.month,
    required this.units,
    required this.amount,
    this.verified = false,
  });

  Map<String, dynamic> toJson() => {
        'month': month,
        'units': units,
        'amount': amount,
        'verified': verified,
      };

  factory UscMonthEntry.fromJson(Map<String, dynamic> j) => UscMonthEntry(
        month: (j['shortLabel'] ?? j['month'] ?? j['label'] ?? j['billMonth'] ?? '').toString(),
        units: ((j['unitsKwh'] ?? j['units'] ?? j['kwh'] ?? 0) as num?)?.toDouble() ?? 0,
        amount: ((j['billAmountInr'] ?? j['billInr'] ?? j['amount'] ?? j['bill'] ?? 0) as num?)?.toDouble() ?? 0,
        verified: (j['isVerifiedPortalData'] as bool?) ?? (j['verified'] as bool?) ?? false,
      );
}

/// Live CAPTCHA challenge returned by DISCOM portals such as TGSPDCL.
class UscCaptchaChallenge {
  final String captchaId;
  final String imageDataUri;
  final Uint8List? imageBytes;
  final String provider;
  final String hint;

  const UscCaptchaChallenge({
    required this.captchaId,
    required this.imageDataUri,
    this.imageBytes,
    this.provider = 'DISCOM',
    this.hint = 'Enter the security code shown above.',
  });

  static Uint8List? decodeDataUri(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final idx = s.indexOf(',');
      final b64 = idx >= 0 ? s.substring(idx + 1) : s;
      return base64Decode(b64.replaceAll(RegExp(r'\s+'), ''));
    } catch (_) {
      return null;
    }
  }

  factory UscCaptchaChallenge.fromJson(Map<String, dynamic> j) {
    final img = (j['image'] ?? j['imageDataUrl'] ?? '').toString();
    return UscCaptchaChallenge(
      captchaId: (j['captchaId'] ?? '').toString(),
      imageDataUri: img,
      imageBytes: decodeDataUri(img),
      provider: (j['provider'] ?? 'DISCOM').toString(),
      hint: (j['hint'] ?? 'Enter the security code shown above to fetch your live bill.').toString(),
    );
  }
}

/// Result of a multi-state USC / Service Number lookup.
class UscBillResult {
  final bool ok;
  final String usc;
  final String stateId;
  final String discomName;
  final String consumerName;
  final String address;
  final double avgMonthlyUnits;
  final double avgMonthlyBill;
  final double? contractedLoadKw;
  final String phaseType;
  final String billDate;
  final String ebillUrl;
  final List<UscMonthEntry> history;
  final String verificationStep; // none | captcha_required | mobile_required | not_found | portal_manual_or_paste
  final UscCaptchaChallenge? captchaChallenge;
  final String? error;
  final String? message;
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
    this.contractedLoadKw,
    this.phaseType = '',
    this.billDate = '',
    this.ebillUrl = '',
    this.history = const [],
    this.verificationStep = 'none',
    this.captchaChallenge,
    this.error,
    this.message,
    this.sourceLabel,
  });

  bool get needsCaptcha => verificationStep == 'captcha_required' && captchaChallenge != null;
  bool get needsMobile => verificationStep == 'mobile_required';
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

  /// Resolves the canonical government portal URL accepted by the backend allowlist.
  static String resolvePortalUrl(String discomId, String fallbackUrl) {
    switch (discomId.toLowerCase()) {
      case 'tgspdcl':
      case 'tsspdcl':
        return 'https://tgsouthernpower.org';
      case 'tgnpdcl':
      case 'tsnpdcl':
        return 'https://tgnpdcl.com';
      case 'apspdcl':
        return 'https://www.apspdcl.in';
      case 'apepdcl':
        return 'https://www.apeasternpower.com';
      case 'apcpdcl':
        return 'https://www.apcpdcl.in';
      case 'tpcodl':
        return 'https://www.tpcentralodisha.com';
      case 'tpnodl':
        return 'https://www.tpnodl.com';
      case 'tpsodl':
        return 'https://www.tpsouthernodisha.com';
      case 'tpwodl':
        return 'https://www.tpwesternodisha.com';
      case 'cspdcl':
        return 'https://cspdcl.co.in';
      default:
        return fallbackUrl.isNotEmpty ? fallbackUrl : 'https://tgsouthernpower.org';
    }
  }

  /// Pings `/api/health` on the configured backend server.
  static Future<({bool ok, String message})> checkHealth(String rawBaseUrl) async {
    final base = cleanBaseUrl(rawBaseUrl);
    if (base.isEmpty) {
      return (ok: false, message: 'Enter your deployed Render or Cloud Run backend URL first.');
    }
    try {
      final r = await http.get(Uri.parse('$base/api/health')).timeout(const Duration(seconds: 10));
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

  /// Refreshes a fresh TGSPDCL CAPTCHA challenge from `/api/utility/captcha`.
  static Future<UscCaptchaChallenge?> refreshCaptcha(String rawBaseUrl) async {
    final base = cleanBaseUrl(rawBaseUrl);
    if (base.isEmpty) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('$base/api/utility/captcha'),
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'discomId': 'tgspdcl'}),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body);
      if (j is! Map) return null;
      final map = j.cast<String, dynamic>();
      final ch = (map['captchaChallenge'] is Map)
          ? (map['captchaChallenge'] as Map).cast<String, dynamic>()
          : map;
      if ((ch['captchaId'] ?? '').toString().isEmpty) return null;
      return UscCaptchaChallenge.fromJson(ch);
    } catch (_) {
      return null;
    }
  }

  /// Fetches live 4-state DISCOM / USC monthly usage via `/api/utility/service-usage`.
  /// Supports live TGSPDCL CAPTCHA verification, APSPDCL mobile verification, and
  /// direct live bill / 12-month history parsing.
  static Future<UscBillResult> fetchUscBill({
    required String rawBaseUrl,
    required String usc,
    required String stateId,
    required String discomId,
    required String category,
    String portalUrl = '',
    String? captchaId,
    String? captchaAnswer,
    String? mobileNumber,
  }) async {
    final base = cleanBaseUrl(rawBaseUrl);
    if (base.isEmpty) {
      return UscBillResult(
        ok: false,
        usc: usc,
        error: 'Set your Live API Server URL in Settings → Display to enable live DISCOM bill fetch, or tap Open Portal below.',
      );
    }
    try {
      final resolvedPortal = resolvePortalUrl(discomId, portalUrl);
      final normalizedState = stateId.toLowerCase() == 'odisha' ? 'odissa' : stateId.toLowerCase();
      final payload = <String, dynamic>{
        'uscNumber': usc,
        'serviceNumber': usc,
        'stateId': normalizedState,
        'discomId': discomId.toLowerCase(),
        'portalUrl': resolvedPortal,
        'billHistoryUrl': resolvedPortal,
        'category': category,
        'requestedMonths': 12,
      };
      if (captchaId != null && captchaId.isNotEmpty) payload['captchaId'] = captchaId;
      if (captchaAnswer != null && captchaAnswer.isNotEmpty) payload['captchaAnswer'] = captchaAnswer.trim();
      if (mobileNumber != null && mobileNumber.isNotEmpty) payload['mobileNumber'] = mobileNumber.trim();

      final resp = await http
          .post(
            Uri.parse('$base/api/utility/service-usage'),
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      final dynamic raw = jsonDecode(resp.body);
      if (raw is! Map) {
        return UscBillResult(ok: false, usc: usc, error: 'Unexpected response from server.');
      }
      final j = raw.cast<String, dynamic>();
      if (resp.statusCode != 200 || j['ok'] == false) {
        return UscBillResult(
          ok: false,
          usc: usc,
          error: (j['error'] ?? j['message'] ?? 'DISCOM lookup failed (HTTP ${resp.statusCode}).').toString(),
        );
      }

      final verificationStep = (j['verificationStep'] ?? 'none').toString();
      final captchaRaw = j['captchaChallenge'];
      final captcha = (captchaRaw is Map) ? UscCaptchaChallenge.fromJson(captchaRaw.cast<String, dynamic>()) : null;
      final liveBill = (j['livePortalBill'] is Map) ? (j['livePortalBill'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final consumer = (j['consumer'] is Map) ? (j['consumer'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final rawHist = (j['usage12Months'] ?? j['history'] ?? j['monthlyHistory'] ?? j['bills'] ?? const []) as List;

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
      if (avgUnits <= 0 && liveBill['unitsKwh'] is num) {
        avgUnits = (liveBill['unitsKwh'] as num).toDouble();
      }
      if (avgBill <= 0 && history.isNotEmpty) {
        final withAmt = history.where((e) => e.amount > 0).toList();
        if (withAmt.isNotEmpty) {
          avgBill = withAmt.fold(0.0, (a, e) => a + e.amount) / withAmt.length;
        }
      }
      if (avgBill <= 0 && liveBill['billAmountInr'] is num) {
        avgBill = (liveBill['billAmountInr'] as num).toDouble();
      }

      final consumerName = (liveBill['consumerName'] ?? j['consumerName'] ?? consumer['name'] ?? '').toString();
      final address = (liveBill['consumerAddress'] ?? j['address'] ?? consumer['address'] ?? '').toString();
      final contractedLoadKw = (liveBill['contractedLoadKw'] as num?)?.toDouble() ?? (j['sanctionedLoadKw'] as num?)?.toDouble();
      final phaseType = (liveBill['phaseType'] ?? j['phaseType'] ?? '').toString();
      final billDate = (liveBill['billDate'] ?? '').toString();
      final ebillUrl = (liveBill['viewEbillUrl'] ?? '').toString();
      final msg = (j['message'] ?? '').toString();

      final hasData = avgUnits > 0 || avgBill > 0;
      return UscBillResult(
        ok: hasData,
        usc: (j['uscNumber'] ?? usc).toString(),
        stateId: stateId,
        discomName: (j['discomName'] ?? liveBill['sourcePortal'] ?? discomId.toUpperCase()).toString(),
        consumerName: consumerName,
        address: address,
        avgMonthlyUnits: avgUnits,
        avgMonthlyBill: avgBill,
        contractedLoadKw: contractedLoadKw,
        phaseType: phaseType,
        billDate: billDate,
        ebillUrl: ebillUrl,
        history: history,
        verificationStep: verificationStep,
        captchaChallenge: captcha,
        sourceLabel: (j['dataSourceMode'] ?? j['source'] ?? 'Live DISCOM').toString(),
        message: msg.isNotEmpty ? msg : null,
        error: hasData
            ? null
            : (msg.isNotEmpty ? msg : 'No billing units returned for this service number.'),
      );
    } catch (e) {
      return UscBillResult(ok: false, usc: usc, error: 'Live bill fetch failed: $e');
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
    final base = cleanBaseUrl(rawBaseUrl);
    if (base.isEmpty) {
      return (ok: false, rate: null, label: null, error: 'No backend URL configured');
    }
    try {
      final normalizedState = stateId.toLowerCase() == 'odisha' ? 'odissa' : stateId.toLowerCase();
      final uri = Uri.parse('$base/api/tariff/realtime').replace(queryParameters: {
        'stateId': normalizedState,
        'providerId': discomId.toLowerCase(),
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

    final base = cleanBaseUrl(rawBaseUrl);
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
      if (watts > 0) currentKw = watts > 200 ? watts / 1000 : watts;
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
      plantName: (j['plantName'] ?? j['stationName'] ?? j['deviceName'] ?? '').toString(),
      plantStatus: plantStatus,
      loggerStatus: loggerStatus,
      currentKw: currentKw,
      todayKwh: numVal(['todayKwh', 'dailyEnergyKwh', 'eToday', 'todayGenerationKwh', 'dayEnergy']),
      monthKwh: numVal(['monthKwh', 'monthlyEnergyKwh', 'eMonth', 'monthEnergy']),
      totalKwh: numVal(['totalKwh', 'totalEnergyKwh', 'eTotal', 'lifetimeKwh']),
      ratedKw: numVal(['ratedKw', 'capacityKw', 'installedCapacityKw', 'systemSizeKw']),
      gridVoltageV: optNum(['gridVoltageV', 'acVoltageV', 'uAc1']),
      inverterTempC: optNum(['inverterTempC', 'temperatureC', 'tempC']),
      batterySocPct: optNum(['batterySocPct', 'batterySoc', 'soc']),
      dailyLogs: logs,
      syncedAt: DateTime.now().millisecondsSinceEpoch,
      note: (j['note'] ?? j['message'] ?? '').toString(),
    );
  }
}
