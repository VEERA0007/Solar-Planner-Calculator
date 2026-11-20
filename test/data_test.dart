import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/core/geo.dart';
import 'package:calculator/core/i18n.dart';
import 'package:calculator/core/tariff.dart';

void main() {
  test('plus code matches the Open Location Code reference', () {
    expect(plusCode(47.365590, 8.524997), '8FVC9G8F+6X');
    expect(plusCodeShort(17.4239, 78.4738), 'CFFF+HG7');
  });

  final book = TariffBook.parse(File('data/tariffs.json').readAsStringSync());

  test('tariff file has the four states and their grids', () {
    expect(book.states.map((s) => s.id), ['andhra_pradesh', 'telangana', 'odisha', 'chhattisgarh']);
    expect(book.byId('telangana').discoms.length, 2);
    expect(book.byId('odisha').discoms.length, 4);
    expect(book.byId('telangana').exportRate, 3.80);
    expect(book.detect('Telangana')!.id, 'telangana');
    expect(book.detect('Orissa')!.id, 'odisha');
    expect(book.detect('Karnataka'), isNull);
  });

  test('telescopic slab bill, marginal rate and label', () {
    final d = book.byId('telangana').cat('domestic');
    expect(d.bill(250), closeTo(200 * 5.10 + 50 * 7.70, 1e-9));
    expect(d.marginal(250), 7.70);
    expect(d.slabLabel(250), 'Slab 200-300 Units / Month');
    expect(d.scheduleFor(80).slabs.first.rate, 1.95); // <=100 units schedule
    expect(d.bill(0), 0);
  });

  test('bill to units round trip', () {
    final d = book.byId('andhra_pradesh').cat('domestic');
    final units = d.unitsForBill(d.bill(310));
    expect(units, closeTo(310, 0.01));
  });

  test('every state has all three categories with increasing slabs', () {
    for (final s in book.states) {
      for (final c in ['domestic', 'commercial', 'industrial']) {
        final cat = s.cat(c);
        for (final sc in cat.schedules) {
          double prev = 0;
          for (final sl in sc.slabs) {
            if (sl.upTo != null) {
              expect(sl.upTo! > prev, isTrue, reason: '${s.id}/$c');
              prev = sl.upTo!;
            }
            expect(sl.rate > 0, isTrue);
          }
        }
      }
    }
  });

  test('every language has every key', () {
    for (final l in kLangs.keys) {
      for (final k in ['home', 'settings', 'unit_price', 'save_profile', 'warranty']) {
        expect(tr(l, k).isNotEmpty, isTrue);
        expect(tr(l, k) == k, isFalse);
      }
    }
    expect(tr('te', 'home'), 'హోమ్');
  });
}
