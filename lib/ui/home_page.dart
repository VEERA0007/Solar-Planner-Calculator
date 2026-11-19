import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calc.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'settings_sheet.dart';
import 'theme.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');
String clock12(DateTime d, {bool seconds = false}) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${_two(h)}:${_two(d.minute)}${seconds ? ':${_two(d.second)}' : ''} ${d.hour < 12 ? 'AM' : 'PM'}';
}

class HomePage extends StatefulWidget {
  final AppState state;
  const HomePage({super.key, required this.state});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final s = widget.state;
      // hourly auto-sync
      if (s.site.auto && !s.syncing && (s.lastSync == null || _now.difference(s.lastSync!).inMinutes >= 60)) {
        s.sync();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final site = s.site;
    final now = _now;
    final info = dayInfo(now, site.lat, site.lon);
    final pos = solarPosition(now, site.lat, site.lon);
    final irr = s.irr;
    final hourly = irr?.hourly ?? const <double>[];
    final psh = hourly.fold(0.0, (a, b) => a + b) / 1000;
    final potential = site.kwp * psh * kPerformanceRatio;
    final hNow = now.hour + now.minute / 60;
    var soFar = 0.0;
    for (var h = 0; h < hourly.length; h++) {
      if (h + 1 <= hNow) {
        soFar += hourly[h];
      } else if (h <= hNow) {
        soFar += hourly[h] * (hNow - h);
      }
    }
    soFar = soFar / 1000 * site.kwp * kPerformanceRatio;
    final live = irr == null ? 0.0 : site.kwp * irr.ghi / 1000 * kPerformanceRatio;
    final load = s.dailyLoad;
    final act = s.activeNow(now);
    final net = potential - load;
    final used = math.min(potential, load);
    final offset = load > 0 ? math.min(100, (potential / load * 100).round()) : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            const Icon(Icons.location_on, color: Color(0xFFF97316), size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(site.city, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                Text(site.label, style: const TextStyle(color: C.mute, fontSize: 14.5), overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            _RoundBtn(Icons.settings_outlined, () => showSettingsSheet(context, s)),
          ]),
        ),
        // date + clock
        Panel(
          radius: 24,
          child: Row(children: [
            const Icon(Icons.calendar_month_outlined, color: C.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${_wd[now.weekday - 1]}, ${_mo[now.month - 1]} ${now.day}, ${now.year}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF0E1A33), borderRadius: BorderRadius.circular(99), border: Border.all(color: C.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const _Dot(C.green, 9),
                const SizedBox(width: 7),
                Text(clock12(now, seconds: true),
                    style: const TextStyle(fontFamilyFallback: kMono, color: C.sky, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(width: 6),
                const Text('LIVE', style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // auto sync
        Panel(
          radius: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
              const _Dot(Color(0xFF0FA27A), 24),
              const Text('Hourly Auto-Sync', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(
                s.lastSync == null ? 'Not synced' : 'Updated: ${_two(s.lastSync!.hour)}:${_two(s.lastSync!.minute)}',
                style: const TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 13),
              ),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Switch(
                value: site.auto,
                onChanged: (v) {
                  site.auto = v;
                  s.saveSite();
                },
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: s.syncing
                    ? null
                    : () async {
                        await s.sync();
                        if (context.mounted) {
                          toast(context, (s.irr?.live ?? false) ? 'Synced with live weather data' : 'Offline: using clear-sky model');
                        }
                      },
                icon: s.syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Icon(Icons.sync),
                label: const Text('Sync Now', style: TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        // sun card
        Panel(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              flex: 42,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('▲  Altitude', style: TextStyle(color: C.mute, fontSize: 14)),
                const SizedBox(height: 4),
                Text('${pos.alt >= 0 ? '+' : ''}${pos.alt.toStringAsFixed(2)}°',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const Divider(color: C.line, height: 22),
                const Text('☀  Sun Status', style: TextStyle(color: C.mute, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Flexible(
                    child: Text(pos.alt > 0 ? compass(pos.az) : 'Below horizon',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const _Dot(C.sun, 14),
                ]),
                const SizedBox(height: 8),
                Text('${fmt1(soFar * kCo2PerKwh)} kg CO₂ avoided',
                    style: const TextStyle(fontFamilyFallback: kMono, color: C.green, fontSize: 12.5)),
              ]),
            ),
            Expanded(
              flex: 58,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                AspectRatio(aspectRatio: 320 / 190, child: CustomPaint(painter: _SunArc(now, info))),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Peak sunlight at : '),
                    TextSpan(
                        text: info.noon == null ? '-' : clock12(info.noon!),
                        style: const TextStyle(color: Color(0xFFFB8A2E), fontWeight: FontWeight.w800)),
                  ]),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        // heading
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Expanded(
            flex: 11,
            child: Text("Today's Energy Balance & Financial Overview",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
          ),
          const SizedBox(width: 10),
          const Expanded(flex: 9, child: Text('· Tap any metric for dedicated analysis', style: TextStyle(color: C.mute, fontSize: 13))),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF131C31), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(child: Text(irr == null ? 'Waiting for sync' : skyLabel(irr.cloud), style: const TextStyle(fontWeight: FontWeight.w600))),
            Column(children: [
              Text(psh > 0 ? psh.toStringAsFixed(1) : '-',
                  style: const TextStyle(fontFamilyFallback: kMono, color: C.amber, fontSize: 18, fontWeight: FontWeight.w700)),
              const Text('PSH', style: TextStyle(fontFamilyFallback: kMono, color: C.amber, fontSize: 12)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _Metric(
                icon: Icons.wb_sunny_outlined,
                iconBg: const Color(0xFF2A1F12),
                iconColor: C.sun,
                name: 'Potential Gain',
                value: potential < 100 ? potential.toStringAsFixed(1) : potential.round().toString(),
                unit: 'kWh',
                unitColor: C.amber,
                desc: 'Yield from ${site.kwp} kWp plant',
                foot1: '${live.toStringAsFixed(2)} kW live',
                foot2: '${(irr?.ghi ?? 0).round()} W/m²',
                onTap: () => s.setTab(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                icon: Icons.monitor_heart_outlined,
                iconBg: const Color(0xFF0D2238),
                iconColor: C.sky,
                name: 'Actual Usage',
                value: load.toStringAsFixed(1),
                unit: 'kWh',
                unitColor: C.sky,
                desc: 'Household consumption load',
                foot1: '${act.kw.toStringAsFixed(2)} kW active',
                foot2: '${s.appliances.length} appliances',
                onTap: () => s.setTab(2),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _Metric(
                icon: Icons.trending_down,
                iconBg: const Color(0xFF2A1F12),
                iconColor: C.sun,
                name: net >= 0 ? 'Grid Surplus' : 'Grid Deficit',
                value: '${net >= 0 ? '+' : '-'}${net.abs().toStringAsFixed(1)}',
                unit: 'kWh',
                unitColor: C.amber,
                desc: net >= 0 ? 'Surplus exported to grid' : 'Deficit drawn from grid',
                foot1: 'Offset: $offset%',
                foot2: net >= 0 ? 'Self-sufficient' : 'Grid Reliance',
                foot2Color: C.amber,
                onTap: () => s.setTab(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                icon: Icons.auto_awesome,
                iconBg: const Color(0xFF221941),
                iconColor: C.purple,
                name: 'Financial Value',
                value: '₹${groupIndian(used * site.tariff)}',
                unit: 'saved',
                unitColor: C.green,
                desc: '@ ₹${site.tariff}/kWh tariff',
                foot1: '${fmt1(potential * kCo2PerKwh)} kg CO₂',
                foot2: 'Clean offset',
                foot2Color: C.green,
                onTap: () => s.setTab(1),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // balance
        Panel(
          radius: 24,
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Solar: '),
                TextSpan(text: potential.toStringAsFixed(1), style: const TextStyle(fontFamilyFallback: kMono, fontWeight: FontWeight.w700)),
                const TextSpan(text: ' kWh'),
              ]), style: const TextStyle(fontSize: 16)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Load: '),
                TextSpan(text: load.toStringAsFixed(1), style: const TextStyle(fontFamilyFallback: kMono, fontWeight: FontWeight.w700)),
                const TextSpan(text: ' kWh'),
              ]), style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: math.max(1, (potential * 100).round()), child: Container(height: 12, decoration: BoxDecoration(color: const Color(0xFFFF9500), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(width: 6),
              Expanded(flex: math.max(1, (load * 100).round()), child: Container(height: 12, decoration: BoxDecoration(color: const Color(0xFF0A9BFF), borderRadius: BorderRadius.circular(99)))),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(irr == null ? '-' : '${irr.dni.round()} DNI · ${irr.ghi.round()} GHI', style: const TextStyle(color: C.mute, fontSize: 13.5)),
              Text('${net >= 0 ? '+' : '-'}${net.abs().toStringAsFixed(1)} kWh Net ${net >= 0 ? 'Export' : 'Import'}',
                  style: const TextStyle(color: C.amber, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Data: ${irr == null ? '-' : (irr.live ? 'LIVE' : 'MODEL')} · Plant performance ratio 84%',
                  style: const TextStyle(color: C.mute, fontSize: 11.5)),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  const _Dot(this.color, this.size);
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF101A30),
        shape: const CircleBorder(side: BorderSide(color: C.line)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 52, height: 52, child: Icon(icon, color: C.blue, size: 26))),
      );
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor, unitColor;
  final String name, value, unit, desc, foot1, foot2;
  final Color foot2Color;
  final VoidCallback onTap;
  const _Metric({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.name,
    required this.value,
    required this.unit,
    required this.unitColor,
    required this.desc,
    required this.foot1,
    required this.foot2,
    this.foot2Color = C.mute,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Panel(
      radius: 24,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text('$name ›', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFB5C0D6), fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ]),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: const TextStyle(fontFamilyFallback: kMono, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
            const SizedBox(width: 6),
            Text(unit, style: TextStyle(color: unitColor, fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
        ),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(color: Color(0xFF9AA6BF), fontSize: 14)),
        const Spacer(),
        const SizedBox(height: 10),
        const Divider(color: C.line, height: 1),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 2, children: [
          Text(foot1, style: const TextStyle(fontFamilyFallback: kMono, color: Color(0xFF9AA6BF), fontSize: 12)),
          Text(foot2, style: TextStyle(fontFamilyFallback: kMono, color: foot2Color, fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _SunArc extends CustomPainter {
  final DateTime now;
  final DayInfo info;
  _SunArc(this.now, this.info);
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 320, sy = size.height / 190;
    canvas.scale(sx, sy);
    const cx = 160.0, cy = 170.0, r = 140.0;
    final rise = info.rise, set = info.set;
    var f = 0.0;
    var day = false;
    if (rise != null && set != null) {
      final total = set.difference(rise).inSeconds;
      f = total > 0 ? (now.difference(rise).inSeconds / total).clamp(0.0, 1.0).toDouble() : 0.0;
      day = !now.isBefore(rise) && !now.isAfter(set);
    }
    // dashed arc
    final arc = Path()..addArc(Rect.fromCircle(center: const Offset(cx, cy), radius: r), math.pi, math.pi);
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.butt;
    for (final m in arc.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), dashPaint);
        d += 16;
      }
    }
    canvas.drawCircle(const Offset(cx + r, cy), 12, Paint()..color = const Color(0xFF3A2A22));
    final x = cx - r * math.cos(math.pi * f), y = cy - r * math.sin(math.pi * f);
    if (day) canvas.drawCircle(Offset(x, y), 26, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.18));
    canvas.drawCircle(Offset(x, y), 11, Paint()..color = day ? const Color(0xFFF97316) : const Color(0xFF475569));
    canvas.drawCircle(Offset(x, y), 5, Paint()..color = const Color(0xFF0B1220));
    canvas.drawCircle(Offset(x, y), 3, Paint()..color = day ? const Color(0xFFFDBA74) : const Color(0xFF94A3B8));
  }

  @override
  bool shouldRepaint(covariant _SunArc old) => true;
}
