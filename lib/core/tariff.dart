import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// One telescopic slab: units up to [upTo] (null = no limit) cost [rate] each.
class Slab {
  final double? upTo;
  final double rate;
  const Slab(this.upTo, this.rate);
}

/// A set of slabs that applies when total monthly units are <= [max].
class Schedule {
  final double? max;
  final List<Slab> slabs;
  const Schedule(this.max, this.slabs);
}

class CategoryTariff {
  final String label;
  final List<Schedule> schedules;
  const CategoryTariff(this.label, this.schedules);

  Schedule scheduleFor(double units) {
    for (final s in schedules) {
      if (s.max == null || units <= s.max!) return s;
    }
    return schedules.last;
  }

  /// Energy charge (Rs) for a month with [units] consumption.
  double bill(double units) {
    if (units <= 0) return 0;
    final s = scheduleFor(units);
    double left = units, prev = 0, total = 0;
    for (final sl in s.slabs) {
      final cap = sl.upTo == null ? double.infinity : sl.upTo! - prev;
      final take = left < cap ? left : cap;
      total += take * sl.rate;
      left -= take;
      prev = sl.upTo ?? prev;
      if (left <= 0) break;
    }
    return total;
  }

  /// Rate of the last unit consumed (what one more unit costs).
  double marginal(double units) {
    final s = scheduleFor(units <= 0 ? 1 : units);
    double prev = 0;
    for (final sl in s.slabs) {
      if (sl.upTo == null || units <= sl.upTo!) return sl.rate;
      prev = sl.upTo!;
    }
    return s.slabs.last.rate;
  }

  /// Average Rs per unit.
  double average(double units) => units <= 0 ? marginal(1) : bill(units) / units;

  /// Human label such as "Slab 200-400 Units / Month".
  String slabLabel(double units) {
    final s = scheduleFor(units);
    double prev = 0;
    for (final sl in s.slabs) {
      if (sl.upTo == null || units <= sl.upTo!) {
        return sl.upTo == null
            ? 'Slab ${prev.round()}+ Units / Month'
            : 'Slab ${prev.round()}-${sl.upTo!.round()} Units / Month';
      }
      prev = sl.upTo!;
    }
    return '';
  }

  /// Monthly units that produce a given energy-charge [amount].
  double unitsForBill(double amount) {
    if (amount <= 0) return 0;
    double lo = 0, hi = 20000;
    for (var i = 0; i < 60; i++) {
      final mid = (lo + hi) / 2;
      if (bill(mid) < amount) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }
}

class Discom {
  final String id, name, coverage, url;
  const Discom(this.id, this.name, this.coverage, this.url);
}

class StateTariff {
  final String id;
  final Map<String, String> names;
  final List<String> match;
  final double pr;
  final double? exportRate;
  final String order, effective;
  final List<Discom> discoms;
  final Map<String, CategoryTariff> categories;
  const StateTariff(this.id, this.names, this.match, this.pr, this.exportRate,
      this.order, this.effective, this.discoms, this.categories);

  String name(String lang) => names[lang] ?? names['en'] ?? id;
  CategoryTariff cat(String c) => categories[c] ?? categories['domestic']!;
}

class TariffBook {
  final String version;
  final List<StateTariff> states;
  const TariffBook(this.version, this.states);

  StateTariff byId(String id) =>
      states.firstWhere((s) => s.id == id, orElse: () => states.first);

  /// Finds a state from a reverse-geocoded region name, or null.
  StateTariff? detect(String region) {
    final r = region.toLowerCase();
    for (final s in states) {
      if (s.match.any(r.contains)) return s;
    }
    return null;
  }

  static TariffBook parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    double? d(dynamic v) => v is num ? v.toDouble() : null;
    final states = <StateTariff>[];
    for (final s in (j['states'] as List)) {
      final m = s as Map<String, dynamic>;
      final cats = <String, CategoryTariff>{};
      (m['tariff'] as Map<String, dynamic>).forEach((k, v) {
        final c = v as Map<String, dynamic>;
        cats[k] = CategoryTariff(
          c['label'] as String,
          [
            for (final sc in (c['schedules'] as List))
              Schedule(d(sc['max']), [
                for (final sl in (sc['slabs'] as List))
                  Slab(d(sl['upTo']), d(sl['rate'])!)
              ])
          ],
        );
      });
      states.add(StateTariff(
        m['id'] as String,
        Map<String, String>.from(m['names'] as Map),
        List<String>.from(m['match'] as List),
        d(m['pr']) ?? 79.2,
        d(m['exportRate']),
        (m['order'] ?? '') as String,
        (m['effective'] ?? '') as String,
        [
          for (final x in (m['discoms'] as List))
            Discom(x['id'], x['name'], x['coverage'], x['url'])
        ],
        cats,
      ));
    }
    return TariffBook((j['version'] ?? '') as String, states);
  }

  static const remoteUrl =
      'https://raw.githubusercontent.com/VEERA0007/Solar-Planner-Calculator/main/data/tariffs.json';

  /// Bundled tariffs, replaced by a newer published file when reachable.
  static Future<TariffBook> load({String? cached, void Function(String)? onFresh}) async {
    var book = parse(await rootBundle.loadString('data/tariffs.json'));
    if (cached != null) {
      try {
        final c = parse(cached);
        if (c.version.compareTo(book.version) > 0) {
          book = c;
        }
      } catch (_) {}
    }
    try {
      final r = await http.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final n = parse(r.body);
        if (n.version.compareTo(book.version) > 0) {
          book = n;
          onFresh?.call(r.body);
        }
      }
    } catch (_) {}
    return book;
  }
}
