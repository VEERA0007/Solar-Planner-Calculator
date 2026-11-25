import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:calculator/core/usc.dart';
import 'package:calculator/ui/theme.dart';
import 'package:calculator/ui/usc_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo source for screenshots only. It returns obviously fake sample data,
/// so the screen can be seen without a live portal connection.
class _SampleSource implements UscSource {
  @override
  bool needsCaptcha(Discom discom) => true;

  @override
  Future<UscRecord> fetch({required String usc, required Discom discom, String? captcha}) async {
    const vals = [
      [116, 541.0], [116, 535.0], [114, 518.0], [122, 558.0], [106, 475.0], [93, 324.0],
      [110, 496.61], [112, 504.0], [111, 498.0], [122, 557.0], [114, 517.0], [136, 624.0], [119, 546.0],
    ];
    const names = [
      'Nov 2025', 'Dec 2025', 'Jan 2026', 'Feb 2026', 'Mar 2026', 'Apr 2026', 'May 2026',
      'Jun 2026', 'Jul 2026', 'Aug 2026', 'Sep 2026', 'Oct 2026', 'Nov 2026',
    ];
    final months = [
      for (var i = 0; i < vals.length; i++)
        UscMonth(
          month: names[i],
          units: vals[i][0].toDouble(),
          bill: vals[i][1] as double,
          present: i == vals.length - 1,
        ),
    ];
    return UscRecord(
      usc: usc,
      discom: discom,
      consumerName: 'SAMPLE DATA (not from portal)',
      address: 'Sample address',
      months: months,
      fetchedAt: DateTime.now(),
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

Widget _app(UscSource source) => RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(false),
        home: UscPage(source: source),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  testWidgets('usc screen: start, then choose state and DISCOM', (t) async {
    t.view.physicalSize = const Size(400 * 2.5, 860 * 2.5);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(_SampleSource()));
    await t.pumpAndSettle();
    await _shot(t, 'usc-1-start-night');

    await t.tap(find.text('Telangana'));
    await t.pumpAndSettle();
    await t.tap(find.text('TGSPDCL'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '110325672');
    await t.enterText(find.byType(TextField).at(1), 'ABC12');
    await t.pumpAndSettle();
    await _shot(t, 'usc-2-form-filled');

    await t.tap(find.text('Fetch 12-month bills'));
    await t.pumpAndSettle();
    await _shot(t, 'usc-3-result');
    expect(find.textContaining('12-MO AVG UNITS'), findsOneWidget);
    expect(find.text('115 kWh'), findsOneWidget);
  });

  testWidgets('usc screen: no connector shows a clear message, not data', (t) async {
    t.view.physicalSize = const Size(400 * 2.5, 860 * 2.5);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const UnconfiguredUscSource()));
    await t.pumpAndSettle();
    await t.tap(find.text('Telangana'));
    await t.pumpAndSettle();
    await t.tap(find.text('TGSPDCL'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '110325672');
    await t.enterText(find.byType(TextField).at(1), 'ABC12');
    await t.tap(find.text('Fetch 12-month bills'));
    await t.pumpAndSettle();
    await _shot(t, 'usc-4-not-connected');
    expect(find.textContaining('not connected yet'), findsOneWidget);
    expect(find.textContaining('12-MO AVG UNITS'), findsNothing);
  });
}
