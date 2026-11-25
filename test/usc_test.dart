import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/core/usc.dart';

/// Bills from the reference portal screens (BODLA NARSIMHA, TGSPDCL).
/// Oldest first, Nov 2025 through Nov 2026 (13 months).
final _reference = <UscMonth>[
  const UscMonth(month: 'Nov 2025', units: 116, bill: 541),
  const UscMonth(month: 'Dec 2025', units: 116, bill: 535),
  const UscMonth(month: 'Jan 2026', units: 114, bill: 518),
  const UscMonth(month: 'Feb 2026', units: 122, bill: 558),
  const UscMonth(month: 'Mar 2026', units: 106, bill: 475),
  const UscMonth(month: 'Apr 2026', units: 93, bill: 324),
  const UscMonth(month: 'May 2026', units: 110, bill: 496.61),
  const UscMonth(month: 'Jun 2026', units: 112, bill: 504),
  const UscMonth(month: 'Jul 2026', units: 111, bill: 498),
  const UscMonth(month: 'Aug 2026', units: 122, bill: 557),
  const UscMonth(month: 'Sep 2026', units: 114, bill: 517),
  const UscMonth(month: 'Oct 2026', units: 136, bill: 624),
  const UscMonth(month: 'Nov 2026', units: 119, bill: 546, present: true),
];

UscRecord _record(List<UscMonth> months) => UscRecord(
      usc: '110325672',
      discom: discomByCode('TGSPDCL')!,
      consumerName: 'BODLA NARSIMHA',
      months: months,
      fetchedAt: DateTime(2026, 11, 25, 7, 10),
    );

void main() {
  group('USC number', () {
    test('accepts 8 to 12 digits and ignores spaces', () {
      expect(validateUsc('110325672'), isNull);
      expect(validateUsc('1103 2567'), isNull);
      expect(validateUsc('12345678'), isNull);
      expect(validateUsc('123456789012'), isNull);
    });

    test('rejects empty, short, long and non-digit values', () {
      expect(validateUsc(''), isNotNull);
      expect(validateUsc('1234567'), isNotNull);
      expect(validateUsc('1234567890123'), isNotNull);
      expect(validateUsc('11032A672'), isNotNull);
    });

    test('normalizes spaces', () {
      expect(cleanUscNumber(' 1103 2567 '), '11032567');
    });
  });

  group('DISCOMs', () {
    test('every state has at least one DISCOM', () {
      for (final r in UscRegion.values) {
        expect(discomsFor(r), isNotEmpty, reason: r.label);
      }
    });

    test('codes are unique and map back to their state', () {
      final codes = kDiscoms.map((d) => d.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final d in kDiscoms) {
        expect(discomByCode(d.code)?.region, d.region);
      }
    });

    test('unknown DISCOM code gives null', () {
      expect(discomByCode('NOPE'), isNull);
      expect(UscRegion.fromCode('XX'), isNull);
    });
  });

  group('12-month summary matches the reference screens', () {
    final r = _record(_reference);

    test('last 12 months exclude the oldest month', () {
      expect(r.last12.length, 12);
      expect(r.last12.first.month, 'Dec 2025');
      expect(r.last12.last.month, 'Nov 2026');
    });

    test('total units are 1,375 kWh and average is 115 kWh a month', () {
      expect(r.totalUnits12, 1375);
      expect(r.avgUnits.round(), 115);
    });

    test('total bill is ₹6,152.61 and average is ₹513 a month', () {
      expect(r.totalBill12.toStringAsFixed(2), '6152.61');
      expect(r.avgBill.round(), 513);
    });

    test('no missing months when every month is on the portal', () {
      expect(r.missingMonths, 0);
    });
  });

  group('missing months', () {
    test('a month not on the portal counts as 0 and is reported', () {
      final months = [..._reference];
      months[5] = const UscMonth(month: 'Apr 2026', units: 0, bill: 0, onPortal: false);
      final r = _record(months);
      expect(r.missingMonths, 1);
      expect(r.totalUnits12, 1375 - 93);
      expect(r.avgUnits, closeTo((1375 - 93) / 12, 0.0001));
    });

    test('fewer than 12 months: average still divides by 12', () {
      final r = _record(_reference.sublist(0, 6));
      expect(r.last12.length, 6);
      expect(r.missingMonths, 0);
      expect(r.avgUnits, closeTo(r.totalUnits12 / 12, 0.0001));
    });

    test('no months at all gives zero averages', () {
      final r = _record(const []);
      expect(r.avgUnits, 0);
      expect(r.avgBill, 0);
    });
  });

  group('saved record round trip', () {
    test('toJson then fromJson keeps the data', () {
      final r = _record(_reference);
      final back = UscRecord.fromJson(Map<String, dynamic>.from(r.toJson()));
      expect(back, isNotNull);
      expect(back!.usc, r.usc);
      expect(back.discom.code, 'TGSPDCL');
      expect(back.months.length, r.months.length);
      expect(back.avgUnits, closeTo(r.avgUnits, 0.0001));
      expect(back.avgBill, closeTo(r.avgBill, 0.0001));
      expect(back.months.last.present, isTrue);
    });

    test('damaged saved data is skipped, not thrown', () {
      expect(UscRecord.fromJson({'usc': '1'}), isNull);
      expect(UscRecord.fromJson({'usc': '1', 'discom': 'NOPE', 'fetchedAt': '2026-01-01', 'months': []}), isNull);
    });
  });

  group('source', () {
    test('the default source never invents bill data', () async {
      const src = UnconfiguredUscSource();
      expect(src.needsCaptcha(discomByCode('TGSPDCL')!), isTrue);
      expect(
        () => src.fetch(usc: '110325672', discom: discomByCode('TGSPDCL')!, captcha: 'abc'),
        throwsA(isA<UscException>()),
      );
    });
  });
}
