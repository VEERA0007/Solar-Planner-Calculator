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
  InverterBrandOption('solarman', 'Solarman (Deye and Solarman loggers)'),
  InverterBrandOption('growatt', 'Growatt ShineServer'),
  InverterBrandOption('sungrow', 'Sungrow iSolarCloud'),
  InverterBrandOption('goodwe', 'GoodWe SEMS'),
];

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

/// Logs in to the manufacturer portal through the backend and returns the result.
abstract class InverterSyncSource {
  Future<InverterSyncResult> sync({
    required String brand,
    required String username,
    required String password,
    String? stationId,
  });
}

class HttpInverterSync implements InverterSyncSource {
  final String baseUrl;
  HttpInverterSync(this.baseUrl);

  @override
  Future<InverterSyncResult> sync({
    required String brand,
    required String username,
    required String password,
    String? stationId,
  }) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$base/api/inverter/portal-sync');
    final payload = <String, dynamic>{
      'brand': brand,
      'authMode': 'website',
      'username': username,
      'password': password,
      if (stationId != null && stationId.isNotEmpty) 'stationId': stationId,
    };

    http.Response resp;
    try {
      resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
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
}

/// Null when no backend URL was given at build time.
InverterSyncSource? defaultInverterSync() => kUscBackendUrl.isEmpty ? null : HttpInverterSync(kUscBackendUrl);
