import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- service log

enum ServiceType { cleaning, inverter, electrical, general }

class ServiceEntry {
  String id, title, technician, notes, soiling;
  ServiceType type;
  DateTime date;
  DateTime? nextDue;
  double yieldGain, cost;
  ServiceEntry({
    required this.id,
    required this.type,
    required this.date,
    this.title = '',
    this.technician = '',
    this.notes = '',
    this.soiling = 'moderate',
    this.nextDue,
    this.yieldGain = 0,
    this.cost = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type.name, 'date': date.millisecondsSinceEpoch, 'title': title,
        'technician': technician, 'notes': notes, 'soiling': soiling,
        'nextDue': nextDue?.millisecondsSinceEpoch, 'yieldGain': yieldGain, 'cost': cost,
      };

  factory ServiceEntry.fromJson(Map<String, dynamic> j) => ServiceEntry(
        id: (j['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
        type: ServiceType.values.firstWhere((e) => e.name == j['type'], orElse: () => ServiceType.general),
        date: DateTime.fromMillisecondsSinceEpoch((j['date'] as num?)?.toInt() ?? 0),
        title: (j['title'] as String?) ?? '',
        technician: (j['technician'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
        soiling: (j['soiling'] as String?) ?? 'moderate',
        nextDue: j['nextDue'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['nextDue'] as num).toInt()),
        yieldGain: (j['yieldGain'] as num?)?.toDouble() ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
      );
}

/// Typical output lost to dust: about 0.16 % per day without rain, capped.
double soilingLossPct(int daysSinceWash) => math.min(25.0, math.max(0, daysSinceWash) * 0.16);

String isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ------------------------------------------------------------------ geometry

/// Fixed tilts for a latitude (degrees, magnitude), as used on the Seasonal Tilt page.
({int annual, int summer, int equinox, int winter}) seasonalTilts(double lat) {
  final l = lat.abs();
  return (
    annual: (l + 0.5).round(),
    summer: math.max(0, (l - 12).round()),
    equinox: l.round(),
    winter: math.min(90, (l + 15).round()),
  );
}

/// Solar-noon altitude on the solstices and equinox (degrees), folded to 0-90.
({double summer, double equinox, double winter}) noonAltitudes(double lat) {
  double fold(double v) => v > 90 ? 180 - v : v;
  final l = lat.abs();
  // Summer solstice for the hemisphere the site is in.
  return (summer: fold(90 - l + 23.44), equinox: 90 - l, winter: fold(90 - l - 23.44).abs());
}

/// Single-axis (horizontal, north-south axis) rotation: positive = facing west.
double singleAxisAngle(double alt, double az) {
  if (alt <= 0) return 0;
  final zen = (90 - alt) * math.pi / 180;
  final rel = (az - 180) * math.pi / 180;
  return math.atan2(math.sin(zen) * math.sin(rel), math.cos(zen)) * 180 / math.pi;
}

// ------------------------------------------------------------------- weather

class WeatherNow {
  final double tempC, uv, cloud, ghi;
  final bool rain;
  const WeatherNow(this.tempC, this.uv, this.cloud, this.ghi, this.rain);
}

Future<WeatherNow?> fetchWeatherNow(double lat, double lon) async {
  try {
    final u = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,cloud_cover,precipitation,shortwave_radiation&daily=uv_index_max&forecast_days=1&timezone=auto');
    final r = await http.get(u).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final c = j['current'] as Map<String, dynamic>;
    double d(Object? v) => (v is num) ? v.toDouble() : 0.0;
    final uvList = (j['daily']?['uv_index_max'] as List?) ?? const [];
    return WeatherNow(d(c['temperature_2m']), uvList.isEmpty ? 0 : d(uvList.first), d(c['cloud_cover']), d(c['shortwave_radiation']), d(c['precipitation']) > 0);
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------------------- space weather

class KpBlock {
  final DateTime time;
  final double kp;
  const KpBlock(this.time, this.kp);
}

class SpaceWx {
  final double? f107;
  final String? flareClass; // e.g. "C2.1"
  final int? regions;
  final double? kp;
  final List<KpBlock> kpHistory;
  final double? pC, pM, pX; // 24-hour flare probabilities, %
  final DateTime fetched;
  final bool cached;
  const SpaceWx({this.f107, this.flareClass, this.regions, this.kp, this.kpHistory = const [], this.pC, this.pM, this.pX, required this.fetched, this.cached = false});

  bool get hasAny => f107 != null || kp != null || flareClass != null;

  Map<String, dynamic> toJson() => {
        'f107': f107, 'flare': flareClass, 'regions': regions, 'kp': kp, 'at': fetched.millisecondsSinceEpoch,
        'hist': [for (final b in kpHistory) [b.time.millisecondsSinceEpoch, b.kp]], 'pC': pC, 'pM': pM, 'pX': pX,
      };

  factory SpaceWx.fromJson(Map<String, dynamic> j, {bool cached = false}) => SpaceWx(
        f107: (j['f107'] as num?)?.toDouble(),
        flareClass: j['flare'] as String?,
        regions: (j['regions'] as num?)?.toInt(),
        kp: (j['kp'] as num?)?.toDouble(),
        kpHistory: [
          for (final e in (j['hist'] as List? ?? const []))
            KpBlock(DateTime.fromMillisecondsSinceEpoch((e[0] as num).toInt()), (e[1] as num).toDouble())
        ],
        pC: (j['pC'] as num?)?.toDouble(),
        pM: (j['pM'] as num?)?.toDouble(),
        pX: (j['pX'] as num?)?.toDouble(),
        fetched: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
        cached: cached,
      );
}

/// X-ray flux (W/m2, 0.1-0.8 nm) -> flare class such as "C2.1".
String flareClassOf(double flux) {
  if (flux <= 0) return 'A0.0';
  const letters = ['A', 'B', 'C', 'M', 'X'];
  const base = [1e-8, 1e-7, 1e-6, 1e-5, 1e-4];
  var i = 0;
  for (var k = 0; k < base.length; k++) {
    if (flux >= base[k]) i = k;
  }
  return '${letters[i]}${(flux / base[i]).toStringAsFixed(1)}';
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

/// Aurora equatorward boundary (geomagnetic latitude) for a Kp value.
double auroraCutoffLat(double kp) => (66.5 - 2.04 * kp.clamp(0, 9)).clamp(48.0, 66.5).toDouble();

Future<SpaceWx> fetchSpaceWeather() async {
  const base = 'https://services.swpc.noaa.gov';
  Future<dynamic> get(String path) async {
    try {
      final r = await http.get(Uri.parse('$base$path')).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return null;
  }

  final res = await Future.wait([
    get('/json/f107_cm_flux.json'),
    get('/products/noaa-planetary-k-index.json'),
    get('/json/goes/primary/xrays-6-hour.json'),
    get('/json/solar_probabilities.json'),
    get('/json/solar_regions.json'),
  ]);

  double? f107;
  if (res[0] is List && (res[0] as List).isNotEmpty) {
    for (final e in (res[0] as List).reversed) {
      final v = e is Map ? _num(e['flux']) : null;
      if (v != null && v > 0) {
        f107 = v;
        break;
      }
    }
  }
  final hist = <KpBlock>[];
  if (res[1] is List) {
    for (final row in (res[1] as List)) {
      if (row is List && row.length >= 2) {
        final k = _num(row[1]);
        final t = DateTime.tryParse('${row[0]}'.replaceFirst(' ', 'T') + (('${row[0]}').endsWith('Z') ? '' : 'Z'));
        if (k != null && t != null) hist.add(KpBlock(t.toLocal(), k));
      }
    }
  }
  final last8 = hist.length > 8 ? hist.sublist(hist.length - 8) : hist;
  String? flare;
  if (res[2] is List) {
    for (final e in (res[2] as List).reversed) {
      if (e is Map && '${e['energy']}'.contains('0.1-0.8')) {
        final v = _num(e['flux']);
        if (v != null && v > 0) {
          flare = flareClassOf(v);
          break;
        }
      }
    }
  }
  double? pC, pM, pX;
  if (res[3] is List && (res[3] as List).isNotEmpty && (res[3] as List).first is Map) {
    final m = (res[3] as List).first as Map;
    pC = _num(m['c_class_1_day']);
    pM = _num(m['m_class_1_day']);
    pX = _num(m['x_class_1_day']);
  }
  int? regions;
  if (res[4] is List && (res[4] as List).isNotEmpty) {
    final list = (res[4] as List).whereType<Map>().toList();
    final latest = list.map((e) => '${e['observed_date']}').fold('', (a, b) => b.compareTo(a) > 0 ? b : a);
    regions = list.where((e) => '${e['observed_date']}' == latest).map((e) => '${e['region']}').toSet().length;
  }
  final wx = SpaceWx(
    f107: f107, flareClass: flare, regions: regions, kp: last8.isEmpty ? null : last8.last.kp,
    kpHistory: last8, pC: pC, pM: pM, pX: pX, fetched: DateTime.now(),
  );
  try {
    final p = await SharedPreferences.getInstance();
    if (wx.hasAny) {
      await p.setString('space_wx', jsonEncode(wx.toJson()));
    } else {
      final raw = p.getString('space_wx');
      if (raw != null) return SpaceWx.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>(), cached: true);
    }
  } catch (_) {}
  return wx;
}
