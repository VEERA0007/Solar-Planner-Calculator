import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The four states covered by the USC lookup.
enum UscRegion {
  telangana('Telangana', 'TG'),
  andhra('Andhra Pradesh', 'AP'),
  odisha('Odisha', 'OD'),
  chhattisgarh('Chhattisgarh', 'CG');

  final String label;
  final String code;
  const UscRegion(this.label, this.code);

  static UscRegion? fromCode(String? c) {
    for (final r in values) {
      if (r.code == c) return r;
    }
    return null;
  }
}

/// One distribution company (DISCOM) inside a state.
class Discom {
  final String code;
  final String name;
  final UscRegion region;
  const Discom(this.code, this.name, this.region);
}

/// DISCOMs offered for the lookup. The user picks the state first, then the DISCOM.
const kDiscoms = <Discom>[
  Discom('TGSPDCL', 'Southern Power Distribution (Hyderabad area)', UscRegion.telangana),
  Discom('TGNPDCL', 'Northern Power Distribution (Warangal / Karimnagar area)', UscRegion.telangana),
  Discom('APSPDCL', 'Southern Power Distribution (Andhra Pradesh)', UscRegion.andhra),
  Discom('APEPDCL', 'Eastern Power Distribution (Visakhapatnam)', UscRegion.andhra),
  Discom('TPCODL', 'Central Odisha Distribution', UscRegion.odisha),
  Discom('TPNODL', 'Northern Odisha Distribution', UscRegion.odisha),
  Discom('TPSODL', 'Southern Odisha Distribution', UscRegion.odisha),
  Discom('TPWODL', 'Western Odisha Distribution', UscRegion.odisha),
  Discom('CSPDCL', 'Chhattisgarh State Power Distribution', UscRegion.chhattisgarh),
];

List<Discom> discomsFor(UscRegion r) => kDiscoms.where((d) => d.region == r).toList();

Discom? discomByCode(String? code) {
  for (final d in kDiscoms) {
    if (d.code == code) return d;
  }
  return null;
}

/// USC numbers are 8 to 12 digits. Spaces are ignored.
String? validateUsc(String raw) {
  final v = raw.replaceAll(RegExp(r'\s'), '');
  if (v.isEmpty) return 'Enter the USC number';
  if (!RegExp(r'^\d+$').hasMatch(v)) return 'USC number has digits only';
  if (v.length < 8 || v.length > 12) return 'USC number is 8 to 12 digits';
  return null;
}

String cleanUscNumber(String raw) => raw.replaceAll(RegExp(r'\s'), '');

/// One billing month as returned by the portal.
class UscMonth {
  /// Label as shown on the bill, for example "Nov 2026".
  final String month;
  final double units;
  final double bill;
  final double arrears;
  final double paid;

  /// False when the portal had no figure for this month. Units and bill are 0 then.
  final bool onPortal;

  /// True for the current, unpaid bill.
  final bool present;

  const UscMonth({
    required this.month,
    required this.units,
    required this.bill,
    this.arrears = 0,
    this.paid = 0,
    this.onPortal = true,
    this.present = false,
  });

  Map<String, dynamic> toJson() => {
        'month': month,
        'units': units,
        'bill': bill,
        'arrears': arrears,
        'paid': paid,
        'onPortal': onPortal,
        'present': present,
      };

  factory UscMonth.fromJson(Map<String, dynamic> j) => UscMonth(
        month: j['month'] as String,
        units: (j['units'] as num).toDouble(),
        bill: (j['bill'] as num).toDouble(),
        arrears: (j['arrears'] as num? ?? 0).toDouble(),
        paid: (j['paid'] as num? ?? 0).toDouble(),
        onPortal: j['onPortal'] as bool? ?? true,
        present: j['present'] as bool? ?? false,
      );
}

/// Everything the portal returned for one USC number, plus when it was fetched.
class UscRecord {
  final String usc;
  final Discom discom;
  final String consumerName;
  final String address;
  final String category;
  final String loadText;
  final DateTime fetchedAt;

  /// Oldest first.
  final List<UscMonth> months;

  const UscRecord({
    required this.usc,
    required this.discom,
    required this.consumerName,
    required this.months,
    required this.fetchedAt,
    this.address = '',
    this.category = '',
    this.loadText = '',
  });

  /// The most recent 12 months (oldest first). Missing months count as 0.
  List<UscMonth> get last12 => months.length <= 12 ? months : months.sublist(months.length - 12);

  int get missingMonths => last12.where((m) => !m.onPortal).length;

  /// Average units per month over the last 12 months, with missing months as 0.
  double get avgUnits => last12.isEmpty ? 0 : last12.fold<double>(0, (a, m) => a + m.units) / 12;

  /// Average bill per month over the last 12 months, with missing months as 0.
  double get avgBill => last12.isEmpty ? 0 : last12.fold<double>(0, (a, m) => a + m.bill) / 12;

  double get totalUnits12 => last12.fold<double>(0, (a, m) => a + m.units);
  double get totalBill12 => last12.fold<double>(0, (a, m) => a + m.bill);

  Map<String, dynamic> toJson() => {
        'usc': usc,
        'discom': discom.code,
        'name': consumerName,
        'address': address,
        'category': category,
        'load': loadText,
        'fetchedAt': fetchedAt.toIso8601String(),
        'months': months.map((m) => m.toJson()).toList(),
      };

  /// Returns null when the saved data is damaged or its DISCOM is no longer known.
  static UscRecord? fromJson(Map<String, dynamic> j) {
    try {
      final d = discomByCode(j['discom'] as String?);
      if (d == null) return null;
      return UscRecord(
        usc: j['usc'] as String,
        discom: d,
        consumerName: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        category: j['category'] as String? ?? '',
        loadText: j['load'] as String? ?? '',
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        months: (j['months'] as List).map((e) => UscMonth.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Error the UI shows as a message. [message] is safe to display.
class UscException implements Exception {
  final String message;
  const UscException(this.message);
  @override
  String toString() => message;
}

/// Where the data comes from. The live portal connector implements this per DISCOM.
abstract class UscSource {
  /// Throws [UscException] with a readable message when data can't be fetched.
  Future<UscRecord> fetch({required String usc, required Discom discom, String? captcha});

  /// True when this DISCOM needs the user to type the captcha shown by the portal.
  bool needsCaptcha(Discom discom);
}

/// Used until a portal connector is configured for a DISCOM. It never invents data.
class UnconfiguredUscSource implements UscSource {
  const UnconfiguredUscSource();

  @override
  bool needsCaptcha(Discom discom) => true;

  @override
  Future<UscRecord> fetch({required String usc, required Discom discom, String? captcha}) async {
    throw UscException('${discom.code} lookup is not connected yet. No bill data was shown.');
  }
}

/// Saved USC lookups on this device.
class UscStore {
  static const _key = 'usc_records';

  static Future<List<UscRecord>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => UscRecord.fromJson(Map<String, dynamic>.from(e as Map))).whereType<UscRecord>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<UscRecord> records) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(records.map((r) => r.toJson()).toList()));
    } catch (_) {
      // Saving is a convenience. The screen still works without it.
    }
  }
}
