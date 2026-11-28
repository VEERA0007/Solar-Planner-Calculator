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
  ('polygun', 'Polygun / Polycab Solar', 'https://minvertermonitoring.polycab.com'),
  ('pure', 'PURE / PuREPower Solar', 'https://pureenergy.co.in'),
  ('hitachi', 'Hitachi Solar (Hi-Rel)', 'https://www.hitachi-hirel.com'),
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

/// Pure Dart HTTP client supporting BOTH direct native DISCOM government portal
/// calls (zero backend server required on Android/iOS/Desktop) and optional
/// Render / Cloud Run proxy URLs.
class BackendService {
  static const String _tgspdclPublicKey = 'TGSWpDcL2025XkNpMqRvFzAcYeUhBsJ3';

  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/html, */*;q=0.8',
    'Accept-Language': 'en-IN,en;q=0.9',
  };

  static String cleanBaseUrl(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return 'https://$s';
  }

  /// Resolves the canonical government portal URL accepted by DISCOM portals.
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

  /// Pings `/api/health` on the configured optional backend server.
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

  /// Parses pasted 12-month portal bill rows (e.g. "Nov 2025 340 2450" or "Jan-26  410  2890").
  static List<UscMonthEntry> parsePastedBillRows(String text) {
    final out = <UscMonthEntry>[];
    final lines = text.split(RegExp(r'[\r\n]+'));
    final monthRx = RegExp(
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*[\s\-/]*(\d{2,4})?\b',
      caseSensitive: false,
    );
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = monthRx.firstMatch(line);
      final label = m != null ? m.group(0)!.trim() : 'M${out.length + 1}';
      final stripped = m != null ? line.replaceFirst(m.group(0)!, ' ') : line;
      final nums = RegExp(r'\d+(?:,\d+)*(?:\.\d+)?')
          .allMatches(stripped)
          .map((e) => double.tryParse(e.group(0)!.replaceAll(',', '')) ?? -1)
          .where((v) => v >= 0 && v < 1000000)
          .toList();
      if (nums.isEmpty) continue;
      // Ignore leading serial number 1..24 when 3+ numbers appear
      final vals = (nums.length >= 3 && nums[0] >= 1 && nums[0] <= 24 && nums[0] == nums[0].roundToDouble())
          ? nums.sublist(1)
          : nums;
      final units = vals[0];
      final amt = vals.length >= 2 ? vals[1] : 0.0;
      if (units > 0 || amt > 0) {
        out.add(UscMonthEntry(month: label, units: units, amount: amt, verified: true));
      }
    }
    return out;
  }

  /// Refreshes a fresh TGSPDCL CAPTCHA challenge.
  /// Works directly against TGSPDCL when no backend server URL is configured.
  static Future<UscCaptchaChallenge?> refreshCaptcha(String rawBaseUrl) async {
    final base = cleanBaseUrl(rawBaseUrl);
    if (base.isNotEmpty) {
      try {
        final resp = await http
            .post(
              Uri.parse('$base/api/utility/captcha'),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({'discomId': 'tgspdcl'}),
            )
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          final j = jsonDecode(resp.body);
          if (j is Map) {
            final map = j.cast<String, dynamic>();
            final ch = (map['captchaChallenge'] is Map)
                ? (map['captchaChallenge'] as Map).cast<String, dynamic>()
                : map;
            if ((ch['captchaId'] ?? '').toString().isNotEmpty) {
              return UscCaptchaChallenge.fromJson(ch);
            }
          }
        }
      } catch (_) {
        // Fall through to direct TGSPDCL portal call
      }
    }
    return _fetchTgspdclCaptchaDirect();
  }

  /// Fetches live DISCOM / USC monthly usage.
  /// If a Backend Server URL is configured in Settings, tries it first and falls
  /// back to direct native DISCOM API calls on failure. If no Backend Server URL
  /// is configured, connects DIRECTLY to official DISCOM APIs in pure Dart!
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
    if (base.isNotEmpty) {
      final proxyRes = await _fetchUscViaBackend(
        base: base,
        usc: usc,
        stateId: stateId,
        discomId: discomId,
        category: category,
        portalUrl: portalUrl,
        captchaId: captchaId,
        captchaAnswer: captchaAnswer,
        mobileNumber: mobileNumber,
      );
      if (proxyRes != null) return proxyRes;
    }

    // Direct native Flutter HTTPS fetch (no backend server required!)
    return _fetchUscDirect(
      usc: usc,
      stateId: stateId,
      discomId: discomId,
      category: category,
      portalUrl: portalUrl,
      captchaId: captchaId,
      captchaAnswer: captchaAnswer,
      mobileNumber: mobileNumber,
    );
  }

  static Future<UscBillResult?> _fetchUscViaBackend({
    required String base,
    required String usc,
    required String stateId,
    required String discomId,
    required String category,
    required String portalUrl,
    String? captchaId,
    String? captchaAnswer,
    String? mobileNumber,
  }) async {
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
          .timeout(const Duration(seconds: 22));

      final dynamic raw = jsonDecode(resp.body);
      if (raw is! Map) return null;
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

      double avgUnits = _toDouble(j['averageMonthlyUnits'] ?? j['avgMonthlyUnits'] ?? j['monthlyUnits']);
      double avgBill = _toDouble(j['averageMonthlyBill'] ?? j['avgMonthlyBill'] ?? j['monthlyBill']);

      if (avgUnits <= 0 && history.isNotEmpty) {
        final withUnits = history.where((e) => e.units > 0).toList();
        if (withUnits.isNotEmpty) {
          avgUnits = withUnits.fold(0.0, (a, e) => a + e.units) / withUnits.length;
        }
      }
      if (avgUnits <= 0) avgUnits = _toDouble(liveBill['unitsKwh']);
      if (avgBill <= 0 && history.isNotEmpty) {
        final withAmt = history.where((e) => e.amount > 0).toList();
        if (withAmt.isNotEmpty) {
          avgBill = withAmt.fold(0.0, (a, e) => a + e.amount) / withAmt.length;
        }
      }
      if (avgBill <= 0) avgBill = _toDouble(liveBill['billAmountInr']);

      final consumerName = (liveBill['consumerName'] ?? j['consumerName'] ?? consumer['name'] ?? '').toString();
      final address = (liveBill['consumerAddress'] ?? j['address'] ?? consumer['address'] ?? '').toString();
      final contractedLoadKw = _optDouble(liveBill['contractedLoadKw'] ?? j['sanctionedLoadKw']);
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
        error: hasData ? null : (msg.isNotEmpty ? msg : 'No billing units returned for this service number.'),
      );
    } catch (_) {
      return null; // Fall back to direct DISCOM fetch
    }
  }

  // -------------------- Direct Native DISCOM API Fetchers --------------------

  static Future<UscBillResult> _fetchUscDirect({
    required String usc,
    required String stateId,
    required String discomId,
    required String category,
    required String portalUrl,
    String? captchaId,
    String? captchaAnswer,
    String? mobileNumber,
  }) async {
    final dc = discomId.toLowerCase().trim();
    if (dc == 'tgspdcl' || dc == 'tsspdcl') {
      return _fetchTgspdclDirect(
        usc: usc,
        stateId: stateId,
        captchaId: captchaId,
        captchaAnswer: captchaAnswer,
      );
    }
    if (dc == 'tgnpdcl' || dc == 'tsnpdcl') {
      return _fetchTgnpdclDirect(usc: usc, stateId: stateId);
    }
    if (dc == 'apepdcl') {
      return _fetchApepdclDirect(usc: usc, stateId: stateId);
    }
    if (dc == 'apspdcl') {
      return _fetchApspdclDirect(usc: usc, stateId: stateId, mobileNumber: mobileNumber);
    }

    // Odisha (TPNODL/TPCODL/TPSODL/TPWODL), APCPDCL, Chhattisgarh (CSPDCL)
    final digitsOnly = usc.replaceAll(RegExp(r'\D'), '');
    final isOdisha = stateId.toLowerCase().contains('odis') || dc.startsWith('tp');
    if (isOdisha && digitsOnly.length == 9) {
      return UscBillResult(
        ok: false,
        usc: usc,
        stateId: stateId,
        discomName: dc.toUpperCase(),
        verificationStep: 'portal_manual_or_paste',
        message:
            'Odisha ${dc.toUpperCase()} Consumer Numbers are 11–12 digits. "$usc" has 9 digits (Telangana TGSPDCL format) — switch State to Telangana → TGSPDCL and tap Fetch, or tap Open Portal / Paste Bills below.',
        error:
            'Odisha ${dc.toUpperCase()} Consumer Numbers are 11–12 digits. If "$usc" is a Telangana USC number, switch State to Telangana → TGSPDCL and tap Fetch.',
      );
    }
    if (isOdisha && digitsOnly.length == 8) {
      return UscBillResult(
        ok: false,
        usc: usc,
        stateId: stateId,
        discomName: dc.toUpperCase(),
        verificationStep: 'portal_manual_or_paste',
        message:
            'Odisha ${dc.toUpperCase()} Consumer Numbers are 11–12 digits. If "$usc" is a Telangana TGNPDCL or AP USC number, switch State/DISCOM and tap Fetch.',
        error:
            'Odisha ${dc.toUpperCase()} Consumer Numbers are 11–12 digits. Switch State/DISCOM if this is a Telangana/AP USC, or tap Open Portal / Paste Bills.',
      );
    }

    return UscBillResult(
      ok: false,
      usc: usc,
      stateId: stateId,
      discomName: dc.toUpperCase(),
      verificationStep: 'portal_manual_or_paste',
      message:
          '${dc.toUpperCase()} requires consumer login on its official portal for personal bill history. Tap Open ${dc.toUpperCase()} Portal and copy your monthly bill rows into Paste Bills below.',
      error:
          '${dc.toUpperCase()} requires consumer login on its official portal. Tap Open ${dc.toUpperCase()} Portal and use Paste Bills below to auto-fill 12-month usage.',
    );
  }

  static Future<UscCaptchaChallenge?> _fetchTgspdclCaptchaDirect() async {
    try {
      final resp = await http.get(
        Uri.parse('https://tgsouthernpower.org/api/captcha/generate'),
        headers: {
          ..._browserHeaders,
          'X-API-Key': _tgspdclPublicKey,
          'Referer': 'https://tgsouthernpower.org/',
        },
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final raw = jsonDecode(resp.body);
      if (raw is! Map) return null;
      final j = raw.cast<String, dynamic>();
      if ((j['captchaId'] ?? '').toString().isEmpty || (j['image'] ?? '').toString().isEmpty) {
        return null;
      }
      return UscCaptchaChallenge.fromJson({
        'captchaId': j['captchaId'],
        'image': j['image'],
        'provider': 'TGSPDCL',
        'hint': 'Enter the security code from TGSPDCL above to fetch your live meter reading & bill.',
      });
    } catch (_) {
      return null;
    }
  }

  static Future<UscBillResult> _fetchTgspdclDirect({
    required String usc,
    required String stateId,
    String? captchaId,
    String? captchaAnswer,
  }) async {
    var lookupToken = '';

    // 1. Exchange CAPTCHA answer for X-Lookup-Token if supplied
    if (captchaId != null && captchaId.isNotEmpty && captchaAnswer != null && captchaAnswer.trim().isNotEmpty) {
      try {
        final tokenResp = await http
            .post(
              Uri.parse('https://tgsouthernpower.org/api/public/lookup-token'),
              headers: {
                ..._browserHeaders,
                'Content-Type': 'application/json',
                'X-API-Key': _tgspdclPublicKey,
                'Referer': 'https://tgsouthernpower.org/',
              },
              body: jsonEncode({
                'captchaId': captchaId,
                'answer': captchaAnswer.trim(),
              }),
            )
            .timeout(const Duration(seconds: 10));
        final tokenRaw = _tryJsonMap(tokenResp.body);
        if (tokenResp.statusCode != 200 || (tokenRaw?['token'] ?? '').toString().isEmpty) {
          final fresh = await _fetchTgspdclCaptchaDirect();
          return UscBillResult(
            ok: false,
            usc: usc,
            stateId: stateId,
            discomName: 'TGSPDCL',
            verificationStep: 'captcha_required',
            captchaChallenge: fresh,
            message: (tokenRaw?['message'] ?? 'Incorrect TGSPDCL security code. Please enter the new code below.').toString(),
          );
        }
        lookupToken = tokenRaw!['token'].toString();
      } catch (_) {
        final fresh = await _fetchTgspdclCaptchaDirect();
        return UscBillResult(
          ok: false,
          usc: usc,
          stateId: stateId,
          discomName: 'TGSPDCL',
          verificationStep: 'captcha_required',
          captchaChallenge: fresh,
          message: 'TGSPDCL security check timed out. Please enter the new code below.',
        );
      }
    }

    final hdrs = <String, String>{
      ..._browserHeaders,
      'X-API-Key': _tgspdclPublicKey,
      'Referer': 'https://tgsouthernpower.org/',
      if (lookupToken.isNotEmpty) 'X-Lookup-Token': lookupToken,
    };

    final encodedUsc = Uri.encodeComponent(usc);
    final results = await Future.wait<http.Response?>([
      _safeGet(Uri.parse('https://tgsouthernpower.org/api/public/bill/download/$encodedUsc'), hdrs),
      _safeGet(Uri.parse('https://tgsouthernpower.org/api/public/bill/history?uscno=$encodedUsc'), hdrs),
    ]);
    final dlResp = results[0];
    final histResp = results[1];

    // Parse 12-month history array
    final history = <UscMonthEntry>[];
    if (histResp != null && histResp.statusCode == 200) {
      try {
        final rawHist = jsonDecode(histResp.body);
        if (rawHist is List) {
          for (final item in rawHist.whereType<Map>()) {
            final m = item.cast<String, dynamic>();
            final month = (m['BILLMONTH'] ?? m['billmonth'] ?? m['MONTH'] ?? m['month'] ?? '').toString().trim();
            final u = _toDouble(m['UNITS'] ?? m['units'] ?? m['BILLEDUNITS'] ?? m['BILLED_UNITS'] ?? m['KWH']);
            final amt = _toDouble(m['DEMAND'] ?? m['demand'] ?? m['CURDEMAND'] ?? m['BILLAMT'] ?? m['TOTAMT'] ?? m['NETAMT']);
            if (u > 0 || amt > 0) {
              history.add(UscMonthEntry(month: month.isNotEmpty ? month : 'Bill', units: u, amount: amt, verified: true));
            }
          }
        }
      } catch (_) {}
    }

    // Parse current bill download payload
    if (dlResp != null && dlResp.statusCode == 200) {
      final dlRaw = _tryJsonMap(dlResp.body);
      final dlData = (dlRaw?['data'] is Map) ? (dlRaw!['data'] as Map).cast<String, dynamic>() : dlRaw;
      if (dlData != null) {
        final dlUnits = _toDouble(dlData['BLDUNITS'] ?? dlData['UNITS'] ?? dlData['BILLEDUNITS']);
        final dlBill = _toDouble(dlData['BILLAMT'] ?? dlData['NETAMT'] ?? dlData['CURDEMAND'] ?? dlData['TOTALAMOUNT']);
        final cname = _str(dlData['CTNAME'] ?? dlData['CUSTOMERNAME']);
        final addr = _str(dlData['ADDRESS'] ?? dlData['CUSTOMERADD']);
        final billDate = _str(dlData['BLDT'] ?? dlData['CTPRESENTDT']);
        final loadKw = _optDouble(dlData['CTLOAD']);
        final phaseNum = _toDouble(dlData['CTMTRPHASE']).round();
        final phase = phaseNum == 3 ? 'three_phase' : (phaseNum == 1 ? 'single_phase' : '');

        if (dlUnits > 0 || dlBill > 0 || cname.isNotEmpty) {
          if ((dlUnits > 0 || dlBill > 0) &&
              !history.any((e) => e.month.toLowerCase() == billDate.toLowerCase() && billDate.isNotEmpty)) {
            history.add(UscMonthEntry(
              month: billDate.isNotEmpty ? billDate : 'Latest',
              units: dlUnits,
              amount: dlBill,
              verified: true,
            ));
          }
          final avgUnits = _averageUnits(history, dlUnits);
          final avgBill = _averageBills(history, dlBill);
          return UscBillResult(
            ok: avgUnits > 0 || avgBill > 0,
            usc: _str(dlData['CTUKSCNO'] ?? dlData['UKSCNO']).isNotEmpty ? _str(dlData['CTUKSCNO'] ?? dlData['UKSCNO']) : usc,
            stateId: stateId,
            discomName: 'TGSPDCL',
            consumerName: cname,
            address: addr,
            avgMonthlyUnits: avgUnits,
            avgMonthlyBill: avgBill,
            contractedLoadKw: (loadKw != null && loadKw > 0) ? loadKw : null,
            phaseType: phase,
            billDate: billDate,
            ebillUrl: 'https://webportal.tgsouthernpower.org/ConsumerInfo/',
            history: history,
            verificationStep: 'none',
            sourceLabel: 'TGSPDCL Direct API',
            message: 'Fetched ${history.length} verified months directly from TGSPDCL.',
          );
        }
      }
    }

    // Check /api/public/bill to see if CAPTCHA (HTTP 428) is required
    try {
      final billResp = await http
          .get(Uri.parse('https://tgsouthernpower.org/api/public/bill?uscno=$encodedUsc'), headers: hdrs)
          .timeout(const Duration(seconds: 10));

      if (billResp.statusCode == 428) {
        final fresh = await _fetchTgspdclCaptchaDirect();
        if (history.isNotEmpty) {
          final avgU = _averageUnits(history, 0);
          final avgB = _averageBills(history, 0);
          return UscBillResult(
            ok: avgU > 0 || avgB > 0,
            usc: usc,
            stateId: stateId,
            discomName: 'TGSPDCL',
            avgMonthlyUnits: avgU,
            avgMonthlyBill: avgB,
            ebillUrl: 'https://webportal.tgsouthernpower.org/ConsumerInfo/',
            history: history,
            verificationStep: 'none',
            captchaChallenge: fresh,
            sourceLabel: 'TGSPDCL History API',
            message: 'Fetched ${history.length} billing months directly from TGSPDCL.',
          );
        }
        return UscBillResult(
          ok: false,
          usc: usc,
          stateId: stateId,
          discomName: 'TGSPDCL',
          verificationStep: 'captcha_required',
          captchaChallenge: fresh,
          message: 'TGSPDCL requires solving the security code below to fetch your live bill.',
        );
      }

      final billRaw = _tryJsonMap(billResp.body);
      final bData = (billRaw?['data'] is Map) ? (billRaw!['data'] as Map).cast<String, dynamic>() : billRaw;
      if (billResp.statusCode == 200 && bData != null) {
        final u = _toDouble(bData['UNITS'] ?? bData['BILLEDUNITS'] ?? bData['KWH'] ?? bData['units']);
        final amt = _toDouble(bData['BILLAMT'] ?? bData['CURDEMAND'] ?? bData['DEMAND'] ?? bData['TOTAMT'] ?? bData['NETAMT']);
        if (u > 0 || amt > 0 || history.isNotEmpty) {
          final avgU = _averageUnits(history, u);
          final avgB = _averageBills(history, amt);
          return UscBillResult(
            ok: avgU > 0 || avgB > 0,
            usc: _str(bData['UKSCNO']).isNotEmpty ? _str(bData['UKSCNO']) : usc,
            stateId: stateId,
            discomName: 'TGSPDCL',
            consumerName: _str(bData['CUSTOMERNAME']),
            address: _str(bData['CUSTOMERADD']),
            avgMonthlyUnits: avgU,
            avgMonthlyBill: avgB,
            contractedLoadKw: _optDouble(bData['LOAD'] ?? bData['CTLOAD']),
            billDate: _str(bData['BILLDATE']),
            ebillUrl: 'https://webportal.tgsouthernpower.org/ConsumerInfo/',
            history: history,
            verificationStep: 'none',
            sourceLabel: 'TGSPDCL Direct API',
          );
        }
      }
      if (billResp.statusCode == 404 || (billRaw?['success'] == false)) {
        return UscBillResult(
          ok: false,
          usc: usc,
          stateId: stateId,
          discomName: 'TGSPDCL',
          verificationStep: 'not_found',
          error: (billRaw?['message'] ?? 'No TGSPDCL consumer found for USC "$usc".').toString(),
        );
      }
    } catch (_) {
      // Fall through to official TGSPDCL Easebuzz pay gateway
    }

    // Fallback: Official TGSPDCL Pay Gateway (Easebuzz)
    try {
      final ebResp = await http
          .post(
            Uri.parse('https://layer.easebuzz.in/tgspdcl/api/v1/fetchbilldetails/'),
            headers: {
              ..._browserHeaders,
              'Content-Type': 'application/json',
              'Origin': 'https://vas.easebuzz.in',
              'Referer': 'https://vas.easebuzz.in/TGSPDCL/Billpay',
            },
            body: jsonEncode({'service_number': usc, 'service_type': 'N'}),
          )
          .timeout(const Duration(seconds: 10));
      final eb = _tryJsonMap(ebResp.body);
      if (ebResp.statusCode == 200 && eb != null) {
        if (eb['success'] == true && eb['data'] is Map) {
          final d = (eb['data'] as Map).cast<String, dynamic>();
          final amt = _toDouble(d['totalAmount'] ?? d['amountPayable']);
          final estU = amt > 0 ? _estimateTelanganaUnits(amt) : 0.0;
          final bDate = _str(d['billDate']);
          return UscBillResult(
            ok: estU > 0 || amt > 0,
            usc: usc,
            stateId: stateId,
            discomName: 'TGSPDCL',
            consumerName: _str(d['customerName']),
            avgMonthlyUnits: estU,
            avgMonthlyBill: amt,
            billDate: bDate,
            ebillUrl: 'https://vas.easebuzz.in/TGSPDCL/Billpay',
            history: (estU > 0 || amt > 0)
                ? [UscMonthEntry(month: bDate.isNotEmpty ? bDate : 'Latest', units: estU, amount: amt, verified: true)]
                : const [],
            verificationStep: 'none',
            sourceLabel: 'TGSPDCL Pay Gateway',
          );
        }
        return UscBillResult(
          ok: false,
          usc: usc,
          stateId: stateId,
          discomName: 'TGSPDCL',
          verificationStep: 'not_found',
          error: (eb['message'] ?? 'No TGSPDCL consumer found for USC "$usc".').toString(),
        );
      }
    } catch (_) {}

    return UscBillResult(
      ok: false,
      usc: usc,
      stateId: stateId,
      discomName: 'TGSPDCL',
      verificationStep: 'portal_manual_or_paste',
      error: 'Could not reach TGSPDCL portal right now. Check your internet connection or tap Open TGSPDCL Portal.',
    );
  }

  static Future<UscBillResult> _fetchTgnpdclDirect({
    required String usc,
    required String stateId,
  }) async {
    final clean = usc.replaceAll(RegExp(r'[\s\-_/.]'), '').trim();
    try {
      final resp = await http
          .post(
            Uri.parse('https://layer.easebuzz.in/tgnpdcl/api/v1/fetchbilldetails/'),
            headers: {
              ..._browserHeaders,
              'Content-Type': 'application/json',
              'Origin': 'https://vas.easebuzz.in',
              'Referer': 'https://vas.easebuzz.in/TGNPDCL/Billpay',
            },
            body: jsonEncode({'service_number': clean}),
          )
          .timeout(const Duration(seconds: 12));
      final j = _tryJsonMap(resp.body);
      if (resp.statusCode == 200 && j != null) {
        if (j['success'] == false) {
          final hint = clean.length != 8
              ? 'TGNPDCL requires an 8-digit USCNO ("$clean" has ${clean.length} characters; 9-digit Telangana USCs belong to TGSPDCL).'
              : 'No active consumer found on TGNPDCL for USCNO "$clean".';
          return UscBillResult(
            ok: false,
            usc: clean,
            stateId: stateId,
            discomName: 'TGNPDCL',
            verificationStep: 'not_found',
            error: hint,
          );
        }
        if (j['success'] == true && j['data'] is Map) {
          final d = (j['data'] as Map).cast<String, dynamic>();
          final demand = _toDouble(d['currentMonthDemand']);
          final totalAmt = _toDouble(d['billTotalAmount']);
          final billAmt = demand > 0 ? demand : totalAmt;
          final estUnits = billAmt > 0 ? _estimateTelanganaUnits(billAmt) : 0.0;
          final billDate = _str(d['billDate']);
          final addrParts = [_str(d['area']), _str(d['secname']), _str(d['circleCode'])]
              .where((e) => e.isNotEmpty)
              .join(', ');
          return UscBillResult(
            ok: estUnits > 0 || billAmt > 0,
            usc: _str(d['uscno']).isNotEmpty ? _str(d['uscno']) : clean,
            stateId: stateId,
            discomName: 'TGNPDCL',
            consumerName: _str(d['name']),
            address: addrParts,
            avgMonthlyUnits: estUnits,
            avgMonthlyBill: billAmt,
            billDate: billDate,
            ebillUrl: 'https://vas.easebuzz.in/TGNPDCL/Billpay',
            history: (estUnits > 0 || billAmt > 0)
                ? [UscMonthEntry(month: billDate.isNotEmpty ? billDate : 'Latest', units: estUnits, amount: billAmt, verified: true)]
                : const [],
            verificationStep: 'none',
            sourceLabel: 'TGNPDCL Pay Gateway',
          );
        }
      }
    } catch (_) {}

    return UscBillResult(
      ok: false,
      usc: clean,
      stateId: stateId,
      discomName: 'TGNPDCL',
      verificationStep: 'portal_manual_or_paste',
      error: 'Could not reach TGNPDCL portal right now. Tap Open TGNPDCL Portal or Paste Bills below.',
    );
  }

  static Future<UscBillResult> _fetchApepdclDirect({
    required String usc,
    required String stateId,
  }) async {
    try {
      final pageResp = await http
          .get(Uri.parse('https://www.apeasternpower.com/viewBillDetailsMain'), headers: _browserHeaders)
          .timeout(const Duration(seconds: 10));
      final cookie = _extractCookieHeader(pageResp.headers['set-cookie']);
      final commonHdrs = <String, String>{
        ..._browserHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
        if (cookie.isNotEmpty) 'Cookie': cookie,
        'Referer': 'https://www.apeasternpower.com/viewBillDetailsMain',
      };

      final chatResp = await http
          .post(
            Uri.parse('https://www.apeasternpower.com/getChatboxBill'),
            headers: commonHdrs,
            body: 'ltscno=${Uri.encodeQueryComponent(usc)}',
          )
          .timeout(const Duration(seconds: 10));

      final chat = _tryJsonMap(chatResp.body);
      final billAmt = _toDouble(chat?['TOT_BILL_AMT'] ?? chat?['BILL_AMT']);
      final units = _toDouble(chat?['BILLED_UNITS'] ?? chat?['UNITS']);
      final billDate = _str(chat?['BILL_DATE']);

      if (units > 0 || billAmt > 0) {
        return UscBillResult(
          ok: true,
          usc: usc,
          stateId: stateId,
          discomName: 'APEPDCL',
          avgMonthlyUnits: units,
          avgMonthlyBill: billAmt,
          billDate: billDate,
          ebillUrl: 'https://www.apeasternpower.com/viewBillDetailsMain',
          history: [UscMonthEntry(month: billDate.isNotEmpty ? billDate : 'Latest', units: units, amount: billAmt, verified: true)],
          verificationStep: 'none',
          sourceLabel: 'APEPDCL Direct Portal',
        );
      }

      return UscBillResult(
        ok: false,
        usc: usc,
        stateId: stateId,
        discomName: 'APEPDCL',
        verificationStep: 'not_found',
        error: 'No consumer bill found on APEPDCL for Service Number "$usc".',
      );
    } catch (_) {
      return UscBillResult(
        ok: false,
        usc: usc,
        stateId: stateId,
        discomName: 'APEPDCL',
        verificationStep: 'portal_manual_or_paste',
        error: 'APEPDCL portal timed out. Tap Open APEPDCL Portal or Paste Bills below.',
      );
    }
  }

  static Future<UscBillResult> _fetchApspdclDirect({
    required String usc,
    required String stateId,
    String? mobileNumber,
  }) async {
    try {
      final formResp = await http
          .get(Uri.parse('https://www.apspdcl.in/ConsumerDashboard/serviceDetails.jsp'), headers: _browserHeaders)
          .timeout(const Duration(seconds: 10));
      final cookie = _extractCookieHeader(formResp.headers['set-cookie']);
      final csrf = RegExp(r'name="X-CSRF-TOKEN"[^>]*value="([^"]+)"', caseSensitive: false)
              .firstMatch(formResp.body)
              ?.group(1) ??
          '';

      final cleanMob = (mobileNumber ?? '').replaceAll(RegExp(r'\D'), '');
      final body = <String, String>{
        'X-CSRF-TOKEN': csrf,
        'option': 'uscno',
        'uscno': usc,
        if (cleanMob.length == 10) 'mobile': cleanMob,
        'ans': '10',
      };

      final postResp = await http
          .post(
            Uri.parse('https://www.apspdcl.in/ConsumerDashboard/public/consumerdetail'),
            headers: {
              ..._browserHeaders,
              'Content-Type': 'application/x-www-form-urlencoded',
              if (cookie.isNotEmpty) 'Cookie': cookie,
              'Referer': 'https://www.apspdcl.in/ConsumerDashboard/serviceDetails.jsp',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 12));

      final plain = postResp.body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
      if (!RegExp(r'Invalid Details', caseSensitive: false).hasMatch(plain) && !postResp.body.contains('id="uscsec"')) {
        final uMatch = RegExp(r'(?:Billed\s*Units|Consumption\s*Units|Units\s*Consumed|Total\s*Units|Units)\s*[:\-]?\s*([\d,]+)', caseSensitive: false)
            .firstMatch(plain);
        final bMatch = RegExp(r'(?:Total\s*Bill\s*Amount|Net\s*Payable|Bill\s*Amount|Amount\s*Payable)\s*[:\-]?\s*(?:Rs\.?|₹|INR)?\s*([\d,]+(?:\.\d+)?)', caseSensitive: false)
            .firstMatch(plain);
        final nameMatch = RegExp(r'(?:Consumer\s*Name|Customer\s*Name)\s*[:\-]?\s*([A-Za-z][A-Za-z\s.]{2,40})', caseSensitive: false)
            .firstMatch(plain);

        final u = uMatch != null ? _toDouble(uMatch.group(1)) : 0.0;
        final b = bMatch != null ? _toDouble(bMatch.group(1)) : 0.0;
        if (u > 0 || b > 0) {
          return UscBillResult(
            ok: true,
            usc: usc,
            stateId: stateId,
            discomName: 'APSPDCL',
            consumerName: nameMatch?.group(1)?.trim() ?? '',
            avgMonthlyUnits: u,
            avgMonthlyBill: b,
            ebillUrl: 'https://www.apspdcl.in/ConsumerDashboard/serviceDetails.jsp',
            history: [UscMonthEntry(month: 'Latest', units: u, amount: b, verified: true)],
            verificationStep: 'none',
            sourceLabel: 'APSPDCL Direct Portal',
          );
        }
      }

      if (cleanMob.length != 10) {
        return UscBillResult(
          ok: false,
          usc: usc,
          stateId: stateId,
          discomName: 'APSPDCL',
          verificationStep: 'mobile_required',
          message: 'APSPDCL may require the 10-digit mobile number linked to USC "$usc". Enter it below and tap Submit.',
        );
      }

      return UscBillResult(
        ok: false,
        usc: usc,
        stateId: stateId,
        discomName: 'APSPDCL',
        verificationStep: 'not_found',
        error: 'APSPDCL returned no active bill for USC "$usc". Verify your 8-digit USC number and linked mobile.',
      );
    } catch (_) {
      return UscBillResult(
        ok: false,
        usc: usc,
        stateId: stateId,
        discomName: 'APSPDCL',
        verificationStep: 'portal_manual_or_paste',
        error: 'APSPDCL portal timed out. Tap Open APSPDCL Portal or Paste Bills below.',
      );
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
      return (ok: false, rate: null, label: null, error: 'Using built-in official slab table');
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
      final rate = _optDouble(j['effectiveUnitRate'] ?? j['unitRate'] ?? j['tariff'] ?? j['rate']);
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
    if (base.isNotEmpty) {
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
            .timeout(const Duration(seconds: 25));

        final j = _tryJsonMap(resp.body);
        if (resp.statusCode == 200 && j != null && j['ok'] != false) {
          final dataMap = (j['telemetry'] is Map)
              ? (j['telemetry'] as Map).cast<String, dynamic>()
              : (j['data'] is Map ? (j['data'] as Map).cast<String, dynamic>() : j);
          return (
            ok: true,
            snapshot: _parseSnapshot({...j, ...dataMap}, config.brand, config.authMode),
            error: null,
          );
        }
        // If backend returned an explicit credential/validation error (4xx), surface it;
        // otherwise fall through to direct native manufacturer sync.
        if (resp.statusCode >= 400 && resp.statusCode < 500 && j != null) {
          final msg = _str(j['error'] ?? j['message']);
          if (msg.isNotEmpty) {
            return (ok: false, snapshot: null, error: msg);
          }
        }
      } catch (_) {
        // Backend unreachable — fall back to direct native manufacturer sync below.
      }
    }

    return _syncInverterDirect(
      config: config,
      password: password,
      apiSecret: apiSecret,
    );
  }

  // -------------------- Internal parsing helpers --------------------

  static Map<String, dynamic>? _tryJsonMap(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  static String _str(dynamic v) => v == null ? '' : v.toString().trim();

  static double _toDouble(dynamic v) {
    if (v is num) return v.isFinite ? v.toDouble() : 0;
    if (v is String) {
      final p = double.tryParse(v.replaceAll(',', '').trim());
      return (p != null && p.isFinite) ? p : 0;
    }
    return 0;
  }

  static double? _optDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      final p = double.tryParse(v.replaceAll(',', '').trim());
      return (p != null && p.isFinite) ? p : null;
    }
    return null;
  }

  static double _averageUnits(List<UscMonthEntry> list, double fallback) {
    final withU = list.where((e) => e.units > 0).toList();
    if (withU.isNotEmpty) {
      return withU.fold(0.0, (a, e) => a + e.units) / withU.length;
    }
    return fallback;
  }

  static double _averageBills(List<UscMonthEntry> list, double fallback) {
    final withB = list.where((e) => e.amount > 0).toList();
    if (withB.isNotEmpty) {
      return withB.fold(0.0, (a, e) => a + e.amount) / withB.length;
    }
    return fallback;
  }

  static String _extractCookieHeader(String? rawSetCookie) {
    if (rawSetCookie == null || rawSetCookie.isEmpty) return '';
    final cookies = <String>[];
    for (final m in RegExp(r'([A-Za-z0-9_\-]+)=([^;,\s]+)').allMatches(rawSetCookie)) {
      final k = m.group(1) ?? '';
      final low = k.toLowerCase();
      if (low == 'path' || low == 'domain' || low == 'expires' || low == 'max-age' || low == 'samesite') continue;
      cookies.add('$k=${m.group(2)}');
    }
    return cookies.join('; ');
  }

  static Future<http.Response?> _safeGet(Uri uri, Map<String, String> headers) async {
    try {
      return await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }
  }

  /// Approximates Telangana TGERC domestic monthly units from a live demand ₹ amount
  /// when a payment gateway only returns rupee demand.
  static double _estimateTelanganaUnits(double billInr) {
    if (billInr <= 120) return (billInr / 2.6).clamp(10.0, 50.0).toDouble();
    if (billInr <= 800) return (billInr / 4.8).roundToDouble();
    if (billInr <= 2500) return (billInr / 7.2).roundToDouble();
    return (billInr / 8.8).roundToDouble();
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

  // -------------------- Direct Native Manufacturer Inverter Sync --------------------

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static String? _solisWebPrefix;
  static String? _solisWebKey;
  static String _solisWebVersion = '5.3.121';
  static int _solisWebFetchedAtMs = 0;

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncInverterDirect({
    required InverterConfig config,
    required String password,
    required String apiSecret,
  }) async {
    final brand = config.brand.trim().toLowerCase();
    try {
      switch (brand) {
        case 'soliscloud':
        case 'solis':
          return await _syncSolisCloudDirect(config, password, apiSecret);
        case 'goodwe':
          return await _syncGoodWeDirect(config, password);
        case 'growatt':
          return await _syncGrowattDirect(config, password);
        case 'solarman':
        case 'deye':
          return await _syncSolarmanDirect(config, password, apiSecret);
        case 'sungrow':
          return await _syncSungrowDirect(config, password);
        case 'polygun':
        case 'polycab':
          return await _syncPolygunDirect(config, password, apiSecret);
        case 'pure':
        case 'purepower':
          return await _syncPureDirect(config, password, apiSecret);
        case 'hitachi':
          return await _syncHitachiDirect(config, password, apiSecret);
        default:
          return (
            ok: false,
            snapshot: null,
            error:
                'Unsupported inverter brand "$brand". Select SolisCloud, Solarman, Growatt, Sungrow, GoodWe, Polygun/Polycab, PURE, or Hitachi.',
          );
      }
    } catch (e) {
      return (
        ok: false,
        snapshot: null,
        error: 'Direct inverter sync failed: $e',
      );
    }
  }

  // ---- Shared inverter telemetry helpers ----

  static Map<String, dynamic>? _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : null;

  static List<Map<String, dynamic>> _asListOfMaps(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static String _pickStr(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return '';
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  static double? _pickNum(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      final v = _optDouble(m[k]);
      if (v != null) return v;
    }
    return null;
  }

  static double? _toKwSmart(double? val, String unitHint) {
    if (val == null) return null;
    final u = unitHint.trim().toLowerCase();
    if (u == 'mw' || u == 'mwp') return val * 1000.0;
    if (u == 'kw' || u == 'kwp') return val;
    if (u == 'w' || u == 'wp') return val / 1000.0;
    return val > 200.0 ? val / 1000.0 : val;
  }

  static String _normSerial(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  static bool _serialsMatch(String a, String b) {
    final na = _normSerial(a);
    final nb = _normSerial(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  static String _sanitizeDateKey(String raw) {
    final s = raw.trim();
    final m = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(s);
    if (m != null) {
      final y = m.group(1)!;
      final mo = m.group(2)!.padLeft(2, '0');
      final d = m.group(3)!.padLeft(2, '0');
      return '$y-$mo-$d';
    }
    return '';
  }

  static double _round2(double v) => (v * 100.0).roundToDouble() / 100.0;

  static String _istYearMonth() {
    final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  static String _mergeCookies(String existing, String? rawSetCookie) {
    final jar = <String, String>{};
    if (existing.isNotEmpty) {
      for (final part in existing.split(';')) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          final k = part.substring(0, idx).trim();
          final v = part.substring(idx + 1).trim();
          if (k.isNotEmpty && v.isNotEmpty) jar[k] = v;
        }
      }
    }
    if (rawSetCookie != null && rawSetCookie.isNotEmpty) {
      const attrs = {
        'path',
        'domain',
        'expires',
        'max-age',
        'samesite',
        'secure',
        'httponly',
        'priority',
      };
      for (final m in RegExp(r'([A-Za-z0-9_\-\.]+)=([^;,\r\n]+)').allMatches(rawSetCookie)) {
        final k = (m.group(1) ?? '').trim();
        final v = (m.group(2) ?? '').trim();
        if (k.isEmpty || v.isEmpty || attrs.contains(k.toLowerCase())) continue;
        jar[k] = v;
      }
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static String _cookieValue(String cookieJar, List<String> names) {
    if (cookieJar.isEmpty) return '';
    final lower = names.map((e) => e.toLowerCase()).toSet();
    for (final part in cookieJar.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final k = part.substring(0, idx).trim();
      final v = part.substring(idx + 1).trim();
      if (v.isNotEmpty && lower.contains(k.toLowerCase())) return v;
    }
    return '';
  }

  // ==================== 1. SOLISCLOUD (Website Login + Official API) ====================

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncSolisCloudDirect(
    InverterConfig config,
    String password,
    String apiSecret,
  ) async {
    final isApi = config.authMode == 'api';
    final keyId = (config.apiKey.trim().isNotEmpty ? config.apiKey.trim() : config.username.trim());
    final keySec = (apiSecret.trim().isNotEmpty ? apiSecret.trim() : password.trim());
    final looksKeyId = RegExp(r'^\d{15,24}$').hasMatch(keyId);
    final useOfficialApi = (isApi && keyId.isNotEmpty && keySec.isNotEmpty) ||
        (looksKeyId && keySec.length >= 16);

    if (isApi && !useOfficialApi) {
      return (
        ok: false,
        snapshot: null,
        error: 'Enter your SolisCloud API KeyID and KeySecret, or switch to Manufacturer Website Login.',
      );
    }

    if (useOfficialApi) {
      return _syncSolisCloudApiDirect(config, keyId, keySec);
    }
    return _syncSolisCloudWebDirect(config, password);
  }

  static Future<({String prefix, String webKey, String version})> _getSolisWebConfig({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh &&
        _solisWebPrefix != null &&
        _solisWebKey != null &&
        (now - _solisWebFetchedAtMs) < 12 * 60 * 60 * 1000) {
      return (prefix: _solisWebPrefix!, webKey: _solisWebKey!, version: _solisWebVersion);
    }

    final loginResp = await http
        .get(
          Uri.parse('https://www.soliscloud.com/login'),
          headers: const {
            'User-Agent': _ua,
            'Accept': 'text/html,application/xhtml+xml,*/*',
          },
        )
        .timeout(const Duration(seconds: 15));

    final jsMatch = RegExp(r'''https://ui-cdn\.soliscloud\.com[^"'<>]*?/index-[A-Za-z0-9_\-]+\.js''')
        .firstMatch(loginResp.body);
    if (jsMatch == null || jsMatch.group(0) == null) {
      throw Exception('Could not load SolisCloud web portal bundle.');
    }

    final bundleResp = await http
        .get(
          Uri.parse(jsMatch.group(0)!),
          headers: const {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 18));
    final bundleTxt = bundleResp.body;

    final prefixMatch = RegExp(r'"(WEB \d+:)"\+').firstMatch(bundleTxt);
    if (prefixMatch == null || prefixMatch.group(1) == null) {
      throw Exception('Could not initialize SolisCloud web portal handshake.');
    }
    final prefix = prefixMatch.group(1)!;
    final kyIdx = prefixMatch.start;
    final start = kyIdx > 6000 ? kyIdx - 6000 : 0;
    final end = (kyIdx + 120) < bundleTxt.length ? kyIdx + 120 : bundleTxt.length;
    final keyWindow = bundleTxt.substring(start, end);

    final arrMatches = RegExp(r'=\[("[A-Za-z0-9+/=]{16,}"(?:,"[A-Za-z0-9+/=]{16,}")+)\]').allMatches(keyWindow).toList();
    String webKey = '';
    for (var i = arrMatches.length - 1; i >= 0; i--) {
      final inner = arrMatches[i].group(1);
      if (inner == null) continue;
      try {
        final chunks = (jsonDecode('[$inner]') as List).map((e) => e.toString()).toList();
        final decoded = chunks.map((c) => utf8.decode(base64Decode(c))).join();
        if (RegExp(r'^[0-9a-fA-F]{24,64}$').hasMatch(decoded)) {
          webKey = decoded;
          break;
        }
      } catch (_) {
        // Try next candidate
      }
    }
    if (webKey.isEmpty) {
      throw Exception('Invalid SolisCloud web portal handshake parameters.');
    }

    final verMatch = RegExp(r'Version:"([0-9.]+)"').firstMatch(bundleTxt);
    final version = verMatch?.group(1) ?? '5.3.121';

    _solisWebPrefix = prefix;
    _solisWebKey = webKey;
    _solisWebVersion = version;
    _solisWebFetchedAtMs = now;
    return (prefix: prefix, webKey: webKey, version: version);
  }

  static Future<({bool ok, int status, Map<String, dynamic>? json})> _solisWebPost({
    required Map<String, String> sessionState,
    required ({String prefix, String webKey, String version}) webCfg,
    required String apiPath,
    required Map<String, dynamic> bodyObj,
  }) async {
    final clean = <String, dynamic>{};
    bodyObj.forEach((k, v) {
      if (v != null && v != '') clean[k] = v;
    });
    clean['localTime'] = DateTime.now().millisecondsSinceEpoch;
    clean['localTimeZone'] = 5.5;
    clean['language'] = '2';

    final bodyStr = jsonEncode(clean);
    final contentMd5 = _md5Base64(bodyStr);
    final gmtDate = _rfc1123Utc(DateTime.now().toUtc());
    final canonical = 'POST\n$contentMd5\napplication/json\n$gmtDate\n$apiPath';
    final sig = _hmacSha1Base64(webCfg.webKey, canonical);

    final headers = <String, String>{
      'User-Agent': _ua,
      'Content-Type': 'application/json;charset=UTF-8',
      'Content-MD5': contentMd5,
      'Authorization': '${webCfg.prefix}$sig',
      'Time': gmtDate,
      'X-Cloud-Platform': 'GLY',
      'language': '2',
      'Device-Id': sessionState['deviceId'] ?? '',
      'Version': webCfg.version,
      'platform': 'Web',
      'Origin': 'https://www.soliscloud.com',
      'Referer': 'https://www.soliscloud.com/overview/plantStation',
    };
    final cookie = sessionState['cookie'] ?? '';
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    final token = sessionState['token'] ?? '';
    if (token.isNotEmpty) headers['token'] = token;

    final resp = await http
        .post(
          Uri.parse('https://www.soliscloud.com/api$apiPath'),
          headers: headers,
          body: bodyStr,
        )
        .timeout(const Duration(seconds: 20));

    final hdrTok = (resp.headers['token'] ??
            resp.headers['csrftoken'] ??
            resp.headers['x-token'] ??
            '')
        .trim();
    if (hdrTok.isNotEmpty && (sessionState['token'] ?? '').isEmpty) {
      sessionState['token'] = hdrTok;
    }

    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      sessionState['cookie'] = _mergeCookies(sessionState['cookie'] ?? '', setCookie);
      if ((sessionState['token'] ?? '').isEmpty) {
        final ckTok = _cookieValue(sessionState['cookie'] ?? '', ['token', 'csrfToken', 'X-Token']);
        if (ckTok.isNotEmpty) sessionState['token'] = ckTok;
      }
    }

    return (
      ok: resp.statusCode >= 200 && resp.statusCode < 300,
      status: resp.statusCode,
      json: _tryJsonMap(resp.body),
    );
  }

  static Future<({bool ok, int status, Map<String, dynamic>? json})> _safeSolisWebPost({
    required Map<String, String> sessionState,
    required ({String prefix, String webKey, String version}) webCfg,
    required String apiPath,
    required Map<String, dynamic> bodyObj,
  }) async {
    try {
      return await _solisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: apiPath,
        bodyObj: bodyObj,
      );
    } catch (_) {
      return (ok: false, status: 0, json: null);
    }
  }

  static List<Map<String, dynamic>> _extractSolisRecords(dynamic payload) {
    if (payload == null) return const [];
    if (payload is List) return _asListOfMaps(payload);
    final root = _asMap(payload);
    if (root == null) return const [];
    for (final k in const ['records', 'list']) {
      if (root[k] is List) return _asListOfMaps(root[k]);
    }
    for (final container in const ['page', 'inverterPage', 'stationPage']) {
      final sub = _asMap(root[container]);
      if (sub != null) {
        if (sub['records'] is List) return _asListOfMaps(sub['records']);
        if (sub['list'] is List) return _asListOfMaps(sub['list']);
      }
    }
    return const [];
  }

  static InverterSnapshot _buildSolisSnapshot({
    required Map<String, dynamic> data,
    required String authMode,
    required String matchedInvSn,
    required String matchedLogSn,
    required String stationId,
    required bool? loggerOnline,
    required int? loggerSignalPct,
    required List<InverterDailyLog> dailyLogs,
  }) {
    final pacRaw = _pickNum(data, ['pac', 'power', 'currentPower']) ?? 0.0;
    final pacUnit = _pickStr(data, ['pacStr', 'powerStr']);
    final liveKw = (_toKwSmart(pacRaw, pacUnit.isEmpty ? 'kw' : pacUnit) ?? 0.0);
    final todayKwh = _pickNum(data, ['eToday', 'dayEnergy', 'dayEnergy1']) ?? 0.0;
    final monthKwh = _pickNum(data, ['eMonth', 'monthEnergy', 'monthEnergy1']) ?? 0.0;
    final totalKwh = _pickNum(data, ['eTotal', 'allEnergy', 'allEnergy1']) ?? 0.0;

    final capRaw = _pickNum(data, ['capacity', 'power', 'dcInputPower']);
    final capUnit = _pickStr(data, ['capacityStr', 'powerStr']);
    final ratedKw = capRaw != null
        ? (_toKwSmart(capRaw, capUnit.isNotEmpty ? capUnit : (capRaw > 500 ? 'w' : 'kw')) ?? 0.0)
        : 0.0;

    final stateNum = _pickNum(data, ['state', 'inverterState'])?.round();
    final plantStatus = stateNum == 1
        ? 'online'
        : stateNum == 2
            ? 'offline'
            : stateNum == 3
                ? 'fault'
                : stateNum == 4
                    ? 'standby'
                    : (liveKw > 0 ? 'online' : 'offline');

    final loggerStatus = loggerOnline == true
        ? 'online'
        : loggerOnline == false
            ? 'offline'
            : (plantStatus == 'online' ? 'online' : 'unknown');

    final statusTag = (plantStatus == 'offline' && loggerOnline == true)
        ? 'Plant Offline (No Sun) · Logger Online'
        : (plantStatus == 'offline' ? 'Plant Offline / Standby' : 'Live');
    final sigStr = loggerSignalPct != null ? ' · Signal $loggerSignalPct%' : '';
    final idTag = matchedInvSn.isNotEmpty
        ? matchedInvSn
        : (matchedLogSn.isNotEmpty ? matchedLogSn : (stationId.isNotEmpty ? stationId : 'Synced'));

    return InverterSnapshot(
      brand: 'soliscloud',
      authMode: authMode,
      plantName: _pickStr(data, ['stationName', 'sno']).isNotEmpty
          ? _pickStr(data, ['stationName', 'sno'])
          : 'SolisCloud Plant',
      plantStatus: plantStatus,
      loggerStatus: loggerStatus,
      currentKw: _round2(liveKw < 0 ? 0.0 : liveKw),
      todayKwh: _round2(todayKwh < 0 ? 0.0 : todayKwh),
      monthKwh: _round2(monthKwh < 0 ? 0.0 : monthKwh),
      totalKwh: _round2(totalKwh < 0 ? 0.0 : totalKwh),
      ratedKw: _round2(ratedKw < 0 ? 0.0 : ratedKw),
      gridVoltageV: _pickNum(data, ['uAc1']),
      inverterTempC: _pickNum(data, ['inverterTemperature', 'temperature']),
      batterySocPct: _pickNum(data, ['batteryCapacitySoc']),
      dailyLogs: dailyLogs,
      syncedAt: DateTime.now().millisecondsSinceEpoch,
      note: 'SolisCloud $statusTag · $idTag$sigStr',
    );
  }

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncSolisCloudWebDirect(
    InverterConfig config,
    String password,
  ) async {
    final user = config.username.trim();
    final pass = password.trim();
    if (user.isEmpty || pass.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: 'Enter your SolisCloud email/username and password.',
      );
    }

    var webCfg = await _getSolisWebConfig();
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final sessionState = <String, String>{
      'deviceId': '${_md5Hex('$nowUs-solis-a')}${_md5Hex('${nowUs + 7}-solis-b')}',
      'cookie': '',
      'token': '',
    };

    final md5Pwd = _md5Hex(pass);
    var loginRes = await _solisWebPost(
      sessionState: sessionState,
      webCfg: webCfg,
      apiPath: '/user/login2',
      bodyObj: {'userInfo': user, 'passWord': md5Pwd, 'yingZhenType': 1},
    );

    if (loginRes.status == 401 || loginRes.status == 403 || loginRes.json == null) {
      webCfg = await _getSolisWebConfig(forceRefresh: true);
      loginRes = await _solisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/user/login2',
        bodyObj: {'userInfo': user, 'passWord': md5Pwd, 'yingZhenType': 1},
      );
    }

    final loginCode = _str(loginRes.json?['code']);
    if (!loginRes.ok || loginCode != '0') {
      final serverMsg = _str(loginRes.json?['msg']);
      if (loginCode == '3' || loginCode == '4' || loginCode == '5') {
        return (
          ok: false,
          snapshot: null,
          error:
              'SolisCloud requested an account verification code (${serverMsg.isEmpty ? '2-step verification' : serverMsg}). Sign in once on www.soliscloud.com to trust your account, or use API Integration.',
        );
      }
      return (
        ok: false,
        snapshot: null,
        error: serverMsg.isNotEmpty
            ? 'SolisCloud login failed: $serverMsg'
            : 'SolisCloud login failed (HTTP ${loginRes.status}). Check your www.soliscloud.com email and password.',
      );
    }

    final loginData = _asMap(loginRes.json?['data']);
    final csrfTok = _pickStr(loginRes.json, ['csrfToken', 'token']).isNotEmpty
        ? _pickStr(loginRes.json, ['csrfToken', 'token'])
        : (_pickStr(loginData, ['csrfToken', 'token', 'accessToken']).isNotEmpty
            ? _pickStr(loginData, ['csrfToken', 'token', 'accessToken'])
            : _cookieValue(sessionState['cookie'] ?? '', ['token', 'csrfToken', 'X-Token']));
    if (csrfTok.isNotEmpty) {
      sessionState['token'] = csrfTok;
    }

    final stIdParam = config.stationId.trim();
    final invSnParam = config.inverterSerial.trim();
    final logSnParam = config.loggerSerial.trim();

    final listResults = await Future.wait([
      _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/station/list',
        bodyObj: {'pageNo': 1, 'pageSize': 30, 'stationType': '0'},
      ),
      _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/inverter/listV2',
        bodyObj: {
          'pageNo': 1,
          'pageSize': 30,
          'stationType': '0',
          if (stIdParam.isNotEmpty) 'stationId': stIdParam,
        },
      ),
      _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/collector/listV2',
        bodyObj: {
          'pageNo': 1,
          'pageSize': 30,
          if (stIdParam.isNotEmpty) 'stationId': stIdParam,
        },
      ),
    ]);

    final stationRes = listResults[0];
    final invListRes = listResults[1];
    final collectorRes = listResults[2];

    var stationRecords = _extractSolisRecords(stationRes.json?['data']);
    var invRecords = _extractSolisRecords(invListRes.json?['data']);
    var collectorRecords = _extractSolisRecords(collectorRes.json?['data']);

    if (stationRecords.isEmpty) {
      final stFallback = await _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/station/list',
        bodyObj: {'pageNo': 1, 'pageSize': 30},
      );
      stationRecords = _extractSolisRecords(stFallback.json?['data']);
    }
    if (stationRecords.isEmpty) {
      final stV2 = await _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/station/listV2',
        bodyObj: {'pageNo': 1, 'pageSize': 30},
      );
      stationRecords = _extractSolisRecords(stV2.json?['data']);
    }

    if (invRecords.isEmpty && stationRecords.isNotEmpty) {
      for (final st in stationRecords.take(5)) {
        final sid = _pickStr(st, ['id', 'stationId']);
        if (sid.isEmpty) continue;
        final stInv = await _safeSolisWebPost(
          sessionState: sessionState,
          webCfg: webCfg,
          apiPath: '/inverter/listV2',
          bodyObj: {'pageNo': 1, 'pageSize': 20, 'stationId': sid},
        );
        final recs = _extractSolisRecords(stInv.json?['data']);
        if (recs.isNotEmpty) invRecords = [...invRecords, ...recs];
      }
    }

    if (invRecords.isEmpty && stationRecords.isEmpty && collectorRecords.isEmpty) {
      final apiErr = _pickStr(invListRes.json, ['msg', 'message']).isNotEmpty
          ? _pickStr(invListRes.json, ['msg', 'message'])
          : (_pickStr(stationRes.json, ['msg', 'message']).isNotEmpty
              ? _pickStr(stationRes.json, ['msg', 'message'])
              : _pickStr(collectorRes.json, ['msg', 'message']));
      return (
        ok: false,
        snapshot: null,
        error: apiErr.isNotEmpty
            ? 'Signed in to www.soliscloud.com, but SolisCloud returned: $apiErr'
            : 'Signed in to www.soliscloud.com, but no plant or inverter was found on this account.',
      );
    }

    Map<String, dynamic>? matchedInv;
    for (final rec in invRecords) {
      final sn = _pickStr(rec, ['sn', 'inverterSn']);
      final col = _pickStr(rec, ['collectorSn', 'collectorsn', 'dataloggerSn']);
      if ((invSnParam.isNotEmpty && _serialsMatch(invSnParam, sn)) ||
          (logSnParam.isNotEmpty && _serialsMatch(logSnParam, col)) ||
          (stIdParam.isNotEmpty && _pickStr(rec, ['stationId']) == stIdParam)) {
        matchedInv = rec;
        break;
      }
    }

    Map<String, dynamic>? matchedCol;
    if (logSnParam.isNotEmpty) {
      for (final c in collectorRecords) {
        if (_serialsMatch(logSnParam, _pickStr(c, ['sn', 'collectorSn']))) {
          matchedCol = c;
          break;
        }
      }
    }

    Map<String, dynamic>? matchedStation;
    final targetStId = _pickStr(matchedInv, ['stationId']).isNotEmpty
        ? _pickStr(matchedInv, ['stationId'])
        : (_pickStr(matchedCol, ['stationId']).isNotEmpty
            ? _pickStr(matchedCol, ['stationId'])
            : stIdParam);
    if (targetStId.isNotEmpty) {
      for (final st in stationRecords) {
        if (_pickStr(st, ['id', 'stationId']) == targetStId) {
          matchedStation = st;
          break;
        }
      }
    }
    matchedStation ??= stationRecords.isNotEmpty ? stationRecords.first : null;
    final chosenInv = matchedInv ?? (invRecords.isNotEmpty ? invRecords.first : null);

    var inverterData = <String, dynamic>{
      if (matchedStation != null) ...matchedStation,
      if (chosenInv != null) ...chosenInv,
    };

    final invId = _pickStr(chosenInv, ['id', 'inverterId']).isNotEmpty
        ? _pickStr(chosenInv, ['id', 'inverterId'])
        : _pickStr(matchedStation, ['inverterId']);
    var matchedInvSn = _pickStr(chosenInv, ['sn', 'inverterSn']).isNotEmpty
        ? _pickStr(chosenInv, ['sn', 'inverterSn'])
        : (_pickStr(matchedStation, ['inverterSn']).isNotEmpty
            ? _pickStr(matchedStation, ['inverterSn'])
            : invSnParam);
    var matchedLogSn = _pickStr(chosenInv, ['collectorSn', 'collectorsn', 'dataloggerSn']).isNotEmpty
        ? _pickStr(chosenInv, ['collectorSn', 'collectorsn', 'dataloggerSn'])
        : (_pickStr(matchedCol, ['sn', 'collectorSn']).isNotEmpty
            ? _pickStr(matchedCol, ['sn', 'collectorSn'])
            : logSnParam);
    var chosenStationId = _pickStr(chosenInv, ['stationId']).isNotEmpty
        ? _pickStr(chosenInv, ['stationId'])
        : (_pickStr(matchedCol, ['stationId']).isNotEmpty
            ? _pickStr(matchedCol, ['stationId'])
            : (_pickStr(matchedStation, ['id', 'stationId']).isNotEmpty
                ? _pickStr(matchedStation, ['id', 'stationId'])
                : stIdParam));

    if (invId.isNotEmpty || matchedInvSn.isNotEmpty) {
      final detRes = await _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/inverter/detail',
        bodyObj: {
          if (invId.isNotEmpty) 'id': invId,
          if (matchedInvSn.isNotEmpty) 'sn': matchedInvSn,
        },
      );
      final detData = _asMap(detRes.json?['data']);
      if (detRes.ok && _str(detRes.json?['code']) == '0' && detData != null) {
        inverterData = {...inverterData, ...detData};
        if (_pickStr(detData, ['sn', 'inverterSn']).isNotEmpty) {
          matchedInvSn = _pickStr(detData, ['sn', 'inverterSn']);
        }
        if (_pickStr(detData, ['collectorSn', 'collectorsn']).isNotEmpty) {
          matchedLogSn = _pickStr(detData, ['collectorSn', 'collectorsn']);
        }
        if (_pickStr(detData, ['stationId']).isNotEmpty) {
          chosenStationId = _pickStr(detData, ['stationId']);
        }
      }
    }

    if (chosenStationId.isNotEmpty) {
      final stDet = await _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/station/detailMix',
        bodyObj: {'id': chosenStationId, 'needCheckSingleInverter': false},
      );
      final stData = _asMap(stDet.json?['data']);
      if (stDet.ok && _str(stDet.json?['code']) == '0' && stData != null) {
        inverterData = {...stData, ...inverterData};
      }
    }

    if (collectorRecords.isEmpty && chosenStationId.isNotEmpty) {
      final colRes = await _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/collector/listV2',
        bodyObj: {'pageNo': 1, 'pageSize': 20, 'stationId': chosenStationId},
      );
      collectorRecords = _extractSolisRecords(colRes.json?['data']);
    }

    Map<String, dynamic>? colMatch = matchedCol;
    if (colMatch == null && collectorRecords.isNotEmpty) {
      for (final c in collectorRecords) {
        if (_serialsMatch(matchedLogSn.isNotEmpty ? matchedLogSn : logSnParam, _pickStr(c, ['sn']))) {
          colMatch = c;
          break;
        }
      }
      colMatch ??= collectorRecords.first;
    }

    bool? loggerOnline;
    int? loggerSignalPct;
    if (colMatch != null) {
      if (_pickStr(colMatch, ['sn', 'collectorSn']).isNotEmpty) {
        matchedLogSn = _pickStr(colMatch, ['sn', 'collectorSn']);
      }
      final rssi = _pickNum(colMatch, ['rssi', 'rssiLevel', 'signal']);
      if (rssi != null) {
        loggerSignalPct = rssi < 0
            ? ((rssi + 100.0) * 2.0).round().clamp(0, 100).toInt()
            : rssi.round().clamp(0, 100).toInt();
      }
      final cState = _pickNum(colMatch, ['state'])?.round();
      if (cState != null) loggerOnline = cState == 1;
    }

    final dailyLogs = <InverterDailyLog>[];
    if (invId.isNotEmpty || matchedInvSn.isNotEmpty) {
      final mRes = await _safeSolisWebPost(
        sessionState: sessionState,
        webCfg: webCfg,
        apiPath: '/chart/inverter/month',
        bodyObj: {
          if (invId.isNotEmpty) 'id': invId,
          if (matchedInvSn.isNotEmpty) 'sn': matchedInvSn,
          'month': _istYearMonth(),
          'money': 'INR',
        },
      );
      final rawData = mRes.json?['data'];
      final days = rawData is List
          ? _asListOfMaps(rawData)
          : _asListOfMaps(_asMap(rawData)?['list']);
      for (final row in days) {
        final dk = _sanitizeDateKey(_pickStr(row, ['dateStr', 'date', 'time']));
        final gen = _pickNum(row, ['energy', 'eToday', 'value']);
        if (dk.isNotEmpty && gen != null && gen >= 0) {
          dailyLogs.add(InverterDailyLog(date: dk, kwh: _round2(gen)));
        }
      }
    }

    return (
      ok: true,
      snapshot: _buildSolisSnapshot(
        data: inverterData,
        authMode: 'website',
        matchedInvSn: matchedInvSn,
        matchedLogSn: matchedLogSn,
        stationId: chosenStationId,
        loggerOnline: loggerOnline,
        loggerSignalPct: loggerSignalPct,
        dailyLogs: dailyLogs,
      ),
      error: null,
    );
  }

  static Future<({bool ok, int status, Map<String, dynamic>? json})> _solisApiPost({
    required String apiPath,
    required Map<String, dynamic> bodyObj,
    required String keyId,
    required String keySecret,
    String apiBase = 'https://www.soliscloud.com:13333',
  }) async {
    final reqBodyStr = jsonEncode(bodyObj);
    final contentMd5 = _md5Base64(reqBodyStr);
    final gmtDate = _rfc1123Utc(DateTime.now().toUtc());
    final canonical = 'POST\n$contentMd5\napplication/json\n$gmtDate\n$apiPath';
    final sig = _hmacSha1Base64(keySecret, canonical);

    final resp = await http
        .post(
          Uri.parse('$apiBase$apiPath'),
          headers: {
            'User-Agent': _ua,
            'Content-Type': 'application/json;charset=UTF-8',
            'Content-MD5': contentMd5,
            'Date': gmtDate,
            'Authorization': 'API $keyId:$sig',
          },
          body: reqBodyStr,
        )
        .timeout(const Duration(seconds: 20));
    return (
      ok: resp.statusCode >= 200 && resp.statusCode < 300,
      status: resp.statusCode,
      json: _tryJsonMap(resp.body),
    );
  }

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncSolisCloudApiDirect(
    InverterConfig config,
    String keyId,
    String keySecret, {
    String apiBase = 'https://www.soliscloud.com:13333',
  }) async {
    final stIdParam = config.stationId.trim();
    final invSnParam = config.inverterSerial.trim();
    final logSnParam = config.loggerSerial.trim();

    Map<String, dynamic>? inverterData;
    var matchedInvSn = invSnParam;
    var matchedLogSn = logSnParam;
    var chosenStationId = stIdParam;

    if (invSnParam.isNotEmpty) {
      final det = await _solisApiPost(
        apiPath: '/v1/api/inverterDetail',
        bodyObj: {'sn': invSnParam},
        keyId: keyId,
        keySecret: keySecret,
        apiBase: apiBase,
      );
      final detData = _asMap(det.json?['data']);
      if (det.ok && det.json?['success'] == true && detData != null) {
        inverterData = detData;
        if (_pickStr(detData, ['sn']).isNotEmpty) matchedInvSn = _pickStr(detData, ['sn']);
        if (_pickStr(detData, ['collectorSn', 'collectorsn']).isNotEmpty) {
          matchedLogSn = _pickStr(detData, ['collectorSn', 'collectorsn']);
        }
        if (_pickStr(detData, ['stationId']).isNotEmpty) {
          chosenStationId = _pickStr(detData, ['stationId']);
        }
      }
    }

    if (inverterData == null) {
      final listRes = await _solisApiPost(
        apiPath: '/v1/api/inverterDetailList',
        bodyObj: {
          'pageNo': 1,
          'pageSize': 20,
          if (stIdParam.isNotEmpty) 'stationId': stIdParam,
        },
        keyId: keyId,
        keySecret: keySecret,
        apiBase: apiBase,
      );
      if (!listRes.ok || listRes.json?['success'] == false) {
        final msg = _str(listRes.json?['msg']);
        return (
          ok: false,
          snapshot: null,
          error:
              'SolisCloud API authentication failed: ${msg.isNotEmpty ? msg : 'HTTP ${listRes.status}'}. Check your KeyID and KeySecret.',
        );
      }
      final records = _extractSolisRecords(listRes.json?['data']);
      if (records.isEmpty) {
        return (
          ok: false,
          snapshot: null,
          error: 'Signed in to SolisCloud API, but no inverters were found on this account.',
        );
      }
      Map<String, dynamic>? matched;
      for (final rec in records) {
        if ((invSnParam.isNotEmpty && _serialsMatch(invSnParam, _pickStr(rec, ['sn']))) ||
            (logSnParam.isNotEmpty && _serialsMatch(logSnParam, _pickStr(rec, ['collectorSn'])))) {
          matched = rec;
          break;
        }
      }
      inverterData = matched ?? records.first;
      if (_pickStr(inverterData, ['sn']).isNotEmpty) matchedInvSn = _pickStr(inverterData, ['sn']);
      if (_pickStr(inverterData, ['collectorSn']).isNotEmpty) {
        matchedLogSn = _pickStr(inverterData, ['collectorSn']);
      }
      if (_pickStr(inverterData, ['stationId']).isNotEmpty) {
        chosenStationId = _pickStr(inverterData, ['stationId']);
      }
    }

    bool? loggerOnline;
    int? loggerSignalPct;
    if (matchedLogSn.isNotEmpty || chosenStationId.isNotEmpty) {
      try {
        final colRes = await _solisApiPost(
          apiPath: '/v1/api/collectorList',
          bodyObj: {
            'pageNo': 1,
            'pageSize': 20,
            if (chosenStationId.isNotEmpty) 'stationId': chosenStationId,
          },
          keyId: keyId,
          keySecret: keySecret,
          apiBase: apiBase,
        );
        final cols = _extractSolisRecords(colRes.json?['data']);
        Map<String, dynamic>? col;
        for (final c in cols) {
          if (_serialsMatch(matchedLogSn, _pickStr(c, ['sn']))) {
            col = c;
            break;
          }
        }
        col ??= cols.isNotEmpty ? cols.first : null;
        if (col != null) {
          if (_pickStr(col, ['sn']).isNotEmpty) matchedLogSn = _pickStr(col, ['sn']);
          final rssi = _pickNum(col, ['rssi', 'rssiLevel']);
          if (rssi != null) {
            loggerSignalPct = rssi < 0
                ? ((rssi + 100.0) * 2.0).round().clamp(0, 100).toInt()
                : rssi.round().clamp(0, 100).toInt();
          }
          final cState = _pickNum(col, ['state'])?.round();
          if (cState != null) loggerOnline = cState == 1;
        }
      } catch (_) {
        // Optional logger diagnostics
      }
    }

    final dailyLogs = <InverterDailyLog>[];
    if (matchedInvSn.isNotEmpty) {
      try {
        final mRes = await _solisApiPost(
          apiPath: '/v1/api/inverterMonth',
          bodyObj: {'sn': matchedInvSn, 'month': _istYearMonth(), 'money': 'INR'},
          keyId: keyId,
          keySecret: keySecret,
          apiBase: apiBase,
        );
        final days = _asListOfMaps(mRes.json?['data']);
        for (final row in days) {
          final dk = _sanitizeDateKey(_pickStr(row, ['dateStr', 'date']));
          final gen = _pickNum(row, ['energy', 'eToday']);
          if (dk.isNotEmpty && gen != null && gen >= 0) {
            dailyLogs.add(InverterDailyLog(date: dk, kwh: _round2(gen)));
          }
        }
      } catch (_) {
        // Optional history
      }
    }

    return (
      ok: true,
      snapshot: _buildSolisSnapshot(
        data: inverterData,
        authMode: 'api',
        matchedInvSn: matchedInvSn,
        matchedLogSn: matchedLogSn,
        stationId: chosenStationId,
        loggerOnline: loggerOnline,
        loggerSignalPct: loggerSignalPct,
        dailyLogs: dailyLogs,
      ),
      error: null,
    );
  }

  // ==================== 2. GOODWE SEMS PORTAL ====================

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncGoodWeDirect(
    InverterConfig config,
    String password,
  ) async {
    final user = config.username.trim();
    if (user.isEmpty || password.isEmpty) {
      return (ok: false, snapshot: null, error: 'Enter your GoodWe SEMS Portal email and password.');
    }

    final initToken = base64Encode(utf8.encode(jsonEncode({
      'uid': '',
      'timestamp': 0,
      'token': '',
      'client': 'web',
      'version': '',
      'language': 'en',
    })));

    const loginUrls = [
      'https://www.semsportal.com/api/v2/Common/CrossLogin',
      'https://eu.semsportal.com/api/v2/Common/CrossLogin',
      'https://au.semsportal.com/api/v2/Common/CrossLogin',
    ];

    var authTokenHeader = '';
    var apiBase = 'https://www.semsportal.com/api/';
    var lastErr = 'GoodWe SEMS login failed. Check your SEMS Portal email and password.';

    for (final url in loginUrls) {
      try {
        final resp = await http
            .post(
              Uri.parse(url),
              headers: {
                'User-Agent': _ua,
                'Content-Type': 'application/json',
                'Token': initToken,
              },
              body: jsonEncode({'account': user, 'pwd': password}),
            )
            .timeout(const Duration(seconds: 15));
        final j = _tryJsonMap(resp.body);
        final data = _asMap(j?['data']);
        if (resp.statusCode == 200 && j != null && j['hasError'] != true && data != null && _str(data['token']).isNotEmpty) {
          authTokenHeader = base64Encode(utf8.encode(jsonEncode(data)));
          final api = _str(j['api']);
          if (api.startsWith('https://')) {
            apiBase = api.endsWith('/') ? api : '$api/';
          }
          break;
        }
        if (j != null && _str(j['msg']).isNotEmpty) {
          lastErr = 'GoodWe SEMS: ${_str(j['msg'])}';
        }
      } catch (_) {
        // Try next region
      }
    }

    if (authTokenHeader.isEmpty) {
      return (ok: false, snapshot: null, error: lastErr);
    }

    var stationIds = <String>[];
    if (config.stationId.trim().isNotEmpty) {
      stationIds.add(config.stationId.trim());
    } else {
      final listPaths = <(String, Map<String, dynamic>)>[
        ('v2/HistoryData/QueryPowerStationByHistory', <String, dynamic>{}),
        ('v3/PowerStation/GetPowerStationList', <String, dynamic>{'page_index': 1, 'page_size': 20}),
        ('v1/PowerStation/GetPowerStationList', <String, dynamic>{'page_index': 1, 'page_size': 20}),
      ];
      for (final entry in listPaths) {
        try {
          final r = await http
              .post(
                Uri.parse('$apiBase${entry.$1}'),
                headers: {
                  'User-Agent': _ua,
                  'Content-Type': 'application/json',
                  'Token': authTokenHeader,
                },
                body: jsonEncode(entry.$2),
              )
              .timeout(const Duration(seconds: 15));
          final j = _tryJsonMap(r.body);
          final d = j?['data'];
          final rawArr = d is List
              ? _asListOfMaps(d)
              : (_asListOfMaps(_asMap(d)?['list']).isNotEmpty
                  ? _asListOfMaps(_asMap(d)?['list'])
                  : _asListOfMaps(_asMap(d)?['data']));
          for (final item in rawArr) {
            final id = _pickStr(item, ['id', 'powerstation_id', 'stationId']);
            if (id.isNotEmpty) stationIds.add(id);
          }
          if (stationIds.isNotEmpty) break;
        } catch (_) {
          // Try next path
        }
      }
    }

    if (stationIds.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: 'Signed in to GoodWe SEMS, but no power stations were found under this account.',
      );
    }

    Map<String, dynamic>? chosenDetail;
    var chosenPsId = stationIds.first;
    for (final psId in stationIds.take(5)) {
      try {
        final r = await http
            .post(
              Uri.parse('${apiBase}v2/PowerStation/GetMonitorDetailByPowerstationId'),
              headers: {
                'User-Agent': _ua,
                'Content-Type': 'application/json',
                'Token': authTokenHeader,
              },
              body: jsonEncode({'powerStationId': psId}),
            )
            .timeout(const Duration(seconds: 15));
        final j = _tryJsonMap(r.body);
        final d = _asMap(j?['data']);
        if (r.statusCode == 200 && j != null && j['hasError'] != true && d != null) {
          chosenPsId = psId;
          chosenDetail = d;
          if (config.inverterSerial.trim().isEmpty && config.loggerSerial.trim().isEmpty) break;
          final invs = _asListOfMaps(d['inverter']);
          final matched = invs.any((inv) {
            final full = _asMap(inv['invert_full']);
            final sn = _pickStr(inv, ['sn']).isNotEmpty ? _pickStr(inv, ['sn']) : _pickStr(full, ['sn']);
            return _serialsMatch(config.inverterSerial, sn) || _serialsMatch(config.loggerSerial, sn);
          });
          if (matched) break;
        }
      } catch (_) {
        // Try next station
      }
    }

    if (chosenDetail == null) {
      return (
        ok: false,
        snapshot: null,
        error: 'Signed in to GoodWe SEMS, but could not load plant monitor telemetry.',
      );
    }

    final info = _asMap(chosenDetail['info']) ?? const <String, dynamic>{};
    final kpi = _asMap(chosenDetail['kpi']) ?? const <String, dynamic>{};
    final pf = _asMap(chosenDetail['powerflow']) ?? const <String, dynamic>{};
    final energe = _asMap(chosenDetail['energeStatisticsTotals']) ?? const <String, dynamic>{};
    final invs = _asListOfMaps(chosenDetail['inverter']);
    final activeInv = invs.isNotEmpty ? invs.first : const <String, dynamic>{};
    final invFull = _asMap(activeInv['invert_full']) ?? const <String, dynamic>{};

    final liveKw = _toKwSmart(_pickNum(kpi, ['pac']), 'w') ??
        _toKwSmart(_pickNum(pf, ['pv']), 'w') ??
        _toKwSmart(_pickNum(invFull, ['pac', 'output_power']), 'w') ??
        0.0;
    final todayKwh = _pickNum(kpi, ['power']) ??
        _pickNum(energe, ['etoday', 'generation']) ??
        _pickNum(invFull, ['eday']) ??
        0.0;
    final monthKwh = _pickNum(kpi, ['month_generation']) ?? _pickNum(invFull, ['emonth']) ?? 0.0;
    final totalKwh = _pickNum(kpi, ['total_power']) ??
        _pickNum(energe, ['etotal']) ??
        _pickNum(invFull, ['etotal']) ??
        0.0;
    final ratedKw = _pickNum(info, ['capacity']) ?? 0.0;

    final rawStatus = _pickNum(invFull, ['status'])?.round() ?? _pickNum(activeInv, ['status'])?.round();
    final plantStatus = rawStatus == 1
        ? 'online'
        : rawStatus == 0
            ? 'standby'
            : rawStatus == 2
                ? 'fault'
                : rawStatus == -1
                    ? 'offline'
                    : (liveKw > 0 ? 'online' : 'standby');

    return (
      ok: true,
      snapshot: InverterSnapshot(
        brand: 'goodwe',
        authMode: config.authMode,
        plantName: _pickStr(info, ['stationname', 'name']).isNotEmpty
            ? _pickStr(info, ['stationname', 'name'])
            : 'GoodWe Solar Plant',
        plantStatus: plantStatus,
        loggerStatus: plantStatus == 'offline' ? 'offline' : 'online',
        currentKw: _round2(liveKw < 0 ? 0.0 : liveKw),
        todayKwh: _round2(todayKwh < 0 ? 0.0 : todayKwh),
        monthKwh: _round2(monthKwh < 0 ? 0.0 : monthKwh),
        totalKwh: _round2(totalKwh < 0 ? 0.0 : totalKwh),
        ratedKw: _round2(ratedKw < 0 ? 0.0 : ratedKw),
        gridVoltageV: _pickNum(invFull, ['vac1', 'vgrid1']),
        inverterTempC: _pickNum(invFull, ['tempperature', 'temperature']),
        batterySocPct: _pickNum(pf, ['soc']) ?? _pickNum(invFull, ['cbattery1', 'battery_soc']),
        dailyLogs: const [],
        syncedAt: DateTime.now().millisecondsSinceEpoch,
        note: 'GoodWe SEMS · ${_pickStr(invFull, ['sn']).isNotEmpty ? _pickStr(invFull, ['sn']) : chosenPsId}',
      ),
      error: null,
    );
  }

  // ==================== 3. GROWATT SHINESERVER ====================

  static String _growattMd5(String password, bool modified) {
    final digest = _md5Hex(password);
    if (!modified) return digest;
    final sb = StringBuffer();
    for (var i = 0; i < digest.length; i += 2) {
      final first = digest[i] == '0' ? 'c' : digest[i];
      sb.write(first);
      if (i + 1 < digest.length) sb.write(digest[i + 1]);
    }
    return sb.toString();
  }

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncGrowattDirect(
    InverterConfig config,
    String password,
  ) async {
    final user = config.username.trim();
    if (user.isEmpty || password.isEmpty) {
      return (ok: false, snapshot: null, error: 'Enter your Growatt ShineServer username and password.');
    }

    const bases = ['https://server.growatt.com', 'https://server-us.growatt.com'];
    var activeBase = bases.first;
    var cookieJar = '';
    var loggedIn = false;
    var plantItems = <Map<String, dynamic>>[];
    var lastErr = 'Growatt ShineServer login failed. Check your ShinePhone/ShineServer username and password.';

    for (final base in bases) {
      for (final modified in const [true, false]) {
        try {
          final resp = await http
              .post(
                Uri.parse('$base/newTwoLoginAPI.do'),
                headers: const {
                  'User-Agent': _ua,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {
                  'userName': user,
                  'password': _growattMd5(password, modified),
                },
              )
              .timeout(const Duration(seconds: 15));
          final j = _tryJsonMap(resp.body);
          final back = _asMap(j?['back']);
          if (resp.statusCode == 200 && back != null && back['success'] == true) {
            activeBase = base;
            cookieJar = _mergeCookies('', resp.headers['set-cookie']);
            loggedIn = true;
            plantItems = _asListOfMaps(back['data']);
            break;
          }
          if (back != null && _str(back['msg']).isNotEmpty) {
            lastErr = 'Growatt ShineServer: ${_str(back['msg'])}';
          }
        } catch (_) {
          // Try next variant
        }
      }
      if (loggedIn) break;
    }

    if (!loggedIn) {
      return (ok: false, snapshot: null, error: lastErr);
    }

    if (plantItems.isEmpty) {
      try {
        final plResp = await http
            .get(
              Uri.parse('$activeBase/PlantListAPI.do'),
              headers: {'User-Agent': _ua, 'Cookie': cookieJar},
            )
            .timeout(const Duration(seconds: 15));
        cookieJar = _mergeCookies(cookieJar, plResp.headers['set-cookie']);
        final plJson = _tryJsonMap(plResp.body);
        plantItems = _asListOfMaps(_asMap(plJson?['back'])?['data']);
      } catch (_) {
        // Ignore
      }
    }

    final plantIds = config.stationId.trim().isNotEmpty
        ? [config.stationId.trim()]
        : plantItems
            .map((p) => _pickStr(p, ['plantId', 'id']))
            .where((id) => id.isNotEmpty)
            .take(6)
            .toList();

    if (plantIds.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: 'Signed in to Growatt ShineServer, but no plants were found under this account.',
      );
    }

    var chosenPid = plantIds.first;
    Map<String, dynamic> chosenDevice = const {};
    Map<String, dynamic> chosenPlantData = const {};
    var matchedInvSn = config.inverterSerial.trim();

    for (final pid in plantIds) {
      try {
        final devResp = await http
            .get(
              Uri.parse(
                '$activeBase/newPlantAPI.do?op=getAllDeviceList&plantId=${Uri.encodeQueryComponent(pid)}&pageNum=1&pageSize=20',
              ),
              headers: {'User-Agent': _ua, 'Cookie': cookieJar},
            )
            .timeout(const Duration(seconds: 15));
        final devJson = _tryJsonMap(devResp.body);
        final devs = _asListOfMaps(devJson?['deviceList']);
        final pData = _asMap(devJson?['plantData']) ?? const <String, dynamic>{};
        if (devs.isNotEmpty) {
          chosenPid = pid;
          chosenPlantData = pData;
          chosenDevice = devs.first;
          matchedInvSn = _pickStr(devs.first, ['deviceSn', 'sn', 'alias']);
          var foundExact = false;
          for (final dev in devs) {
            final sn = _pickStr(dev, ['deviceSn', 'sn', 'alias']);
            final logSn = _pickStr(dev, ['datalogSn', 'datalog_sn', 'loggerSn']);
            if ((config.inverterSerial.trim().isNotEmpty && _serialsMatch(config.inverterSerial, sn)) ||
                (config.loggerSerial.trim().isNotEmpty && _serialsMatch(config.loggerSerial, logSn))) {
              chosenDevice = dev;
              matchedInvSn = sn;
              foundExact = true;
              break;
            }
          }
          if (foundExact || (config.inverterSerial.trim().isEmpty && config.loggerSerial.trim().isEmpty)) {
            break;
          }
        }
      } catch (_) {
        // Continue
      }
    }

    var invDetail = <String, dynamic>{};
    if (matchedInvSn.isNotEmpty) {
      try {
        final dResp = await http
            .get(
              Uri.parse(
                '$activeBase/newInverterAPI.do?op=getInverterData&id=${Uri.encodeQueryComponent(matchedInvSn)}',
              ),
              headers: {'User-Agent': _ua, 'Cookie': cookieJar},
            )
            .timeout(const Duration(seconds: 15));
        final dJson = _tryJsonMap(dResp.body);
        if (dJson != null) {
          invDetail = _asMap(dJson['obj']) ?? dJson;
        }
      } catch (_) {
        // Fallback to device summary
      }
    }

    final merged = <String, dynamic>{...chosenPlantData, ...chosenDevice, ...invDetail};
    final liveKw = _toKwSmart(_pickNum(merged, ['pac', 'power', 'currentPower', 'ppv']), '') ?? 0.0;
    final todayKwh = _pickNum(merged, ['eToday', 'energyToday', 'todayEnergy', 'e_today']) ?? 0.0;
    final monthKwh = _pickNum(merged, ['eMonth', 'energyMonth']) ?? 0.0;
    final totalKwh = _pickNum(merged, ['eTotal', 'energyTotal', 'totalEnergy']) ?? 0.0;
    final ratedKw = _toKwSmart(_pickNum(merged, ['nominalPower', 'nominal_Power']), 'w') ?? 0.0;
    final isLost = merged['lost'] == true || _str(merged['lost']) == 'true' || _str(merged['deviceStatus']) == '-1';
    final plantStatus = isLost
        ? 'offline'
        : _str(merged['deviceStatus']) == '3'
            ? 'fault'
            : (liveKw > 0 ? 'online' : 'standby');

    var plantName = _pickStr(merged, ['plantName']);
    if (plantName.isEmpty) {
      for (final p in plantItems) {
        if (_pickStr(p, ['plantId', 'id']) == chosenPid) {
          plantName = _pickStr(p, ['plantName', 'name']);
          break;
        }
      }
    }

    return (
      ok: true,
      snapshot: InverterSnapshot(
        brand: 'growatt',
        authMode: config.authMode,
        plantName: plantName.isNotEmpty ? plantName : 'Growatt Solar Plant',
        plantStatus: plantStatus,
        loggerStatus: isLost ? 'offline' : 'online',
        currentKw: _round2(liveKw < 0 ? 0.0 : liveKw),
        todayKwh: _round2(todayKwh < 0 ? 0.0 : todayKwh),
        monthKwh: _round2(monthKwh < 0 ? 0.0 : monthKwh),
        totalKwh: _round2(totalKwh < 0 ? 0.0 : totalKwh),
        ratedKw: _round2(ratedKw < 0 ? 0.0 : ratedKw),
        gridVoltageV: _pickNum(merged, ['vacr', 'vac1', 'vGrid']),
        inverterTempC: _pickNum(merged, ['temperature', 'temp1', 'invTemperature']),
        batterySocPct: _pickNum(merged, ['soc', 'batterySoc']),
        dailyLogs: const [],
        syncedAt: DateTime.now().millisecondsSinceEpoch,
        note: 'Growatt Cloud · ${matchedInvSn.isNotEmpty ? matchedInvSn : chosenPid}',
      ),
      error: null,
    );
  }

  // ==================== 4. SOLARMAN SMART / BUSINESS ====================

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncSolarmanDirect(
    InverterConfig config,
    String password,
    String apiSecret,
  ) async {
    final user = config.username.trim();
    final appId = config.apiKey.trim();
    final appSec = apiSecret.trim();
    final sha256Pwd = _sha256Hex(password);

    var accessToken = '';
    var useOpenApi = false;
    var webOrigin = 'https://globalhome.solarmanpv.com';
    var lastErr = 'Solarman login failed. Verify your Solarman Smart/Business email and password.';

    if (appId.isNotEmpty && appSec.isNotEmpty) {
      try {
        final resp = await http
            .post(
              Uri.parse(
                'https://globalapi.solarmanpv.com/account/v1.0/token?appId=${Uri.encodeQueryComponent(appId)}&language=en',
              ),
              headers: const {'User-Agent': _ua, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'appSecret': appSec,
                if (user.contains('@')) 'email': user else 'username': user,
                'password': sha256Pwd,
              }),
            )
            .timeout(const Duration(seconds: 15));
        final j = _tryJsonMap(resp.body);
        if (resp.statusCode == 200 && j != null && _str(j['access_token']).isNotEmpty) {
          accessToken = _str(j['access_token']);
          useOpenApi = true;
        } else if (j != null && _str(j['msg']).isNotEmpty) {
          lastErr = 'Solarman OpenAPI: ${_str(j['msg'])}';
        }
      } catch (_) {
        // Fallback to web OAuth
      }
    }

    if (accessToken.isEmpty) {
      if (user.isEmpty || password.isEmpty) {
        return (
          ok: false,
          snapshot: null,
          error: 'Enter your Solarman email/username and password (or API AppID & AppSecret).',
        );
      }
      const origins = ['https://globalhome.solarmanpv.com', 'https://globalpro.solarmanpv.com'];
      for (final orig in origins) {
        try {
          final resp = await http
              .post(
                Uri.parse('$orig/oauth-s/oauth/token'),
                headers: const {
                  'User-Agent': _ua,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {
                  'grant_type': 'password',
                  'username': user,
                  'password': sha256Pwd,
                  'clear_text_pwd': password,
                  'identity_type': user.contains('@') ? '2' : '1',
                  'client_id': 'test',
                  'system': 'SOLARMAN',
                },
              )
              .timeout(const Duration(seconds: 15));
          final j = _tryJsonMap(resp.body);
          if (resp.statusCode == 200 && j != null && _str(j['access_token']).isNotEmpty) {
            accessToken = _str(j['access_token']);
            webOrigin = orig;
            break;
          }
          final msg = _pickStr(j, ['error_description', 'msg']);
          if (msg.isNotEmpty) lastErr = 'Solarman: $msg';
        } catch (_) {
          // Try next origin
        }
      }
    }

    if (accessToken.isEmpty) {
      return (ok: false, snapshot: null, error: lastErr);
    }

    final authHeader = 'bearer $accessToken';
    if (useOpenApi) {
      final stResp = await http
          .post(
            Uri.parse('https://globalapi.solarmanpv.com/station/v1.0/list?language=en'),
            headers: {
              'User-Agent': _ua,
              'Content-Type': 'application/json',
              'Authorization': authHeader,
            },
            body: jsonEncode({'page': 1, 'size': 20}),
          )
          .timeout(const Duration(seconds: 15));
      final stJson = _tryJsonMap(stResp.body);
      final stations = _asListOfMaps(stJson?['stationList']);
      if (stations.isEmpty) {
        return (ok: false, snapshot: null, error: 'Signed in to Solarman API, but no stations were found.');
      }
      var chosen = stations.first;
      if (config.stationId.trim().isNotEmpty) {
        for (final s in stations) {
          if (_str(s['id']) == config.stationId.trim()) {
            chosen = s;
            break;
          }
        }
      }
      final sidStr = _str(chosen['id']);
      final dynamic sidVal = int.tryParse(sidStr) ?? sidStr;
      final rtResp = await http
          .post(
            Uri.parse('https://globalapi.solarmanpv.com/station/v1.0/realTime?language=en'),
            headers: {
              'User-Agent': _ua,
              'Content-Type': 'application/json',
              'Authorization': authHeader,
            },
            body: jsonEncode({'stationId': sidVal}),
          )
          .timeout(const Duration(seconds: 15));
      final rt = _tryJsonMap(rtResp.body) ?? const <String, dynamic>{};
      final liveW = _pickNum(rt, ['generationPower']) ?? 0.0;
      final todayKwh = _pickNum(rt, ['generationValue']) ?? 0.0;
      final totalKwh = _pickNum(rt, ['generationTotal']) ?? 0.0;
      final ratedKw = _toKwSmart(_pickNum(chosen, ['installedCapacity']), 'kw') ?? 0.0;

      return (
        ok: true,
        snapshot: InverterSnapshot(
          brand: 'solarman',
          authMode: 'api',
          plantName: _pickStr(chosen, ['name']).isNotEmpty ? _pickStr(chosen, ['name']) : 'Solarman Plant',
          plantStatus: liveW > 0 ? 'online' : 'standby',
          loggerStatus: 'online',
          currentKw: _round2(liveW < 0 ? 0.0 : liveW / 1000.0),
          todayKwh: _round2(todayKwh < 0 ? 0.0 : todayKwh),
          monthKwh: 0.0,
          totalKwh: _round2(totalKwh < 0 ? 0.0 : totalKwh),
          ratedKw: _round2(ratedKw < 0 ? 0.0 : ratedKw),
          batterySocPct: _pickNum(rt, ['batterySoc']),
          dailyLogs: const [],
          syncedAt: DateTime.now().millisecondsSinceEpoch,
          note: 'Solarman Cloud · $sidStr',
        ),
        error: null,
      );
    }

    final webResp = await http
        .post(
          Uri.parse(
            '$webOrigin/maintain-s/operating/station/v2/search?page=1&size=20&order.direction=DESC&order.property=id',
          ),
          headers: {
            'User-Agent': _ua,
            'Content-Type': 'application/json',
            'Authorization': authHeader,
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 15));
    final webJson = _tryJsonMap(webResp.body);
    final webStations = _asListOfMaps(webJson?['data']);
    if (webStations.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: 'Signed in to Solarman, but no stations were returned for this account.',
      );
    }
    final chosen = webStations.first;
    final genPowerW = _pickNum(chosen, ['generationPower']) ?? 0.0;
    final genToday = _pickNum(chosen, ['generationValue']) ?? 0.0;
    final genTotal = _pickNum(chosen, ['generationTotal']) ?? 0.0;
    final cap = _pickNum(chosen, ['installedCapacity']) ?? 0.0;

    return (
      ok: true,
      snapshot: InverterSnapshot(
        brand: 'solarman',
        authMode: 'website',
        plantName: _pickStr(chosen, ['name']).isNotEmpty ? _pickStr(chosen, ['name']) : 'Solarman Plant',
        plantStatus: genPowerW > 0 ? 'online' : 'standby',
        loggerStatus: 'online',
        currentKw: _round2(genPowerW < 0 ? 0.0 : genPowerW / 1000.0),
        todayKwh: _round2(genToday < 0 ? 0.0 : genToday),
        monthKwh: 0.0,
        totalKwh: _round2(genTotal < 0 ? 0.0 : genTotal),
        ratedKw: _round2(cap < 0 ? 0.0 : cap),
        dailyLogs: const [],
        syncedAt: DateTime.now().millisecondsSinceEpoch,
        note: 'Solarman Web · ${_pickStr(chosen, ['name']).isNotEmpty ? _pickStr(chosen, ['name']) : 'Synced'}',
      ),
      error: null,
    );
  }

  // ==================== 5. SUNGROW iSOLARCLOUD ====================

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncSungrowDirect(
    InverterConfig config,
    String password,
  ) async {
    final user = config.username.trim();
    if (user.isEmpty || password.isEmpty) {
      return (ok: false, snapshot: null, error: 'Enter your Sungrow iSolarCloud email/username and password.');
    }

    const appKey = 'ANDROIDE13EC118D789299C9A503F2184611882';
    const gateways = [
      'https://gateway.isolarcloud.com.hk',
      'https://gateway.isolarcloud.com',
      'https://gateway.isolarcloud.eu',
    ];

    var activeGw = gateways.first;
    var token = '';
    var userId = '';
    var lastErr = 'Sungrow iSolarCloud login failed. Verify your email/username and password.';

    for (final gw in gateways) {
      try {
        final resp = await http
            .post(
              Uri.parse('$gw/v1/userService/login'),
              headers: const {
                'User-Agent': _ua,
                'Content-Type': 'application/json',
                'sys_code': '900',
              },
              body: jsonEncode({
                'appkey': appKey,
                'user_account': user,
                'user_password': password,
                'login_type': '1',
                'sys_code': '900',
                'lang': '_en_US',
              }),
            )
            .timeout(const Duration(seconds: 15));
        final j = _tryJsonMap(resp.body);
        final rd = _asMap(j?['result_data']);
        if (resp.statusCode == 200 && _str(j?['result_code']) == '1' && _str(rd?['token']).isNotEmpty) {
          activeGw = gw;
          token = _str(rd?['token']);
          userId = _str(rd?['user_id']);
          break;
        }
        if (_str(j?['result_msg']).isNotEmpty) {
          lastErr = 'Sungrow iSolarCloud: ${_str(j?['result_msg'])}';
        }
      } catch (_) {
        // Try next gateway
      }
    }

    if (token.isEmpty) {
      return (ok: false, snapshot: null, error: lastErr);
    }

    final psResp = await http
        .post(
          Uri.parse('$activeGw/v1/powerStationService/getPsList'),
          headers: const {
            'User-Agent': _ua,
            'Content-Type': 'application/json',
            'sys_code': '900',
          },
          body: jsonEncode({
            'appkey': appKey,
            'token': token,
            'user_id': userId,
            'sys_code': '900',
            'lang': '_en_US',
            'curPage': 1,
            'size': 20,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final psJson = _tryJsonMap(psResp.body);
    final plants = _asListOfMaps(_asMap(psJson?['result_data'])?['pageList']);
    if (plants.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: 'Signed in to Sungrow iSolarCloud, but no power stations were found on this account.',
      );
    }

    var chosen = plants.first;
    if (config.stationId.trim().isNotEmpty) {
      for (final p in plants) {
        if (_str(p['ps_id']) == config.stationId.trim()) {
          chosen = p;
          break;
        }
      }
    }

    ({double? val, String unit}) extractMetric(dynamic field) {
      final m = _asMap(field);
      if (m != null && m.containsKey('value')) {
        return (val: _optDouble(m['value']), unit: _str(m['unit']));
      }
      return (val: _optDouble(field), unit: '');
    }

    final currP = extractMetric(chosen['curr_power']);
    final todayE = extractMetric(chosen['today_energy']);
    final totalE = extractMetric(chosen['total_energy']);
    final capM = extractMetric(chosen['total_capcity']);

    final liveKw = _toKwSmart(currP.val, currP.unit) ?? 0.0;
    var todayKwh = todayE.val ?? 0.0;
    if (todayE.unit.toLowerCase() == 'mwh') todayKwh *= 1000.0;
    if (todayE.unit.toLowerCase() == 'wh') todayKwh /= 1000.0;
    var totalKwh = totalE.val ?? 0.0;
    if (totalE.unit.toLowerCase() == 'mwh') totalKwh *= 1000.0;
    final ratedKw = _toKwSmart(capM.val, capM.unit.isNotEmpty ? capM.unit : 'kwp') ?? 0.0;

    final psStatus = _pickNum(chosen, ['ps_status', 'ps_fault_status'])?.round();
    final plantStatus = psStatus == 1
        ? 'online'
        : psStatus == 2
            ? 'offline'
            : psStatus == 3
                ? 'fault'
                : 'online';

    return (
      ok: true,
      snapshot: InverterSnapshot(
        brand: 'sungrow',
        authMode: config.authMode,
        plantName: _pickStr(chosen, ['ps_name']).isNotEmpty
            ? _pickStr(chosen, ['ps_name'])
            : 'Sungrow Solar Plant',
        plantStatus: plantStatus,
        loggerStatus: psStatus == 2 ? 'offline' : 'online',
        currentKw: _round2(liveKw < 0 ? 0.0 : liveKw),
        todayKwh: _round2(todayKwh < 0 ? 0.0 : todayKwh),
        monthKwh: 0.0,
        totalKwh: _round2(totalKwh < 0 ? 0.0 : totalKwh),
        ratedKw: _round2(ratedKw < 0 ? 0.0 : ratedKw),
        dailyLogs: const [],
        syncedAt: DateTime.now().millisecondsSinceEpoch,
        note: 'Sungrow iSolarCloud · ${_pickStr(chosen, ['ps_id'])}',
      ),
      error: null,
    );
  }

  // ==================== 6. SHINEMONITOR / DESSMONITOR (Eybond SmartESS OEM Cloud) ====================

  static InverterSnapshot _rebrandSnapshot(InverterSnapshot snap, String brandId, String brandLabel) {
    return InverterSnapshot(
      brand: brandId,
      authMode: snap.authMode,
      plantName: snap.plantName.isNotEmpty ? snap.plantName : '$brandLabel Plant',
      plantStatus: snap.plantStatus,
      loggerStatus: snap.loggerStatus,
      currentKw: snap.currentKw,
      todayKwh: snap.todayKwh,
      monthKwh: snap.monthKwh,
      totalKwh: snap.totalKwh,
      ratedKw: snap.ratedKw,
      gridVoltageV: snap.gridVoltageV,
      inverterTempC: snap.inverterTempC,
      batterySocPct: snap.batterySocPct,
      dailyLogs: snap.dailyLogs,
      syncedAt: snap.syncedAt,
      note: snap.note.isNotEmpty ? '$brandLabel · ${snap.note}' : brandLabel,
    );
  }

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncShineMonitorDirect(
    InverterConfig config,
    String password, {
    required String brandId,
    required String brandLabel,
  }) async {
    final user = config.username.trim();
    if (user.isEmpty || password.isEmpty) {
      return (ok: false, snapshot: null, error: 'Enter your $brandLabel username/email and password.');
    }

    const hosts = [
      'https://web.shinemonitor.com/public/',
      'https://api.dessmonitor.com/public/',
    ];
    const companyKeys = ['bnrl_frRFjEz8Mkn'];

    final pwdSha1 = _sha1Hex(password);
    var activeHost = '';
    var token = '';
    var secret = '';
    var lastErr = '$brandLabel login failed. Check your monitoring username and password.';

    for (final host in hosts) {
      for (final cKey in companyKeys) {
        try {
          final salt = DateTime.now().millisecondsSinceEpoch.toString();
          final action =
              '&action=authSource&usr=${Uri.encodeQueryComponent(user)}&company-key=${Uri.encodeQueryComponent(cKey)}&source=1';
          final sign = _sha1Hex('$salt$pwdSha1$action');
          final resp = await http
              .get(
                Uri.parse('$host?sign=$sign&salt=$salt$action'),
                headers: const {'User-Agent': _ua, 'Accept': 'application/json'},
              )
              .timeout(const Duration(seconds: 15));
          final j = _tryJsonMap(resp.body);
          final err = _pickNum(j, ['err'])?.round();
          final dat = _asMap(j?['dat']);
          if (resp.statusCode == 200 && err == 0 && dat != null && _str(dat['token']).isNotEmpty) {
            activeHost = host;
            token = _str(dat['token']);
            secret = _str(dat['secret']);
            break;
          }
          final desc = _str(j?['desc']);
          if (desc.isNotEmpty) lastErr = '$brandLabel: $desc';
        } catch (_) {
          // Try next host
        }
      }
      if (token.isNotEmpty) break;
    }

    if (token.isEmpty || secret.isEmpty) {
      return (ok: false, snapshot: null, error: lastErr);
    }

    Future<Map<String, dynamic>?> querySigned(String actionParams) async {
      try {
        final salt = DateTime.now().millisecondsSinceEpoch.toString();
        final sign = _sha1Hex('$salt$secret$token$actionParams');
        final r = await http
            .get(
              Uri.parse('$activeHost?sign=$sign&salt=$salt&token=${Uri.encodeQueryComponent(token)}$actionParams'),
              headers: const {'User-Agent': _ua, 'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 15));
        final j = _tryJsonMap(r.body);
        if (r.statusCode == 200 && _pickNum(j, ['err'])?.round() == 0) {
          return j;
        }
      } catch (_) {}
      return null;
    }

    final plantsResp = await querySigned('&action=queryPlants&pagesize=20&page=0');
    final plantsDat = _asMap(plantsResp?['dat']);
    final plants = _asListOfMaps(plantsDat?['plant']);
    if (plants.isEmpty) {
      return (
        ok: false,
        snapshot: null,
        error: 'Signed in to $brandLabel cloud, but no plants were found under this account.',
      );
    }

    var chosen = plants.first;
    if (config.stationId.trim().isNotEmpty) {
      for (final p in plants) {
        if (_pickStr(p, ['pid', 'plantid', 'id']) == config.stationId.trim()) {
          chosen = p;
          break;
        }
      }
    }

    final pid = _pickStr(chosen, ['pid', 'plantid', 'id']);
    final plantName = _pickStr(chosen, ['name', 'plantname']).isNotEmpty
        ? _pickStr(chosen, ['name', 'plantname'])
        : '$brandLabel Solar Plant';
    final ratedKw = _toKwSmart(_pickNum(chosen, ['nominalPower', 'capacity']), 'kw') ?? 0.0;

    var liveKw = _toKwSmart(_pickNum(chosen, ['currPower', 'outputPower']), '') ?? 0.0;
    var todayKwh = _pickNum(chosen, ['energyToday', 'dayEnergy']) ?? 0.0;
    var monthKwh = _pickNum(chosen, ['energyMonth', 'monthEnergy']) ?? 0.0;
    var totalKwh = _pickNum(chosen, ['energyTotal', 'totalEnergy']) ?? 0.0;

    if (pid.isNotEmpty) {
      final metrics = await Future.wait([
        querySigned('&action=queryPlantActiveOuputPowerCurrent&plantid=${Uri.encodeQueryComponent(pid)}'),
        querySigned('&action=queryPlantEnergyDay&plantid=${Uri.encodeQueryComponent(pid)}'),
        querySigned('&action=queryPlantEnergyMonth&plantid=${Uri.encodeQueryComponent(pid)}'),
        querySigned('&action=queryPlantEnergyTotal&plantid=${Uri.encodeQueryComponent(pid)}'),
      ]);
      final pDat = _asMap(metrics[0]?['dat']);
      final dDat = _asMap(metrics[1]?['dat']);
      final mDat = _asMap(metrics[2]?['dat']);
      final tDat = _asMap(metrics[3]?['dat']);

      final pVal = _pickNum(pDat, ['outputPower', 'power', 'val']);
      if (pVal != null) liveKw = _toKwSmart(pVal, _pickStr(pDat, ['unit'])) ?? liveKw;
      final dVal = _pickNum(dDat, ['energy', 'val']);
      if (dVal != null) todayKwh = dVal;
      final mVal = _pickNum(mDat, ['energy', 'val']);
      if (mVal != null) monthKwh = mVal;
      final tVal = _pickNum(tDat, ['energy', 'val']);
      if (tVal != null) totalKwh = tVal;
    }

    final statusCode = _pickNum(chosen, ['status'])?.round();
    final plantStatus = statusCode == 0
        ? 'online'
        : statusCode == 1
            ? 'offline'
            : statusCode == 4
                ? 'fault'
                : (liveKw > 0 ? 'online' : 'standby');

    return (
      ok: true,
      snapshot: InverterSnapshot(
        brand: brandId,
        authMode: config.authMode,
        plantName: plantName,
        plantStatus: plantStatus,
        loggerStatus: plantStatus == 'offline' ? 'offline' : 'online',
        currentKw: _round2(liveKw < 0 ? 0.0 : liveKw),
        todayKwh: _round2(todayKwh < 0 ? 0.0 : todayKwh),
        monthKwh: _round2(monthKwh < 0 ? 0.0 : monthKwh),
        totalKwh: _round2(totalKwh < 0 ? 0.0 : totalKwh),
        ratedKw: _round2(ratedKw < 0 ? 0.0 : ratedKw),
        dailyLogs: const [],
        syncedAt: DateTime.now().millisecondsSinceEpoch,
        note: '$brandLabel · ${pid.isNotEmpty ? pid : 'Synced'}',
      ),
      error: null,
    );
  }

  // ==================== 7. POLYGUN / POLYCAB, PURE / PuREPower, HITACHI ====================

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncPolygunDirect(
    InverterConfig config,
    String password,
    String apiSecret,
  ) async {
    final isApi = config.authMode == 'api';
    if (isApi) {
      final keyId = config.apiKey.trim();
      final keySec = apiSecret.trim();
      if (RegExp(r'^\d{15,24}$').hasMatch(keyId) && keySec.isNotEmpty) {
        final polyApi = await _syncSolisCloudApiDirect(
          config,
          keyId,
          keySec,
          apiBase: 'https://minvertermonitoring.polycab.com:13333',
        );
        if (polyApi.ok && polyApi.snapshot != null) {
          return (
            ok: true,
            snapshot: _rebrandSnapshot(polyApi.snapshot!, 'polygun', 'Polygun / Polycab'),
            error: null,
          );
        }
        final solisApi = await _syncSolisCloudApiDirect(config, keyId, keySec);
        if (solisApi.ok && solisApi.snapshot != null) {
          return (
            ok: true,
            snapshot: _rebrandSnapshot(solisApi.snapshot!, 'polygun', 'Polygun / Polycab'),
            error: null,
          );
        }
        return (
          ok: false,
          snapshot: null,
          error: polyApi.error ?? solisApi.error ?? 'Polygun / Polycab API sync failed.',
        );
      }
      final sm = await _syncSolarmanDirect(config, password, apiSecret);
      if (sm.ok && sm.snapshot != null) {
        return (
          ok: true,
          snapshot: _rebrandSnapshot(sm.snapshot!, 'polygun', 'Polygun / Polycab'),
          error: null,
        );
      }
      return (
        ok: false,
        snapshot: null,
        error: sm.error ?? 'Enter your Polygun / Polycab API Key & Secret or Custom HTTPS JSON Endpoint.',
      );
    }

    // Website mode: try Solarman -> ShineMonitor/DessMonitor -> SolisCloud
    final sm = await _syncSolarmanDirect(config, password, apiSecret);
    if (sm.ok && sm.snapshot != null) {
      return (
        ok: true,
        snapshot: _rebrandSnapshot(sm.snapshot!, 'polygun', 'Polygun / Polycab'),
        error: null,
      );
    }
    final shine = await _syncShineMonitorDirect(
      config,
      password,
      brandId: 'polygun',
      brandLabel: 'Polygun / Polycab',
    );
    if (shine.ok && shine.snapshot != null) return shine;

    final solis = await _syncSolisCloudWebDirect(config, password);
    if (solis.ok && solis.snapshot != null) {
      return (
        ok: true,
        snapshot: _rebrandSnapshot(solis.snapshot!, 'polygun', 'Polygun / Polycab'),
        error: null,
      );
    }

    return (
      ok: false,
      snapshot: null,
      error:
          'Polygun / Polycab login failed. Verify your portal username/password (Polycab Solar / Solarman / ShineMonitor), or switch to API Integration with your KeyID & KeySecret or Custom JSON Endpoint.',
    );
  }

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncPureDirect(
    InverterConfig config,
    String password,
    String apiSecret,
  ) async {
    if (config.authMode == 'api') {
      final sm = await _syncSolarmanDirect(config, password, apiSecret);
      if (sm.ok && sm.snapshot != null) {
        return (
          ok: true,
          snapshot: _rebrandSnapshot(sm.snapshot!, 'pure', 'PURE / PuREPower'),
          error: null,
        );
      }
      return (
        ok: false,
        snapshot: null,
        error: sm.error ?? 'Enter your PURE / PuREPower API credentials or Custom HTTPS JSON Endpoint.',
      );
    }

    // Website mode: PuREPower Smart ESS dongles use ShineMonitor/DessMonitor or Solarman
    final shine = await _syncShineMonitorDirect(
      config,
      password,
      brandId: 'pure',
      brandLabel: 'PURE / PuREPower',
    );
    if (shine.ok && shine.snapshot != null) return shine;

    final sm = await _syncSolarmanDirect(config, password, apiSecret);
    if (sm.ok && sm.snapshot != null) {
      return (
        ok: true,
        snapshot: _rebrandSnapshot(sm.snapshot!, 'pure', 'PURE / PuREPower'),
        error: null,
      );
    }

    return (
      ok: false,
      snapshot: null,
      error:
          'PURE / PuREPower login failed. Verify your SmartESS / Solarman dongle credentials, or switch to API Integration and enter your Custom HTTPS JSON Endpoint.',
    );
  }

  static Future<({bool ok, InverterSnapshot? snapshot, String? error})> _syncHitachiDirect(
    InverterConfig config,
    String password,
    String apiSecret,
  ) async {
    if (config.authMode == 'api') {
      final keyId = config.apiKey.trim();
      final keySec = apiSecret.trim();
      if (RegExp(r'^\d{15,24}$').hasMatch(keyId) && keySec.isNotEmpty) {
        final sol = await _syncSolisCloudApiDirect(config, keyId, keySec);
        if (sol.ok && sol.snapshot != null) {
          return (
            ok: true,
            snapshot: _rebrandSnapshot(sol.snapshot!, 'hitachi', 'Hitachi Solar'),
            error: null,
          );
        }
      }
      final sm = await _syncSolarmanDirect(config, password, apiSecret);
      if (sm.ok && sm.snapshot != null) {
        return (
          ok: true,
          snapshot: _rebrandSnapshot(sm.snapshot!, 'hitachi', 'Hitachi Solar'),
          error: null,
        );
      }
      return (
        ok: false,
        snapshot: null,
        error: sm.error ?? 'Enter your Hitachi Solar API credentials or Custom HTTPS JSON Endpoint.',
      );
    }

    // Website mode: Hitachi Hi-Rel Wi-Fi loggers use Solarman, ShineMonitor/DessMonitor, or SolisCloud
    final sm = await _syncSolarmanDirect(config, password, apiSecret);
    if (sm.ok && sm.snapshot != null) {
      return (
        ok: true,
        snapshot: _rebrandSnapshot(sm.snapshot!, 'hitachi', 'Hitachi Solar'),
        error: null,
      );
    }

    final shine = await _syncShineMonitorDirect(
      config,
      password,
      brandId: 'hitachi',
      brandLabel: 'Hitachi Solar',
    );
    if (shine.ok && shine.snapshot != null) return shine;

    final solis = await _syncSolisCloudWebDirect(config, password);
    if (solis.ok && solis.snapshot != null) {
      return (
        ok: true,
        snapshot: _rebrandSnapshot(solis.snapshot!, 'hitachi', 'Hitachi Solar'),
        error: null,
      );
    }

    return (
      ok: false,
      snapshot: null,
      error:
          'Hitachi Solar login failed. Verify your Wi-Fi logger portal credentials (Solarman / ShineMonitor / SolisCloud), or switch to API Integration with your Custom HTTPS JSON Endpoint.',
    );
  }

  // ==================== Pure-Dart RFC Crypto & Date Helpers (Zero Extra Packages) ====================

  static String _rfc1123Utc(DateTime utc) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final wd = days[utc.weekday - 1];
    final dd = utc.day.toString().padLeft(2, '0');
    final mo = months[utc.month - 1];
    final yyyy = utc.year.toString().padLeft(4, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final mm = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    return '$wd, $dd $mo $yyyy $hh:$mm:$ss GMT';
  }

  static String _bytesToHex(Uint8List bytes) {
    const hex = '0123456789abcdef';
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(hex[(b >> 4) & 0x0f]);
      sb.write(hex[b & 0x0f]);
    }
    return sb.toString();
  }

  static int _rotl32(int x, int n) {
    final u = x & 0xffffffff;
    return ((u << n) & 0xffffffff) | (u >> (32 - n));
  }

  static int _rotr32(int x, int n) {
    final u = x & 0xffffffff;
    return (u >> n) | ((u << (32 - n)) & 0xffffffff);
  }

  /// RFC 1321 MD5 digest (pure Dart, zero dependencies).
  static Uint8List _md5Bytes(Uint8List input) {
    const s = <int>[
      7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const k = <int>[
      0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
      0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
      0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
      0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
      0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
      0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
      0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
      0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
      0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
      0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
      0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
      0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
      0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
      0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
      0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
      0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ];

    final origLen = input.length;
    final bitLen = origLen * 8;
    final padLen = ((56 - ((origLen + 1) % 64)) + 64) % 64;
    final msg = Uint8List(origLen + 1 + padLen + 8);
    msg.setRange(0, origLen, input);
    msg[origLen] = 0x80;

    final lowBits = bitLen & 0xffffffff;
    final highBits = (bitLen ~/ 0x100000000) & 0xffffffff;
    final lenOff = msg.length - 8;
    msg[lenOff] = lowBits & 0xff;
    msg[lenOff + 1] = (lowBits >> 8) & 0xff;
    msg[lenOff + 2] = (lowBits >> 16) & 0xff;
    msg[lenOff + 3] = (lowBits >> 24) & 0xff;
    msg[lenOff + 4] = highBits & 0xff;
    msg[lenOff + 5] = (highBits >> 8) & 0xff;
    msg[lenOff + 6] = (highBits >> 16) & 0xff;
    msg[lenOff + 7] = (highBits >> 24) & 0xff;

    var a0 = 0x67452301;
    var b0 = 0xefcdab89;
    var c0 = 0x98badcfe;
    var d0 = 0x10325476;
    final m = List<int>.filled(16, 0);

    for (var offset = 0; offset < msg.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        m[i] = msg[j] | (msg[j + 1] << 8) | (msg[j + 2] << 16) | (msg[j + 3] << 24);
      }

      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;

      for (var i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = ((b & c) | ((~b & 0xffffffff) & d)) & 0xffffffff;
          g = i;
        } else if (i < 32) {
          f = ((d & b) | ((~d & 0xffffffff) & c)) & 0xffffffff;
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = (b ^ c ^ d) & 0xffffffff;
          g = (3 * i + 5) % 16;
        } else {
          f = (c ^ (b | (~d & 0xffffffff))) & 0xffffffff;
          g = (7 * i) % 16;
        }
        final sum = (a + f + k[i] + m[g]) & 0xffffffff;
        a = d;
        d = c;
        c = b;
        b = (b + _rotl32(sum, s[i])) & 0xffffffff;
      }

      a0 = (a0 + a) & 0xffffffff;
      b0 = (b0 + b) & 0xffffffff;
      c0 = (c0 + c) & 0xffffffff;
      d0 = (d0 + d) & 0xffffffff;
    }

    final out = Uint8List(16);
    final words = [a0, b0, c0, d0];
    for (var i = 0; i < 4; i++) {
      out[i * 4] = words[i] & 0xff;
      out[i * 4 + 1] = (words[i] >> 8) & 0xff;
      out[i * 4 + 2] = (words[i] >> 16) & 0xff;
      out[i * 4 + 3] = (words[i] >> 24) & 0xff;
    }
    return out;
  }

  static String _md5Hex(String s) => _bytesToHex(_md5Bytes(Uint8List.fromList(utf8.encode(s))));

  static String _md5Base64(String s) => base64Encode(_md5Bytes(Uint8List.fromList(utf8.encode(s))));

  /// FIPS 180-4 SHA-1 digest (pure Dart, zero dependencies).
  static Uint8List _sha1Bytes(Uint8List input) {
    final origLen = input.length;
    final bitLen = origLen * 8;
    final padLen = ((56 - ((origLen + 1) % 64)) + 64) % 64;
    final msg = Uint8List(origLen + 1 + padLen + 8);
    msg.setRange(0, origLen, input);
    msg[origLen] = 0x80;

    final highBits = (bitLen ~/ 0x100000000) & 0xffffffff;
    final lowBits = bitLen & 0xffffffff;
    final lenOff = msg.length - 8;
    msg[lenOff] = (highBits >> 24) & 0xff;
    msg[lenOff + 1] = (highBits >> 16) & 0xff;
    msg[lenOff + 2] = (highBits >> 8) & 0xff;
    msg[lenOff + 3] = highBits & 0xff;
    msg[lenOff + 4] = (lowBits >> 24) & 0xff;
    msg[lenOff + 5] = (lowBits >> 16) & 0xff;
    msg[lenOff + 6] = (lowBits >> 8) & 0xff;
    msg[lenOff + 7] = lowBits & 0xff;

    var h0 = 0x67452301;
    var h1 = 0xefcdab89;
    var h2 = 0x98badcfe;
    var h3 = 0x10325476;
    var h4 = 0xc3d2e1f0;
    final w = List<int>.filled(80, 0);

    for (var offset = 0; offset < msg.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] = (msg[j] << 24) | (msg[j + 1] << 16) | (msg[j + 2] << 8) | msg[j + 3];
      }
      for (var i = 16; i < 80; i++) {
        w[i] = _rotl32((w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]) & 0xffffffff, 1);
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;

      for (var i = 0; i < 80; i++) {
        int f;
        int k;
        if (i < 20) {
          f = ((b & c) | ((~b & 0xffffffff) & d)) & 0xffffffff;
          k = 0x5a827999;
        } else if (i < 40) {
          f = (b ^ c ^ d) & 0xffffffff;
          k = 0x6ed9eba1;
        } else if (i < 60) {
          f = ((b & c) | (b & d) | (c & d)) & 0xffffffff;
          k = 0x8f1bbcdc;
        } else {
          f = (b ^ c ^ d) & 0xffffffff;
          k = 0xca62c1d6;
        }
        final temp = (_rotl32(a, 5) + f + e + k + w[i]) & 0xffffffff;
        e = d;
        d = c;
        c = _rotl32(b, 30);
        b = a;
        a = temp;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
    }

    final out = Uint8List(20);
    final words = [h0, h1, h2, h3, h4];
    for (var i = 0; i < 5; i++) {
      out[i * 4] = (words[i] >> 24) & 0xff;
      out[i * 4 + 1] = (words[i] >> 16) & 0xff;
      out[i * 4 + 2] = (words[i] >> 8) & 0xff;
      out[i * 4 + 3] = words[i] & 0xff;
    }
    return out;
  }

  static String _sha1Hex(String s) => _bytesToHex(_sha1Bytes(Uint8List.fromList(utf8.encode(s))));

  /// RFC 2104 HMAC-SHA1 encoded as Base64.
  static String _hmacSha1Base64(String key, String message) {
    var keyBytes = Uint8List.fromList(utf8.encode(key));
    if (keyBytes.length > 64) {
      keyBytes = _sha1Bytes(keyBytes);
    }
    final blockKey = Uint8List(64);
    blockKey.setRange(0, keyBytes.length, keyBytes);

    final msgBytes = utf8.encode(message);
    final inner = Uint8List(64 + msgBytes.length);
    final outer = Uint8List(64 + 20);
    for (var i = 0; i < 64; i++) {
      inner[i] = blockKey[i] ^ 0x36;
      outer[i] = blockKey[i] ^ 0x5c;
    }
    inner.setRange(64, 64 + msgBytes.length, msgBytes);
    final innerHash = _sha1Bytes(inner);
    outer.setRange(64, 84, innerHash);
    return base64Encode(_sha1Bytes(outer));
  }

  /// FIPS 180-4 SHA-256 hex digest (pure Dart, zero dependencies).
  static String _sha256Hex(String text) {
    const k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    final input = Uint8List.fromList(utf8.encode(text));
    final origLen = input.length;
    final bitLen = origLen * 8;
    final padLen = ((56 - ((origLen + 1) % 64)) + 64) % 64;
    final msg = Uint8List(origLen + 1 + padLen + 8);
    msg.setRange(0, origLen, input);
    msg[origLen] = 0x80;

    final highBits = (bitLen ~/ 0x100000000) & 0xffffffff;
    final lowBits = bitLen & 0xffffffff;
    final lenOff = msg.length - 8;
    msg[lenOff] = (highBits >> 24) & 0xff;
    msg[lenOff + 1] = (highBits >> 16) & 0xff;
    msg[lenOff + 2] = (highBits >> 8) & 0xff;
    msg[lenOff + 3] = highBits & 0xff;
    msg[lenOff + 4] = (lowBits >> 24) & 0xff;
    msg[lenOff + 5] = (lowBits >> 16) & 0xff;
    msg[lenOff + 6] = (lowBits >> 8) & 0xff;
    msg[lenOff + 7] = lowBits & 0xff;

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;
    final w = List<int>.filled(64, 0);

    for (var offset = 0; offset < msg.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] = (msg[j] << 24) | (msg[j + 1] << 16) | (msg[j + 2] << 8) | msg[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr32(w[i - 15], 7) ^ _rotr32(w[i - 15], 18) ^ ((w[i - 15] & 0xffffffff) >> 3);
        final s1 = _rotr32(w[i - 2], 17) ^ _rotr32(w[i - 2], 19) ^ ((w[i - 2] & 0xffffffff) >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final ch = ((e & f) ^ ((~e & 0xffffffff) & g)) & 0xffffffff;
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final maj = ((a & b) ^ (a & c) ^ (b & c)) & 0xffffffff;
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = Uint8List(32);
    final words = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (var i = 0; i < 8; i++) {
      out[i * 4] = (words[i] >> 24) & 0xff;
      out[i * 4 + 1] = (words[i] >> 16) & 0xff;
      out[i * 4 + 2] = (words[i] >> 8) & 0xff;
      out[i * 4 + 3] = words[i] & 0xff;
    }
    return _bytesToHex(out);
  }
}
