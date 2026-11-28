import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:calculator/core/appliance_data.dart';
import 'package:calculator/ui/appliance_page.dart';
import 'package:calculator/core/service_data.dart';
import 'package:calculator/core/store.dart';
import 'package:calculator/ui/service_level.dart';
import 'package:calculator/ui/service_space.dart';
import 'package:calculator/main.dart' show Shell;
import 'package:calculator/ui/sun_scene.dart';
import 'package:calculator/core/roof.dart';
import 'package:calculator/core/update.dart';
import 'package:calculator/ui/theme.dart';
import 'package:calculator/ui/update_dialog.dart';
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
    LevelTab.disableSensor = true;
    SunScene.animate = false; // keeps pumpAndSettle finite
    PackageInfo.setMockInitialValues(
        appName: 'Solar Planner', packageName: 'com.solarplanner.calculator', version: '0.0.7', buildNumber: '1', buildSignature: '');
    await _loadFonts();
    await SunScenePainter.preload();
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

  // Estimator tab (USC panel, auto-synced electricity rate) at every size, with no overflow.
  for (final entry in sizes.entries) {
    testWidgets('estimator ${entry.key} has no layout errors', (t) async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState();
      await t.runAsync(() => s.load());
      s.prefs.dark = false;
      t.view.physicalSize = entry.value;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(Harness(s));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Estimator').last);
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final dark in [false, true]) {
    testWidgets('service tab pages ${dark ? 'night' : 'day'} have no layout errors', (t) async {
      SharedPreferences.setMockInitialValues({});
      SpaceTab.testPreset = SpaceWx(
        f107: 158, flareClass: 'C2.1', regions: 6, kp: 2.67, pC: 90, pM: 35, pX: 5, fetched: DateTime.now(),
        kpHistory: [for (var i = 0; i < 8; i++) KpBlock(DateTime(2026, 11, 21, i * 3), [2.0, 2.3, 3.0, 2.7, 3.3, 2.3, 2.0, 2.7][i])],
      );
      addTearDown(() => SpaceTab.testPreset = null);
      final s = AppState();
      await t.runAsync(() => s.load());
      s.prefs.dark = dark;
      s.profile
        ..name = 'Test Owner'
        ..inverter = 'Growatt 3.3kW'
        ..panel = 'Waaree 550W Mono'
        ..helpline = '+91 98450 12345'
        ..commission = '18/04/2025';
      s.services = [
        ServiceEntry(id: '1', type: ServiceType.cleaning, date: DateTime.now().subtract(const Duration(days: 40)), title: 'Post-Monsoon Deep Cleaning & Rinsing', technician: 'GreenSun Solar Care', yieldGain: 7.4, cost: 800, notes: 'De-ionized water wash.', nextDue: DateTime.now().add(const Duration(days: 20))),
        ServiceEntry(id: '2', type: ServiceType.inverter, date: DateTime.now().subtract(const Duration(days: 120)), title: 'Bi-Annual Inverter Health & DC String Check', technician: 'Rajesh Sharma', soiling: 'healthy', cost: 1200, notes: 'Voc and Isc within 2%.', nextDue: DateTime.now().add(const Duration(days: 60))),
      ];
      t.view.physicalSize = const Size(412, 915);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(Harness(s));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Service').last);
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      final n = dark ? 'night' : 'day';
      await _shot(t, 'service-maint-$n');
      await t.tap(find.text('+ Log Wash'));
      await t.pumpAndSettle();
      await _shot(t, 'service-log-$n');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView).last, const Offset(0, -600));
      await t.pump(const Duration(milliseconds: 500));
      await _shot(t, 'service-maint2-$n');
      await t.tap(find.text('Tilt & Angles'));
      await t.pump(const Duration(seconds: 1));
      await _shot(t, 'service-tilt-curve-$n');
      await t.tap(find.text('Seasonal Tilt'));
      await t.pump(const Duration(seconds: 1));
      await _shot(t, 'service-tilt-season-$n');
      await t.tap(find.text('Trackers (1X/2X)'));
      await t.pump(const Duration(seconds: 1));
      await _shot(t, 'service-tilt-track-$n');
      await t.tap(find.text('Bubble Level'));
      await t.pump(const Duration(seconds: 2));
      await _shot(t, 'service-level-$n');
      await t.tap(find.text('Space Weather'));
      await t.pump(const Duration(seconds: 1));
      await _shot(t, 'service-space-flux-$n');
      await t.tap(find.text('Kp-Index'));
      await t.pump(const Duration(seconds: 1));
      await _shot(t, 'service-space-kp-$n');
      await t.tap(find.text('Sun Report'));
      await t.pump(const Duration(seconds: 1));
      await _shot(t, 'service-space-sun-$n');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }


  for (final dark in [false, true]) {
    testWidgets('appliance analysis flow ${dark ? 'night' : 'day'} has no layout errors', (t) async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState();
      await t.runAsync(() => s.load());
      s.prefs.dark = dark;
      t.view.physicalSize = const Size(412, 3400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(Harness(s));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Appliance Analysis').last);
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      final n = dark ? 'night' : 'day';
      await _shot(t, 'appl-top-$n');
      await t.tap(find.text('Industrial').first);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Off-Grid').first);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField).at(0), '4');
      await t.pump();
      await t.tap(find.text('Calculate Application & View System Options'));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await _shot(t, 'appl-offgrid-$n');
      expect(s.applHistory.length, 1);
      await t.tap(find.byKey(const ValueKey('history-btn')));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      expect(find.textContaining('Calculation History'), findsOneWidget);
      await _shot(t, 'appl-history-$n');
      await t.pageBack();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Hybrid System'), warnIfMissed: false); // first tap also drops the field focus
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('On-Grid System'), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      await _shot(t, 'appl-ongrid-$n');
      expect(s.appl.sys, SysType.onGrid);
      for (var i = 0; i < 8 && find.textContaining('in Estimator').evaluate().isEmpty; i++) {
        await t.drag(find.descendant(of: find.byType(AppliancePage), matching: find.byType(ListView)).first, const Offset(0, -3000));
        await t.pump(const Duration(milliseconds: 300));
      }
      await _shot(t, 'appl-bom-$n');
      await t.tap(find.textContaining('in Estimator'));
      await t.pump(const Duration(seconds: 1));
      expect(s.tab, 1);
      expect(t.takeException(), isNull);
      await _shot(t, 'appl-estimator-$n');
      await t.pumpWidget(const SizedBox());
    });
  }

  test('system sizing matches the reference numbers', () {
    OptionCase(SysType t) => buildOption(type: t, dailyKwh: 19.26, connectedKw: 3.57, yieldPerKwp: 2.77, tariff: 9.5, dcr: true, profile: LoadProfile.industrial, backupHours: 0);
    final on = OptionCase(SysType.onGrid), hy = OptionCase(SysType.hybrid), off = OptionCase(SysType.offGrid);
    expect(on.panels < hy.panels && hy.panels < off.panels, isTrue);
    expect(on.subsidy, 0); // industrial gets no residential subsidy
    final res = buildOption(type: SysType.onGrid, dailyKwh: 16.8, connectedKw: 3.57, yieldPerKwp: 3.0, tariff: 8, dcr: true, profile: LoadProfile.residential, backupHours: 0);
    expect(res.subsidy, 78000);
    expect(centralSubsidy(2), 60000);
    final bomOn = buildBom(on, dcr: true, profile: LoadProfile.industrial);
    final bomOff = buildBom(off, dcr: true, profile: LoadProfile.industrial);
    expect(bomOn.removed.length, 3);
    expect(bomOff.removed.length, 1);
    expect(bomOff.items.length > bomOn.items.length, isTrue);
    expect(rupee(386100), '₹386,100');
  });

  for (final dark in [false, true]) {
    testWidgets('update dialog ${dark ? 'night' : 'day'} downloads and installs', (t) async {
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final pending = Completer<String?>();
      var installed = '';
      const info = UpdateInfo(137, 'Solar Planner 0.0.7 (build 137)', 'https://example.com/a.apk', 'https://example.com', size: 95200000);
      await t.pumpWidget(RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(dark),
          home: Scaffold(
            body: Center(
              child: UpdateDialog(
                info: info,
                currentLabel: 'v0.0.7 · 136',
                canDownload: true,
                downloader: (url, size, onProgress, cancel) {
                  onProgress(48400000, 95200000);
                  return pending.future;
                },
                installer: (p) async {
                  installed = p;
                  return 'The installer is open. Tap Install to finish updating.';
                },
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('v0.0.7 · 137'), findsOneWidget);
      await _shot(t, 'update-ready-${dark ? 'night' : 'day'}');
      await t.tap(find.text('Update now'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Downloading...'), findsOneWidget);
      expect(find.text('51%'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await _shot(t, 'update-downloading-${dark ? 'night' : 'day'}');
      pending.complete('/tmp/a.apk');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Download complete'), findsOneWidget);
      expect(installed, '/tmp/a.apk');
      await _shot(t, 'update-done-${dark ? 'night' : 'day'}');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final dark in [false, true]) {
    testWidgets('estimator flow ${dark ? 'night' : 'day'} has no layout errors', (t) async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState();
      await t.runAsync(() => s.load());
      s.prefs.dark = dark;
      t.view.physicalSize = const Size(412, 3400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(Harness(s));
      await t.pump(const Duration(seconds: 1));
      s.setTab(1);
      await t.pump(const Duration(seconds: 1));
      final n = dark ? 'night' : 'day';
      expect(find.text('Solar Estimator'), findsWidgets);
      await _shot(t, 'est-form-$n');
      await t.tap(find.text('Calculate the Solar System'));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await _shot(t, 'est-results-$n');
      await t.tap(find.text('ROI Dashboard'));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await _shot(t, 'est-roi-$n');
      await t.tap(find.text('Full Savings Page'));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await _shot(t, 'est-page-$n');
      await t.tap(find.text('Existing Plant'));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await _shot(t, 'est-existing-$n');
      await t.tap(find.text('Generation'));
      await t.pump(const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await _shot(t, 'est-generation-$n');
      await t.pumpWidget(const SizedBox());
    });
  }

  test('roof layout packs panels inside the outline and writes a DXF', () {
    // a 10 m x 6 m roof
    const roof = [Pt(0, 0), Pt(10, 0), Pt(10, 6), Pt(0, 6)];
    expect(polygonArea(roof), closeTo(60, 1e-9));
    final l = layoutPanels(roof, longMm: 2278, shortMm: 1134, gapMm: 25, rowGapMm: 450, setbackMm: 500);
    expect(l.count, greaterThan(4));
    for (final p in l.panels) {
      for (final q in p) {
        expect(pointInPolygon(q, roof), true);
        expect(distToPolygonEdge(q, roof), greaterThanOrEqualTo(.5 - 1e-6));
      }
    }
    final tight = layoutPanels(roof, longMm: 2278, shortMm: 1134, setbackMm: 3500);
    expect(tight.count, 0);
    expect(roofDxf(roof, l), contains('ROOF_BOUNDARY'));
    final pr = RoofProjection(17.385, 78.4867);
    final pt = pr.toLocal(17.3851, 78.4868);
    final back = pr.toLatLon(pt);
    expect(back.$1, closeTo(17.3851, 1e-9));
    expect(back.$2, closeTo(78.4868, 1e-9));
  });

  test('critical load, surge, limits, BOM total and history signature', () {
    const items = [
      LoadItem('LED Bulb', 10, 10, 6, 18),
      LoadItem('Ceiling Fan', 75, 4, 10, 18, backup: true),
      LoadItem('Split AC 1.5 Ton', 1500, 1, 8, 20),
    ];
    final st = analyzeLoad(items, 1.0);
    expect(st.hourly.length, 24);
    expect(st.criticalKw, closeTo(0.3, 1e-9));
    expect(st.surgeKw, greaterThan(st.connectedKw));
    expect(st.dayShare, inInclusiveRange(0, 1));
    expect(st.dailyKwh, closeTo(items.fold(0.0, (a, e) => a + e.kwhDay), 1e-6));
    final cfg = ApplCfg(sys: SysType.hybrid, backupHours: '4', sanctionedKw: 1, roofSqft: 100);
    final an = analyze(items: items, cfg: cfg, rates: const Rates(), yieldPerKwp: 3.5, tariff: 8);
    final hy = an.of(SysType.hybrid);
    expect(hy.batteryKwh, closeTo(4 * 0.3 / 0.9, 0.11)); // from critical load, not 60% of inverter
    expect(limitWarnings(hy, cfg).length, greaterThanOrEqualTo(2));
    for (final t in SysType.values) {
      final o = an.of(t);
      final bom = buildBom(o, dcr: true, profile: LoadProfile.residential);
      expect(bom.total, closeTo(o.gross, 0.5));
    }
    expect(recommend(LoadProfile.industrial, 30), SysType.onGrid);
    expect(recommend(LoadProfile.agricultural, 5), SysType.offGrid);
    expect(recommend(LoadProfile.residential, 5, cutHours: 3), SysType.hybrid);
    expect(subsidyNote(LoadProfile.commercial, true, SysType.onGrid), contains('CA'));
    final a = ApplRecord(id: '1', at: 1, label: 'x', cfg: cfg, items: const [], gross: 100);
    final b = ApplRecord.fromJson(a.toJson());
    expect(b.signature, a.signature);
    expect(solarCurve(10).fold(0.0, (x, y) => x + y), closeTo(10, 1e-9));
  });

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
            child: AspectRatio(aspectRatio: 2.3, child: CustomPaint(painter: SunScenePainter(night: night, t: p))),
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

  test('arc progress follows the sun and parks at the ends at night', () {
    final rise = DateTime(2026, 11, 20, 6, 0), set = DateTime(2026, 11, 20, 18, 0);
    expect(arcProgress(DateTime(2026, 11, 20, 12), rise, set, night: false), closeTo(.5, 1e-9));
    expect(arcProgress(DateTime(2026, 11, 20, 9), rise, set, night: false), closeTo(.25, 1e-9));
    expect(arcProgress(DateTime(2026, 11, 20, 21), rise, set, night: false), 1.0);
    expect(arcProgress(DateTime(2026, 11, 20, 3), rise, set, night: false), 0.0);
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
