import 'package:calculator/core/calc.dart';
import 'package:calculator/core/sun.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subsidy slabs', () {
    expect(subsidyFor(1), 30000);
    expect(subsidyFor(2), 60000);
    expect(subsidyFor(3), 78000);
    expect(subsidyFor(10), 78000);
    expect(subsidyFor(0), 0);
  });

  test('USC helpers', () {
    expect(normalizeUsc(' 123-456 789 '), '123456789');
    expect(isValidUsc('123456789'), true);
    expect(isValidUsc('12345'), false);
  });

  test('400 units/month sizing and money', () {
    final r = calculate(EstimateInput(monthlyUnits: 400));
    expect(r.panels, 7);
    expect(r.kw, closeTo(3.78, 1e-9));
    expect(r.subsidy, 78000);
    expect(r.netCost, closeTo(r.cost - 78000, 1e-6));
    expect(r.paybackYears, isNotNull);
    expect(r.paybackYears!, inInclusiveRange(2.0, 8.0));
    expect(r.series.length, 25);
  });

  test('commercial gets no subsidy, bill mode converts to units', () {
    expect(calculate(EstimateInput(category: 'commercial')).subsidy, 0);
    final b = calculate(EstimateInput(mode: 'bill', monthlyBill: 3000, tariff: 7.5));
    expect(b.monthlyUnits.round(), 400);
  });

  test('zero input does not crash', () {
    expect(calculate(EstimateInput(monthlyUnits: 0)).panels, 0);
  });

  test('Indian number format', () {
    expect(groupIndian(1234567), '12,34,567');
    expect(groupIndian(148800), '1,48,800');
    expect(inr(999), 'Rs. 999');
  });

  test('sun position is sensible for Hyderabad', () {
    // 19 Nov 2026 solar noon is about 06:31 UTC (12:01 IST): sun high in the south
    final noon = DateTime.utc(2026, 11, 19, 6, 31);
    final p = solarPosition(noon, 17.385, 78.4867);
    expect(p.alt, greaterThan(50));
    expect(p.az, inInclusiveRange(150.0, 210.0));
    final night = DateTime.utc(2026, 11, 19, 18, 0);
    expect(solarPosition(night, 17.385, 78.4867).alt, lessThan(0));
  });
}
