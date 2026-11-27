import 'dart:convert';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Open Location Code ("plus code") encoder.
const _alphabet = '23456789CFGHJMPQRVWX';

String plusCode(double lat, double lng, {int length = 10}) {
  lat = lat.clamp(-90.0, 90.0);
  if (lat >= 90) lat = 90 - 0.000001;
  lng = ((lng + 180) % 360) - 180;
  var latVal = ((lat + 90) * 40000).floor();
  var lngVal = ((lng + 180) * 32000).floor();
  final grid = _alphabet[(latVal % 5) * 4 + (lngVal % 4)];
  latVal ~/= 5;
  lngVal ~/= 4;
  final pairs = List<String>.filled(10, '');
  for (var i = 4; i >= 0; i--) {
    pairs[i * 2 + 1] = _alphabet[lngVal % 20];
    pairs[i * 2] = _alphabet[latVal % 20];
    latVal ~/= 20;
    lngVal ~/= 20;
  }
  final j = pairs.join();
  return '${j.substring(0, 8)}+${j.substring(8)}${length > 10 ? grid : ''}';
}

/// Short form (drops the 4-char area prefix), e.g. "CFFF+HG7".
String plusCodeShort(double lat, double lng) {
  final c = plusCode(lat, lng, length: 11);
  return c.substring(4);
}

class Place {
  final double lat, lng;
  final String city, locality, region, postcode;
  const Place(this.lat, this.lng, this.city, this.locality, this.region, this.postcode);

  String get subtitle {
    final parts = <String>[];
    for (final p in [locality, city]) {
      if (p.isNotEmpty && !parts.contains(p)) parts.add(p);
    }
    final loc = parts.isEmpty ? region : parts.join(', ');
    return loc.isEmpty ? plusCodeShort(lat, lng) : '${plusCodeShort(lat, lng)}, $loc';
  }
}

/// Asks for location once per install, when the app starts. Later starts only read the
/// permission state, so the system prompt never comes back on its own.
Future<void> askLocationOnceAtStart() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('locationAskedV1') ?? false) return;
    await prefs.setBool('locationAskedV1', true);
    if (!await Geolocator.isLocationServiceEnabled()) return;
    if (await Geolocator.checkPermission() == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  } catch (_) {}
}

/// [ask] is true only when the user taps "Use my location", so the prompt appears on that tap.
Future<Place?> currentPlace({bool ask = false}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low))
        .timeout(const Duration(seconds: 12));
    return await reverse(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

Future<Place> reverse(double lat, double lng, {String lang = 'en'}) async {
  try {
    final u = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client'
        '?latitude=$lat&longitude=$lng&localityLanguage=$lang');
    final r = await http.get(u).timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      String s(String k) => ((j[k] as String?) ?? '').trim();
      final city = s('city').isNotEmpty ? s('city') : s('locality');
      return Place(lat, lng, city, s('locality'), s('principalSubdivision'), s('postcode'));
    }
  } catch (_) {}
  return Place(lat, lng, '', '', '', '');
}

class GeoHit {
  final String name, region;
  final double lat, lng;
  const GeoHit(this.name, this.region, this.lat, this.lng);
}

Future<List<GeoHit>> searchPlaces(String q) async {
  if (q.trim().length < 2) return [];
  try {
    final u = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q.trim(), 'count': '8', 'language': 'en', 'format': 'json', 'countryCode': 'IN'});
    final r = await http.get(u).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return [];
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return [
      for (final e in (j['results'] as List? ?? []))
        GeoHit(e['name'] ?? '', (e['admin1'] ?? '') as String, (e['latitude'] as num).toDouble(),
            (e['longitude'] as num).toDouble())
    ];
  } catch (_) {
    return [];
  }
}

double distanceKm(double la1, double lo1, double la2, double lo2) {
  const r = 6371.0;
  final dLa = (la2 - la1) * math.pi / 180, dLo = (lo2 - lo1) * math.pi / 180;
  final a = math.pow(math.sin(dLa / 2), 2) +
      math.cos(la1 * math.pi / 180) * math.cos(la2 * math.pi / 180) * math.pow(math.sin(dLo / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
