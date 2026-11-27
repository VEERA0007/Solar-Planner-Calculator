import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'usc_http.dart' show kUscBackendUrl;

/// Inverter brands the Worker can log in to. 'auto' tries each portal in turn.
class InverterBrandOption {
  final String id;
  final String label;
  const InverterBrandOption(this.id, this.label);
}

const kInverterBrands = <InverterBrandOption>[
  InverterBrandOption('auto', 'Auto-detect'),
  InverterBrandOption('soliscloud', 'SolisCloud (Ginlong Solis)'),
  InverterBrandOption('solarman', 'Solarman (Deye / V-Sole / Sofar)'),
  InverterBrandOption('growatt', 'Growatt ShineServer'),
  InverterBrandOption('sungrow', 'Sungrow iSolarCloud'),
  InverterBrandOption('goodwe', 'GoodWe SEMS'),
];

/// How the app reaches the inverter's data. Matches the connection modes in the web app.
enum InverterConnectMode {
  cloudPortal('Cloud portal login'),
  localLogger('Local Wi-Fi logger (same home Wi-Fi)'),
  bridge('HTTPS bridge (Home Assistant or tunnel)');

  final String label;
  const InverterConnectMode(this.label);
}

/// One plant on the portal account. Pick one when the account has several.
class InverterPlant {
  final String stationId;
  final String name;
  final double? capacityKwp;
  final String? status;
  const InverterPlant({required this.stationId, required this.name, this.capacityKwp, this.status});
}

/// Result of one sync. Only the fields the screen shows are kept.
class InverterSyncResult {
  final bool ok;
  final String? error;
  final String? providerName;
  final bool needsPlant;
  final List<InverterPlant> plants;
  final String? plantName;
  final String? model;
  final double? todayGenKwh;
  final double? livePowerKw;
  final double? lifetimeKwh;
  final String? syncedAtIst;
  final String? statusNote;

  const InverterSyncResult({
    required this.ok,
    this.error,
    this.providerName,
    this.needsPlant = false,
    this.plants = const [],
    this.plantName,
    this.model,
    this.todayGenKwh,
    this.livePowerKw,
    this.lifetimeKwh,
    this.syncedAtIst,
    this.statusNote,
  });

  /// Used when the request itself failed. Shows the message and no data.
  factory InverterSyncResult.failed(String message) => InverterSyncResult(ok: false, error: message);

  factory InverterSyncResult.fromJson(Map<String, dynamic> j) {
    final telemetry = j['telemetry'] is Map ? Map<String, dynamic>.from(j['telemetry'] as Map) : const <String, dynamic>{};
    final ext = j['extendedTelemetry'] is Map ? Map<String, dynamic>.from(j['extendedTelemetry'] as Map) : const <String, dynamic>{};
    final rawPlants = j['discoveredPlants'] is List ? j['discoveredPlants'] as List : const [];
    final plants = <InverterPlant>[
      for (final p in rawPlants)
        if (p is Map && (p['stationId'] ?? '').toString().isNotEmpty)
          InverterPlant(
            stationId: p['stationId'].toString(),
            name: (p['plantName'] ?? 'Plant').toString(),
            capacityKwp: _num(p['capacityKwp']),
            status: p['status']?.toString(),
          ),
    ];
    final ok = j['ok'] == true;
    final err = (j['error'] ?? '').toString();
    return InverterSyncResult(
      ok: ok,
      error: ok ? null : (err.isEmpty ? 'The portal did not return data. No data was shown.' : err),
      providerName: j['providerName']?.toString(),
      needsPlant: j['requiresPlantSelection'] == true,
      plants: plants,
      plantName: j['detectedPlantName']?.toString(),
      model: (j['detectedModelName'] ?? ext['inverterModel'])?.toString(),
      todayGenKwh: _num(telemetry['todayGenKwh']),
      livePowerKw: _num(telemetry['livePowerKw']),
      lifetimeKwh: _num(telemetry['lifetimeKwh']),
      syncedAtIst: telemetry['syncedAtIst']?.toString(),
      statusNote: telemetry['statusNote']?.toString(),
    );
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v == null) return null;
    return double.tryParse(v.toString());
  }
}

/// Reaches the inverter in one of the three connection modes.
abstract class InverterSyncSource {
  /// Cloud portal login through the Worker. Credentials are used once and not stored.
  Future<InverterSyncResult> sync({
    required String brand,
    required String username,
    required String password,
    String? stationId,
  });

  /// Local Wi-Fi logger. The phone reads the logger page on the home network, then the
  /// Worker parses the page text. Logger login (if any) goes only to the logger.
  Future<InverterSyncResult> syncLocalLogger({
    required String brand,
    required String loggerAddress,
    String? username,
    String? password,
  });

  /// HTTPS bridge (Home Assistant or a public tunnel). Optional login goes to the bridge.
  Future<InverterSyncResult> syncBridge({
    required String brand,
    required String bridgeUrl,
    String? username,
    String? password,
  });
}

class HttpInverterSync implements InverterSyncSource {
  final String baseUrl;
  HttpInverterSync(this.baseUrl);

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Future<InverterSyncResult> _post(String path, Map<String, dynamic> payload) async {
    http.Response resp;
    try {
      resp = await http
          .post(Uri.parse('$_base$path'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      return InverterSyncResult.failed('Could not reach the sync server. Check the connection and try again.');
    }
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return InverterSyncResult.fromJson(body);
    } catch (_) {
      return InverterSyncResult.failed('The sync server sent an unexpected reply (HTTP ${resp.statusCode}). No data was shown.');
    }
  }

  @override
  Future<InverterSyncResult> sync({
    required String brand,
    required String username,
    required String password,
    String? stationId,
  }) {
    return _post('/api/inverter/portal-sync', {
      'brand': brand,
      'authMode': 'website',
      'username': username,
      'password': password,
      if (stationId != null && stationId.isNotEmpty) 'stationId': stationId,
    });
  }

  @override
  Future<InverterSyncResult> syncBridge({
    required String brand,
    required String bridgeUrl,
    String? username,
    String? password,
  }) {
    return _post('/api/inverter/bridge-sync', {
      'brand': brand,
      'bridgeUrl': bridgeUrl.trim(),
      if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
      if (password != null && password.isNotEmpty) 'password': password,
    });
  }

  /// Turns "192.168.1.50", "http://192.168.1.50" or a full status-page URL into the URLs to try.
  static List<String>? loggerCandidates(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null; // never keep logins in the address
    final base = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    final hasPath = uri.path.isNotEmpty && uri.path != '/';
    return hasPath ? [uri.toString()] : ['$base/status.html', '$base/status_a.html', '$base/inverter.json'];
  }

  @override
  Future<InverterSyncResult> syncLocalLogger({
    required String brand,
    required String loggerAddress,
    String? username,
    String? password,
  }) async {
    final candidates = loggerCandidates(loggerAddress);
    if (candidates == null) {
      return InverterSyncResult.failed('Enter a valid logger address, for example 192.168.1.50.');
    }
    final headers = <String, String>{};
    final user = username?.trim() ?? '';
    if (user.isNotEmpty) {
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$user:${password ?? ''}'))}';
    }

    var lastError = 'Could not reach the logger. Check that this phone is on the same home Wi-Fi.';
    for (final url in candidates) {
      http.Response resp;
      try {
        resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 5));
      } on TimeoutException {
        lastError = 'The logger did not answer in time. Check the address and that this phone is on the same Wi-Fi.';
        continue;
      } catch (_) {
        continue;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return InverterSyncResult.failed(
          'The logger rejected the login (HTTP ${resp.statusCode}). Check the Wi-Fi stick username and password. Solis sticks often default to admin / admin.',
        );
      }
      if (resp.statusCode != 200) {
        lastError = 'The logger returned HTTP ${resp.statusCode} on $url.';
        continue;
      }
      return _post('/api/inverter/parse-logger', {
        'brand': brand,
        'text': resp.body,
      });
    }
    return InverterSyncResult.failed(lastError);
  }
}

/// Null when no backend URL was given at build time.
InverterSyncSource? defaultInverterSync() => kUscBackendUrl.isEmpty ? null : HttpInverterSync(kUscBackendUrl);
