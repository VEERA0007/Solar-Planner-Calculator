import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:calculator/core/usc.dart';
import 'package:calculator/ui/theme.dart';
import 'package:calculator/ui/usc_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo source for screenshots only. Returns fake sample data (reference-shaped
/// numbers), clearly named as sample, so the layout can be checked without a portal.
class _SampleSource implements UscSource {
  @override
  bool needsCaptcha(Discom discom) => true;

  @override
  Future<UscRecord> fetch({required String usc, required Discom discom, String? captcha}) async {
    const names = [
      'Nov 2025', 'Dec 2025', 'Jan 2026', 'Feb 2026', 'Mar 2026', 'Apr 2026', 'May 2026',
      'Jun 2026', 'Jul 2026', 'Aug 2026', 'Sep 2026', 'Oct 2026', 'Nov 2026',
    ];
    const units = <double>[116, 116, 114, 122, 106, 93, 110, 112, 111, 122, 114, 136, 119];
    const bills = <double>[541.0, 535, 518, 558, 475, 324, 496.61, 504, 498, 557, 517, 624, 546];
    final months = [
      for (var i = 0; i < names.length; i++)
        UscMonth(
          month: names[i],
          units: units[i],
          bill: bills[i],
          arrears: 100,
          paid: 0,
          adjust: -bills[i],
          balance: -100,
          present: i == names.length - 1,
        ),
    ];
    return UscRecord(
      usc: usc,
      discom: discom,
      consumerName: 'SAMPLE CONSUMER',
      address: 'Sample address, sample area',
      fetchedAt: DateTime.now(),
      months: months,
      bill: const BillDetail(
        billNo: '22512',
        ero: 'SAMPLE ERO',
        section: 'SAMPLE SEC',
        meterNo: '00000000',
        category: '(B)(i)-Domestic',
        loadPhase: '0.24 kW · 1-Phase',
        meterReading: '7724 → 7843 (31d)',
        billDate: '02-11-2026',
        dueDate: '16-11-2026',
        lastPaid: '27-02-2024',
        disconnDate: '30-11-2026',
        billUnits: 119,
        billAmount: 546,
        totalPayable: 546,
        charges: [
          ChargeLine('Energy Chg', 431.20),
          ChargeLine('Fixed Chg', 14.90),
          ChargeLine('Customer Chg', 90.00),
          ChargeLine('Elec. Duty', 7.14),
          ChargeLine('True-Up (2022-23)', 2.70),
          ChargeLine('Loss/Gain', 0.03),
        ],
      ),
    );
  }
}

final _shotKey = GlobalKey();

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final byFamily = <String, List<File>>{};
  for (final f in dir.listSync().whereType<File>()) {
    final n = f.uri.pathSegments.last;
    if (!n.endsWith('.ttf') && !n.endsWith('.otf')) continue;
    byFamily.putIfAbsent(n.split('-').first, () => []).add(f);
  }
  for (final e in byFamily.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    }
    await loader.load();
  }
}

Future<void> _shot(WidgetTester t, String name) async {
  final dir = Directory('screenshots')..createSync(recursive: true);
  await t.runAsync(() async {
    final b = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget _app(UscSource source, {bool dark = false}) => RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark),
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: UscSection(source: source, onApply: (_) {}),
            ),
          ),
        ),
      ),
    );

void _phone(WidgetTester t, {double height = 860}) {
  t.view.physicalSize = Size(400 * 2.5, height * 2.5);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  testWidgets('usc section: form, then sample result with ledger', (t) async {
    _phone(t, height: 2600);
    await t.pumpWidget(_app(_SampleSource()));
    await t.pumpAndSettle();
    await _shot(t, 'usc-a-form-empty');

    await t.enterText(find.byType(TextField).first, '110325672');
    await t.enterText(find.byType(TextField).at(1), 'ABC12');
    await t.pumpAndSettle();
    await t.tap(find.text('Fetch Govt Bill'));
    await t.pumpAndSettle();
    await _shot(t, 'usc-b-result');

    await t.tap(find.text('Show 13-Mo DISCOM Bills'));
    await t.pumpAndSettle();
    await _shot(t, 'usc-c-ledger');
    expect(find.text('Govt DISCOM Bills'), findsOneWidget);
    expect(find.textContaining('Synced (12-Mo Avg'), findsOneWidget);
  });

  testWidgets('usc section: no connector shows a clear message, not data', (t) async {
    _phone(t);
    await t.pumpWidget(_app(const UnconfiguredUscSource()));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '110325672');
    await t.enterText(find.byType(TextField).at(1), 'ABC12');
    await t.tap(find.text('Fetch Govt Bill'));
    await t.pumpAndSettle();
    await _shot(t, 'usc-d-not-connected');
    expect(find.textContaining('not connected yet'), findsOneWidget);
    expect(find.textContaining('Synced (12-Mo Avg'), findsNothing);
  });
}
