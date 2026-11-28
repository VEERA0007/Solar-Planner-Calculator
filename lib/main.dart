import 'dart:async';
import 'package:flutter/material.dart';
import 'core/i18n.dart';
import 'core/geo.dart';
import 'core/store.dart';
import 'core/update.dart';
import 'ui/appliance_page.dart';
import 'ui/estimator_page.dart';
import 'ui/home_page.dart';
import 'ui/sun_scene.dart';
import 'ui/update_dialog.dart';
import 'ui/service_page.dart';
import 'ui/solar_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SunScenePainter.preload();
  runApp(const SolarApp());
}

class SolarApp extends StatefulWidget {
  const SolarApp({super.key});
  @override
  State<SolarApp> createState() => _SolarAppState();
}

class _SolarAppState extends State<SolarApp> with WidgetsBindingObserver {
  bool _updateOpen = false;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
  final AppState state = AppState();
  Timer? _clock;
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.load().then((_) async {
      await askLocationOnceAtStart(); // single permission prompt at launch, before the first GPS read
      _autoUpdateCheck();
      await state.sync();
      if (state.site.auto) state.locate(); // refreshes place, state and sun data from GPS when allowed
    });
    // day/night auto mode re-evaluates every minute
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && state.prefs.dark == null) setState(() {});
    });
  }

  Future<void> _autoUpdateCheck() async {
    if (_updateOpen) return;
    _lastCheck = DateTime.now();
    final res = await checkForUpdate();
    final u = res.update;
    final ctx = navKey.currentContext;
    if (u == null || ctx == null || !ctx.mounted || _updateOpen) return;
    _updateOpen = true;
    await showUpdateDialog(ctx, u, res.currentLabel);
    _updateOpen = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed && DateTime.now().difference(_lastCheck) > const Duration(minutes: 20)) _autoUpdateCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final dark = state.isDark(DateTime.now());
        final theme = buildTheme(dark);
        return MaterialApp(
          navigatorKey: navKey,
          title: 'Solar Planner & Calculator',
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            navigationBarTheme: NavigationBarThemeData(
              labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5, height: 1.1, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(autoTextScale(mq) * state.prefs.textScale)),
              child: child!,
            );
          },
          home: Shell(state: state),
        );
      },
    );
  }
}

class Shell extends StatelessWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  static const _items = <(IconData, String)>[
    (Icons.home_outlined, 'home'),
    (Icons.calculate_outlined, 'estimator'),
    (Icons.memory_outlined, 'appliance'),
    (Icons.wb_sunny_outlined, 'solar'),
    (Icons.build_outlined, 'service'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final pages = <Widget>[
          HomePage(state: state),
          EstimatorPage(state: state),
          AppliancePage(state: state),
          SolarPage(state: state),
          ServicePage(state: state),
        ];
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                // Phones and tablets keep a readable column; desktop windows use the full width.
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width >= 900 ? double.infinity : 760),
                child: IndexedStack(index: state.tab, children: pages),
              ),
            ),
          ),
          bottomNavigationBar: _NavBar(
            index: state.tab,
            onTap: state.setTab,
            items: [for (final it in _items) (it.$1, tr(state.lang, it.$2))],
          ),
        );
      },
    );
  }
}

/// Bottom tabs: icons sit on one line, every label is a single centred line that
/// shrinks to fit its slot, so nothing wraps or drifts out of alignment.
class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;
  const _NavBar({required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slot = MediaQuery.sizeOf(context).width.clamp(0, 760) / items.length;
    final fs = (slot / 9.6).clamp(8.8, 12.5).toDouble();
    return Material(
      color: Theme.of(context).navigationBarTheme.backgroundColor ?? cs.surfaceContainer,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)))),
        child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 54,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == index ? cs.secondaryContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(items[i].$1, size: 24, color: i == index ? cs.primary : cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: SizedBox(
                        height: 16,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            items[i].$2,
                            maxLines: 1,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(fontSize: fs, fontWeight: i == index ? FontWeight.w800 : FontWeight.w600, color: i == index ? cs.primary : cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      ),
    );
  }
}
