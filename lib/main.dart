import 'package:flutter/material.dart';
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
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    state.load().then((_) {
      state.sync();
      _autoUpdateCheck();
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
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Solar Planner & Calculator',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(state: state),
    );
  }
}

class Shell extends StatelessWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  static const _items = <(IconData, String)>[
    (Icons.home_outlined, 'Home'),
    (Icons.calculate_outlined, 'Estimator'),
    (Icons.memory_outlined, 'Appliance Analysis'),
    (Icons.wb_sunny_outlined, 'Solar Analysis'),
    (Icons.build_outlined, 'Service'),
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
          const ServicePage(),
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
              for (final it in _items) NavigationDestination(icon: Icon(it.$1), label: it.$2),
            ],
          ),
        );
      },
    );
  }
}
