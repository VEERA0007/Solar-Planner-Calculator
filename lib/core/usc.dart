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

/// DISCOMs offered for the lookup.
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
  final v = cleanUscNumber(raw);
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
  final double adjust;
  final double balance;

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
    this.adjust = 0,
    this.balance = 0,
    this.onPortal = true,
    this.present = false,
  });

  Map<String, dynamic> toJson() => {
        'month': month,
        'units': units,
        'bill': bill,
        'arrears': arrears,
        'paid': paid,
        'adjust': adjust,
        'balance': balance,
        'onPortal': onPortal,
        'present': present,
      };

  factory UscMonth.fromJson(Map<String, dynamic> j) => UscMonth(
        month: j['month'] as String,
        units: (j['units'] as num).toDouble(),
        bill: (j['bill'] as num).toDouble(),
        arrears: (j['arrears'] as num? ?? 0).toDouble(),
        paid: (j['paid'] as num? ?? 0).toDouble(),
        adjust: (j['adjust'] as num? ?? 0).toDouble(),
        balance: (j['balance'] as num? ?? 0).toDouble(),
        onPortal: j['onPortal'] as bool? ?? true,
        present: j['present'] as bool? ?? false,
      );
}

/// One line of the portal's charge breakup, for example "Energy Chg" = 431.20.
class ChargeLine {
  final String label;
  final double amount;
  const ChargeLine(this.label, this.amount);
}

/// The current bill and service details shown on the official bill card.
class BillDetail {
  final String billNo;
  final String ero;
  final String section;
  final String meterNo;
  final String category;
  final String loadPhase;
  final String meterReading;
  final String billDate;
  final String dueDate;
  final String lastPaid;
  final String disconnDate;
  final double billUnits;
  final double billAmount;
  final double totalPayable;
  final List<ChargeLine> charges;

  const BillDetail({
    this.billNo = '',
    this.ero = '',
    this.section = '',
    this.meterNo = '',
    this.category = '',
    this.loadPhase = '',
    this.meterReading = '',
    this.billDate = '',
    this.dueDate = '',
    this.lastPaid = '',
    this.disconnDate = '',
    this.billUnits = 0,
    this.billAmount = 0,
    this.totalPayable = 0,
    this.charges = const [],
  });

  Map<String, dynamic> toJson() => {
        'billNo': billNo,
        'ero': ero,
        'section': section,
        'meterNo': meterNo,
        'category': category,
        'loadPhase': loadPhase,
        'meterReading': meterReading,
        'billDate': billDate,
        'dueDate': dueDate,
        'lastPaid': lastPaid,
        'disconnDate': disconnDate,
        'billUnits': billUnits,
        'billAmount': billAmount,
        'totalPayable': totalPayable,
        'charges': [for (final c in charges) {'label': c.label, 'amount': c.amount}],
      };

  factory BillDetail.fromJson(Map<String, dynamic> j) => BillDetail(
        billNo: j['billNo'] as String? ?? '',
        ero: j['ero'] as String? ?? '',
        section: j['section'] as String? ?? '',
        meterNo: j['meterNo'] as String? ?? '',
        category: j['category'] as String? ?? '',
        loadPhase: j['loadPhase'] as String? ?? '',
        meterReading: j['meterReading'] as String? ?? '',
        billDate: j['billDate'] as String? ?? '',
        dueDate: j['dueDate'] as String? ?? '',
        lastPaid: j['lastPaid'] as String? ?? '',
        disconnDate: j['disconnDate'] as String? ?? '',
        billUnits: (j['billUnits'] as num? ?? 0).toDouble(),
        billAmount: (j['billAmount'] as num? ?? 0).toDouble(),
        totalPayable: (j['totalPayable'] as num? ?? 0).toDouble(),
        charges: [
          for (final c in (j['charges'] as List? ?? const []))
            ChargeLine((c as Map)['label'] as String, (c['amount'] as num).toDouble()),
        ],
      );
}

/// Everything the portal returned for one USC number, plus when it was fetched.
class UscRecord {
  final String usc;
  final Discom discom;
  final String consumerName;
  final String address;
  final DateTime fetchedAt;

  /// Oldest first. Usually 13 months: the 12 used for averages plus one earlier month.
  final List<UscMonth> months;

  /// Current bill details. Null when the portal did not return them.
  final BillDetail? bill;

  const UscRecord({
    required this.usc,
    required this.discom,
    required this.consumerName,
    required this.months,
    required this.fetchedAt,
    this.address = '',
    this.bill,
  });

  /// The most recent 12 months (oldest first). Missing months count as 0.
  List<UscMonth> get last12 => months.length <= 12 ? months : months.sublist(months.length - 12);

  int get missingMonths => last12.where((m) => !m.onPortal).length;

  /// Months on the portal, out of the months in the list.
  int get verifiedMonths => months.where((m) => m.onPortal).length;

  /// Average units per month over the last 12 months, with missing months as 0.
  double get avgUnits => last12.isEmpty ? 0 : totalUnits12 / 12;

  /// Average bill per month over the last 12 months, with missing months as 0.
  double get avgBill => last12.isEmpty ? 0 : totalBill12 / 12;

  double get totalUnits12 => last12.fold<double>(0, (a, m) => a + m.units);
  double get totalBill12 => last12.fold<double>(0, (a, m) => a + m.bill);

  /// Rupees per unit over the 12 months.
  double get blendedRate => totalUnits12 > 0 ? totalBill12 / totalUnits12 : 0;

  Map<String, dynamic> toJson() => {
        'usc': usc,
        'discom': discom.code,
        'name': consumerName,
        'address': address,
        'fetchedAt': fetchedAt.toIso8601String(),
        'months': months.map((m) => m.toJson()).toList(),
        'bill': bill?.toJson(),
      };

  /// Returns null when the saved data is damaged or its DISCOM is no longer known.
  static UscRecord? fromJson(Map<String, dynamic> j) {
    try {
      final d = discomByCode(j['discom'] as String?);
      if (d == null) return null;
      final b = j['bill'];
      return UscRecord(
        usc: j['usc'] as String,
        discom: d,
        consumerName: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        months: (j['months'] as List).map((e) => UscMonth.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        bill: b is Map ? BillDetail.fromJson(Map<String, dynamic>.from(b)) : null,
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
