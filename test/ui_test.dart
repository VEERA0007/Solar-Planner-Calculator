import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:calculator/core/store.dart';
import 'package:calculator/main.dart' show Shell;
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

class Harness extends StatelessWidget {
  final AppState s;
  const Harness(this.s, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(s.isDark(DateTime.now())),
          builder: (c, child) {
            final mq = MediaQuery.of(c);
            return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(autoTextScale(mq))), child: child!);
          },
          home: Shell(state: s),
        ),
      );
}

Future<void> _shot(WidgetTester t, String name) async {
  final dir = Directory('screenshots')..createSync(recursive: true);
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
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
    await t.tap(find.text('★★★'));
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
