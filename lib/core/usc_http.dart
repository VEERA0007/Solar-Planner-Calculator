import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'usc.dart';

/// Base URL of the USC lookup backend, set at build time:
///   flutter build apk --dart-define=USC_BACKEND_URL=https://your-worker.example.workers.dev
/// Empty means no backend: the app keeps working with saved and pasted bills only.
const String kUscBackendUrl = String.fromEnvironment('USC_BACKEND_URL', defaultValue: '');

/// Live USC lookup through the backend.
///
/// Contract (the backend implements this):
///   POST {baseUrl}/api/usc/fetch
///   body:     {"discom": "TGSPDCL", "usc": "102603120", "captchaId": "...", "captcha": "AB12"}
///   200 body: {"consumerName": "...", "address": "...", "fetchedAt": "2026-11-26T10:00:00+05:30",
///              "months": [{"month": "Nov 2026", "units": 310, "bill": 4800, "onPortal": true,
///                          "present": false, "arrears": 0, "paid": 0, "adjust": 0, "balance": 0}]}
///   409 body: {"error": "...", "captchaRequired": true, "captchaId": "...", "image": "data:image/png;base64,..."}
///   other:    {"error": "message shown to the user"} with a non-200 status
class HttpUscSource implements UscSource {
  final String baseUrl;
  final Duration timeout;

  HttpUscSource(this.baseUrl, {this.timeout = const Duration(seconds: 40)});

  /// Only TGSPDCL shows a security code. TGNPDCL and the rest don't.
  @override
  bool needsCaptcha(Discom discom) => discom.code == 'TGSPDCL';

  @override
  Future<UscRecord> fetch({required String usc, required Discom discom, String? captcha, String? captchaId}) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$base/api/usc/fetch');

    final payload = <String, dynamic>{'discom': discom.code, 'usc': usc};
    if (captchaId != null) payload['captchaId'] = captchaId;
    if (captcha != null && captcha.isNotEmpty) payload['captcha'] = captcha;

    http.Response resp;
    try {
      resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(timeout);
    } catch (_) {
      throw const UscException('Could not reach the USC lookup server. Check the internet connection and try again.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw UscException('The lookup server sent an unexpected reply (HTTP ${resp.statusCode}). No bill data was shown.');
    }

    if (resp.statusCode == 409 && body['captchaRequired'] == true) {
      final id = (body['captchaId'] ?? '').toString();
      final image = (body['image'] ?? '').toString();
      throw UscCaptchaRequired(
        (body['error'] as String?) ?? 'Enter the security code shown below.',
        captchaId: id,
        image: image,
      );
    }

    if (resp.statusCode != 200) {
      throw UscException((body['error'] as String?) ?? 'Lookup failed (HTTP ${resp.statusCode}). No bill data was shown.');
    }

    final months = <UscMonth>[];
    for (final m in (body['months'] as List? ?? const [])) {
      final j = m as Map<String, dynamic>;
      months.add(UscMonth(
        month: (j['month'] ?? '').toString(),
        units: _num(j['units']),
        bill: _num(j['bill']),
        arrears: _num(j['arrears']),
        paid: _num(j['paid']),
        adjust: _num(j['adjust']),
        balance: _num(j['balance']),
        onPortal: j['onPortal'] as bool? ?? true,
        present: j['present'] as bool? ?? false,
      ));
    }
    if (months.isEmpty) {
      throw const UscException('The portal returned no bill months for this USC number. No bill data was shown.');
    }

    return UscRecord(
      usc: usc,
      discom: discom,
      consumerName: (body['consumerName'] ?? '').toString(),
      address: (body['address'] ?? '').toString(),
      fetchedAt: DateTime.tryParse((body['fetchedAt'] ?? '').toString()) ?? DateTime.now(),
      months: months,
    );
  }

  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
}

/// Turns the captcha image from the backend into bytes. Accepts a data URL or plain base64.
/// Returns null when the text can't be decoded, so the form shows no image instead of failing.
Uint8List? decodeCaptchaImage(String image) {
  if (image.isEmpty) return null;
  final comma = image.indexOf(',');
  final raw = image.startsWith('data:') && comma >= 0 ? image.substring(comma + 1) : image;
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

/// Picks the live backend when one is configured, otherwise the placeholder that never invents data.
UscSource defaultUscSource() => kUscBackendUrl.isEmpty ? const UnconfiguredUscSource() : HttpUscSource(kUscBackendUrl);
