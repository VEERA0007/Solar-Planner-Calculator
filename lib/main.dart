import 'dart:async';
import 'package:flutter/material.dart';
import 'core/i18n.dart';
import 'core/store.dart';
import 'core/update.dart';
import 'ui/appliance_page.dart';
import 'ui/estimator_page.dart';
import 'ui/home_page.dart';
import 'ui/service_page.dart';
import 'ui/solar_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SolarApp());
}

class SolarApp extends StatefulWidget {
  const SolarApp({super.key});
  @override
  State<SolarApp> createState() => _SolarAppState();
}

class _SolarAppState extends State<SolarApp> {
  final AppState state = AppState();
  Timer? _clock;
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    state.load().then((_) async {
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
    final res = await checkForUpdate();
    final u = res.update;
    final ctx = navKey.currentContext;
    if (u == null || ctx == null || !ctx.mounted) return;
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('New version available'),
        content: Text('${u.versionName} is ready.\nYou have ${res.currentVersion}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              openUpdate(u);
            },
            child: const Text('Update now'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
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
          theme: theme,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(autoTextScale(mq))),
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: IndexedStack(index: state.tab, children: pages),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: state.tab,
            onDestinationSelected: state.setTab,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            height: 72,
            destinations: [
              for (final it in _items) NavigationDestination(icon: Icon(it.$1), label: tr(state.lang, it.$2)),
            ],
          ),
        );
      },
    );
  }
}
