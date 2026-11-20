import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:calculator/core/store.dart';
import 'package:calculator/main.dart' show Shell;
import 'package:calculator/ui/sun_art.dart';
import 'package:calculator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final shotKey = GlobalKey();

class Harness extends StatelessWidget {
  final AppState s;
  const Harness(this.s, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) => RepaintBoundary(key: shotKey, child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(s.isDark(DateTime.now())),
          builder: (c, child) {
            final mq = MediaQuery.of(c);
            return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(autoTextScale(mq))), child: child!);
          },
          home: Shell(state: s),
        )),
      );
}

Future<void> _shot(WidgetTester t, String name) async {
  final dir = Directory('screenshots')..createSync(recursive: true);
  await t.runAsync(() async {
    final b = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
        appName: 'Solar Planner', packageName: 'com.solarplanner.calculator', version: '0.0.7', buildNumber: '1', buildSignature: '');
    await _loadFonts();
  });

  const sizes = <String, Size>{'phone-small': Size(360, 700), 'phone': Size(412, 915), 'tablet': Size(820, 1180), 'desktop': Size(1280, 800)};

  for (final entry in sizes.entries) {
    for (final dark in [false, true]) {
      testWidgets('home ${entry.key} ${dark ? 'night' : 'day'} has no layout errors', (t) async {
        SharedPreferences.setMockInitialValues({});
        final s = AppState();
        await t.runAsync(() => s.load());
        s.prefs.dark = dark;
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(Harness(s));
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
        await _shot(t, 'home-${entry.key}-${dark ? 'night' : 'day'}');
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('settings and profile dialogs open and save', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await t.runAsync(() => s.load());
    s.prefs.dark = false;
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(Harness(s));
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.byIcon(Icons.settings_outlined).first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await _shot(t, 'settings-display');
    await t.tap(find.text('Tariffs & Grid'));
    await t.pumpAndSettle();
    await _shot(t, 'settings-tariffs');
    await t.tap(find.text('Alerts'));
    await t.pumpAndSettle();
    await _shot(t, 'settings-alerts');
    await t.tap(find.text('Save Settings'));
    await t.pumpAndSettle();

    // profile
    await t.tap(find.byIcon(Icons.person));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.enterText(find.byType(TextField).first, 'Test Owner');
    await _shot(t, 'profile-owner');
    await t.tap(find.text('Solar Specs'));
    await t.pumpAndSettle();
    await _shot(t, 'profile-specs');
    await t.tap(find.text('Save Profile'));
    await t.pumpAndSettle();
    expect(s.profile.name, 'Test Owner');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('scenic art at several sun positions', (t) async {
    t.view.physicalSize = const Size(900, 330);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget art(bool night, double p) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AspectRatio(aspectRatio: 320 / 190, child: CustomPaint(painter: SunArtPainter(night: night, t: p, dark: night))),
          ),
        );
    await t.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF888888),
          child: Column(children: [
            Expanded(child: Row(children: [art(false, .1), art(false, .5), art(false, .9)])),
            Expanded(child: Row(children: [art(true, .1), art(true, .5), art(true, .9)])),
          ]),
        ),
      ),
    ));
    await _shot(t, 'art-positions');
  });

  test('arc progress follows the sun and the night', () {
    final rise = DateTime(2026, 11, 20, 6, 0), set = DateTime(2026, 11, 20, 18, 0);
    expect(arcProgress(DateTime(2026, 11, 20, 12), rise, set, night: false), closeTo(.5, 1e-9));
    expect(arcProgress(DateTime(2026, 11, 20, 9), rise, set, night: false), closeTo(.25, 1e-9));
    expect(arcProgress(DateTime(2026, 11, 20, 21), rise, set, night: false), 1.0);
    expect(arcProgress(DateTime(2026, 11, 20, 3), rise, set, night: false), 0.0);
    // night path: sunset 18:00 -> sunrise 06:00 next day, midnight is the middle
    expect(arcProgress(DateTime(2026, 11, 21, 0), rise, set, night: true), closeTo(.5, 1e-9));
    expect(arcProgress(DateTime(2026, 11, 20, 3), rise, set, night: true), closeTo(.75, 1e-9));
  });

  testWidgets('language switch changes navigation labels', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await t.runAsync(() => s.load());
    s.prefs.lang = 'hi';
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(Harness(s));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('होम'), findsWidgets);
    expect(find.text('Home'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
