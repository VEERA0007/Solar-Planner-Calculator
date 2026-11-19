import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

const double _rad = math.pi / 180;

class SunPos {
  final double alt; // degrees above horizon
  final double az; // degrees clockwise from north
  const SunPos(this.alt, this.az);
}

SunPos solarPosition(DateTime date, double lat, double lon) {
  final n = date.millisecondsSinceEpoch / 86400000 + 2440587.5 - 2451545.0;
  final l = (280.46 + 0.9856474 * n) % 360;
  final g = ((357.528 + 0.9856003 * n) % 360) * _rad;
  final lam = (l + 1.915 * math.sin(g) + 0.02 * math.sin(2 * g)) * _rad;
  final eps = (23.439 - 0.0000004 * n) * _rad;
  final dec = math.asin(math.sin(eps) * math.sin(lam));
  final ra = math.atan2(math.cos(eps) * math.sin(lam), math.cos(lam));
  final gmst = (((280.46061837 + 360.98564736629 * n) % 360) + 360) % 360;
  final ha = (((gmst + lon) % 360) * _rad) - ra;
  final phi = lat * _rad;
  final alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(ha));
  final az = math.atan2(math.sin(ha), math.cos(ha) * math.sin(phi) - math.tan(dec) * math.cos(phi)) + math.pi;
  return SunPos(alt / _rad, (((az / _rad) % 360) + 360) % 360);
}

String compass(double az) {
  const names = ['North', 'North-East', 'East', 'South-East', 'South', 'South-West', 'West', 'North-West'];
  return names[(az / 45).round() % 8];
}

class DayInfo {
  final DateTime? rise, noon, set;
  final double maxAlt;
  const DayInfo(this.rise, this.noon, this.set, this.maxAlt);
}

/// Sunrise, solar noon and sunset for the local calendar day of [date].
DayInfo dayInfo(DateTime date, double lat, double lon) {
  final start = DateTime(date.year, date.month, date.day);
  DateTime? rise, set, noon;
  var best = -90.0;
  for (var m = 0; m < 1440; m++) {
    final t = start.add(Duration(minutes: m));
    final a = solarPosition(t, lat, lon).alt;
    if (a > best) {
      best = a;
      noon = t;
    }
    if (a > 0) {
      rise ??= t;
      set = t;
    }
  }
  return DayInfo(rise, noon, set, best);
}

/// Clear-sky GHI / DNI in W/m2 (Meinel + Kasten-Young airmass with a haze factor).
({double ghi, double dni}) clearSky(double alt) {
  if (alt <= 0) return (ghi: 0.0, dni: 0.0);
  final s = math.sin(alt * _rad);
  final am = 1 / (s + 0.50572 * math.pow(alt + 6.07995, -1.6364));
  final dni = 1353 * math.pow(0.7, math.pow(am, 0.678)) * 0.8;
  return (ghi: dni * s + 0.1 * dni * s + 20 * s, dni: dni.toDouble());
}

List<double> modelHourly(DateTime date, double lat, double lon) {
  final day = DateTime(date.year, date.month, date.day);
  return List.generate(24, (h) {
    final t = day.add(Duration(minutes: h * 60 + 30));
    return clearSky(solarPosition(t, lat, lon).alt).ghi;
  });
}

class Irradiance {
  final List<double> hourly; // 24 values, W/m2
  final double ghi, dni, cloud;
  final bool live;
  const Irradiance(this.hourly, this.ghi, this.dni, this.cloud, this.live);

  double get psh => hourly.fold(0.0, (s, v) => s + v) / 1000;
}

Irradiance modelIrradiance(DateTime now, double lat, double lon) {
  final c = clearSky(solarPosition(now, lat, lon).alt);
  return Irradiance(modelHourly(now, lat, lon), c.ghi, c.dni, 0, false);
}

/// Live data from Open-Meteo; falls back to the clear-sky model when offline.
Future<Irradiance> fetchIrradiance(double lat, double lon, [DateTime? at]) async {
  final now = at ?? DateTime.now();
  try {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=shortwave_radiation,direct_normal_irradiance,cloud_cover'
        '&hourly=shortwave_radiation&forecast_days=1&timezone=auto');
    final r = await http.get(uri).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw Exception('http ${r.statusCode}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final hourlyRaw = (j['hourly']?['shortwave_radiation'] as List?) ?? const [];
    final cur = j['current'] as Map<String, dynamic>?;
    if (hourlyRaw.length < 24 || cur == null) throw Exception('bad payload');
    double d(Object? v) => (v is num) ? v.toDouble() : 0.0;
    return Irradiance(
      hourlyRaw.take(24).map(d).toList(),
      d(cur['shortwave_radiation']),
      d(cur['direct_normal_irradiance']),
      d(cur['cloud_cover']),
      true,
    );
  } catch (_) {
    return modelIrradiance(now, lat, lon);
  }
}

String skyLabel(double cloud) => cloud < 20 ? 'Clear sky / Optimal' : (cloud < 60 ? 'Partly cloudy' : 'Overcast');
