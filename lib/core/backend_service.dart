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
