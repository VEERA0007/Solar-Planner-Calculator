import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'store_consts.dart';

/// Location-specific long-term average daily peak sun hours per month
/// (kWh/m2/day), cached for 30 days. Falls back to the built-in curve scaled
/// by latitude so the number still differs by place when offline.
class MonthlyPsh {
  final List<double> psh; // 12 values, Jan..Dec
  final bool fetched;
  const MonthlyPsh(this.psh, this.fetched);

  double forMonth(int month) => psh[(month - 1).clamp(0, 11)];
  double get annual => psh.fold(0.0, (a, b) => a + b) / 12;
}

List<double> fallbackPsh(double lat) {
  // Scale the Hyderabad curve by a simple latitude factor (higher lat -> less sun).
  final k = (1.0 - (lat.abs() - 17.4) * 0.012).clamp(0.7, 1.15);
  return [for (final v in kMonthPshHyd) double.parse((v * k).toStringAsFixed(2))];
}

Future<MonthlyPsh> loadMonthlyPsh(double lat, double lon, {bool force = false}) async {
  final key = 'psh_${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}';
  SharedPreferences? p;
  try {
    p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    final at = p.getInt('${key}_at') ?? 0;
    if (!force && raw != null && DateTime.now().millisecondsSinceEpoch - at < 30 * 86400000) {
      final l = (jsonDecode(raw) as List).map((e) => (e as num).toDouble()).toList();
      if (l.length == 12) return MonthlyPsh(l, true);
    }
  } catch (_) {}
  try {
    final u = Uri.parse('https://power.larc.nasa.gov/api/temporal/climatology/point'
        '?parameters=ALLSKY_SFC_SW_DWN&community=RE&longitude=$lon&latitude=$lat&format=JSON');
    final r = await http.get(u).timeout(const Duration(seconds: 12));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final m = j['properties']['parameter']['ALLSKY_SFC_SW_DWN'] as Map<String, dynamic>;
      const names = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
      final l = [for (final n in names) (m[n] as num).toDouble()];
      if (l.every((v) => v > 0 && v < 12)) {
        try {
          p?.setString(key, jsonEncode(l));
          p?.setInt('${key}_at', DateTime.now().millisecondsSinceEpoch);
        } catch (_) {}
        return MonthlyPsh(l, true);
      }
    }
  } catch (_) {}
  return MonthlyPsh(fallbackPsh(lat), false);
}
