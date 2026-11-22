import 'dart:async';
import 'package:flutter/material.dart';
import '../core/store.dart';
import 'service_level.dart';
import 'service_maint.dart';
import 'service_space.dart';
import 'service_tilt.dart';
import 'theme.dart';

/// Service & Field Tools: maintenance log, tilt & angles, bubble level, space weather.
class ServicePage extends StatefulWidget {
  final AppState state;
  const ServicePage({super.key, required this.state});
  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  int tab = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dark = s.isDark(now);
    final psh = s.monthly?.forMonth(now.month);
    const tabs = [
      (Icons.build_outlined, 'Maintenance'),
      (Icons.tune, 'Tilt & Angles'),
      (Icons.refresh, 'Bubble Level'),
      (Icons.sensors, 'Space Weather'),
    ];
    final accents = [C.blue, C.purple, C.green, C.orange];
    const subtitles = [
      'System Maintenance, Tilt, Level & Space Weather',
    ];
    final body = switch (tab) {
      0 => MaintenanceTab(state: s),
      1 => TiltTab(state: s),
      2 => const LevelTab(),
      _ => SpaceTab(state: s),
    };
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          IconButton(onPressed: () => s.setTab(0), icon: const Icon(Icons.arrow_back), tooltip: 'Home'),
          const SizedBox(width: 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Service & Field Tools', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              Text(subtitles.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ),
          IconButton(onPressed: () => s.setDark(!dark), icon: Icon(dark ? Icons.wb_sunny_outlined : Icons.nightlight_outlined, color: dark ? C.sun : C.mute)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wb_cloudy_outlined, size: 18, color: C.orange),
              const SizedBox(width: 5),
              Text(psh == null ? '–' : '${psh.toStringAsFixed(1)}h', style: TextStyle(fontWeight: FontWeight.w800, color: C.sky)),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: ServiceTabs(
          items: [for (final t in tabs) (t.$1, t.$2)],
          index: tab,
          accents: accents,
          onTap: (i) => setState(() => tab = i),
        ),
      ),
      Expanded(child: KeyedSubtree(key: ValueKey(tab), child: body)),
    ]);
  }
}

/// Rounded segmented tabs: the selected one is a raised chip in its accent colour.
class ServiceTabs extends StatelessWidget {
  final List<(IconData?, String)> items;
  final int index;
  final List<Color> accents;
  final ValueChanged<int> onTap;
  final bool compact;
  const ServiceTabs({super.key, required this.items, required this.index, required this.accents, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(vertical: compact ? 11 : 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: i == index ? C.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: i == index ? [BoxShadow(color: Colors.black.withValues(alpha: C.dark ? .35 : .08), blurRadius: 8, offset: const Offset(0, 2))] : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (items[i].$1 != null && !compact) Icon(items[i].$1, size: 20, color: i == index ? accents[i] : C.mute),
                  if (items[i].$1 != null && !compact) const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (items[i].$1 != null && compact) ...[Icon(items[i].$1, size: 18, color: i == index ? accents[i] : C.mute), const SizedBox(width: 6)],
                      Text(items[i].$2, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: i == index ? accents[i] : C.mute)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Section label used inside the Service tabs (upper-case, spaced).
class CapsLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const CapsLabel(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: color ?? C.mute));
}
