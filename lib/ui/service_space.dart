import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/service_data.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'service_page.dart';
import 'theme.dart';

class SpaceTab extends StatefulWidget {
  static set testPreset(SpaceWx? v) => _SpaceTabState.preset = v;
  final AppState state;
  const SpaceTab({super.key, required this.state});
  @override
  State<SpaceTab> createState() => _SpaceTabState();
}

class _SpaceTabState extends State<SpaceTab> {
  /// Test hook: shows fixed data instead of calling the network.
  static SpaceWx? preset;

  int sub = 0;
  SpaceWx? wx;
  bool loading = true;
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    if (preset != null) {
      wx = preset;
      loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    SpaceWx? r;
    try {
      r = await fetchSpaceWeather();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      wx = r;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
      ServiceTabs(
        items: const [(Icons.sensors, 'Radio Flux'), (Icons.monitor_heart_outlined, 'Kp-Index'), (Icons.auto_awesome_outlined, 'Sun Report')],
        index: sub,
        accents: [C.orange, C.purple, C.blue],
        compact: true,
        onTap: (i) => setState(() => sub = i),
      ),
      const SizedBox(height: 14),
      if (sub == 2) ..._sunReport() else if (loading && wx == null) _loading() else if (wx == null || !wx!.hasAny) _offline() else ...(sub == 0 ? _flux(wx!) : _kp(wx!)),
      if (sub != 2) _footer(),
    ]);
  }

  Widget _loading() => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));

  Widget _offline() => Panel(
        child: Column(children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: C.mute),
          const SizedBox(height: 8),
          const Text('Space-weather feed unavailable', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Connect to the internet and try again.', style: TextStyle(color: C.mute)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );

  Widget _footer() {
    final t = wx?.fetched;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(
          child: Text(
            t == null || t.millisecondsSinceEpoch == 0 ? 'Source: NOAA SWPC' : 'Source: NOAA SWPC · ${wx!.cached ? 'saved ' : 'updated '}${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
            style: TextStyle(color: C.mute, fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(onPressed: loading ? null : _load, icon: Icon(Icons.refresh, size: 20, color: C.mute), visualDensity: VisualDensity.compact),
      ]),
    );
  }

  // --------------------------------------------------------------- radio flux
  List<Widget> _flux(SpaceWx w) {
    final f = w.f107;
    final level = f == null ? '–' : (f < 100 ? 'Low' : (f < 150 ? 'Moderate' : (f < 200 ? 'Elevated' : 'High')));
    final cls = w.flareClass;
    final letters = ['A', 'B', 'C', 'M', 'X'];
    final cur = cls == null ? -1 : letters.indexOf(cls[0]);
    const barCols = [Color(0xFF19D38E), Color(0xFF1AA7F0), Color(0xFFFFA800), Color(0xFFFFC9A5), Color(0xFFFFB3C0)];
    final strong = cur >= 3;
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE8800A), Color(0xFFF2490A), Color(0xFFDC1D1D)]),
          boxShadow: [BoxShadow(color: const Color(0xFFF2490A).withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.sensors, color: Color(0xFFFFD08A), size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('10.7 CM RADIO EMISSIONS', style: TextStyle(color: Color(0xFFFFD08A), fontWeight: FontWeight.w800, fontSize: 14.5))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .28), borderRadius: BorderRadius.circular(99)), child: Text(level, style: const TextStyle(color: Color(0xFFFFD08A), fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(f == null ? '–' : f.round().toString(), style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(width: 10),
            const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('sfu', style: TextStyle(color: Color(0xFFFFD08A), fontSize: 24, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          const Text("Measures the Sun's 2800 MHz microwave radio flux. Higher values correlate with elevated solar flares and solar radiation storm risks.", style: TextStyle(color: Color(0xFFFFE3C2), fontSize: 15.5, height: 1.5)),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: .25), height: 1),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _darkBox('Active Sunspot Regions', w.regions == null ? '–' : '${w.regions} Active Groups')),
            const SizedBox(width: 10),
            Expanded(child: _darkBox('Current Flare Activity', cls == null ? '–' : '$cls Class')),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.local_fire_department_outlined, color: C.orange, size: 24),
            const SizedBox(width: 8),
            const Expanded(child: Text('GOES X-RAY FLARE METER (A, B, C, M, X)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: .3))),
            if (cls != null) Text(cls, style: TextStyle(fontFamilyFallback: kMono, color: C.orange, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: i == cur ? 26 : 20,
                  decoration: BoxDecoration(
                    color: i == cur ? barCols[i] : barCols[i].withValues(alpha: i < cur ? .85 : .4),
                    borderRadius: BorderRadius.circular(i == 4 ? 99 : 6),
                    boxShadow: i == cur ? [BoxShadow(color: barCols[i].withValues(alpha: .6), blurRadius: 12)] : null,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < 5; i++)
              Expanded(child: Center(child: Text(i == cur ? '${letters[i]} (Current)' : letters[i], maxLines: 1, style: TextStyle(color: [C.green, C.sky, C.amber, C.orange, C.red][i], fontWeight: FontWeight.w800, fontSize: i == cur ? 13 : 15)))),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: C.amber.withValues(alpha: .35))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.bolt, color: C.amber, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cls == null ? 'Flare level unavailable' : '$cls Flare Level · ${strong ? 'Radio blackout possible' : 'Low radio blackout impact'}', style: TextStyle(fontWeight: FontWeight.w800, color: C.amber, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(strong ? 'High-frequency radio blackouts and brief inverter / telemetry glitches are possible on the sunlit side.' : 'No high-frequency radio blackouts or solar panel telemetry degradation expected today.', style: TextStyle(color: C.mute, fontSize: 14, height: 1.4)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CapsLabel('24-Hour Flare Probability'),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _prob('C-Class', w.pC, C.orange),
            _prob('M-Class', w.pM, const Color(0xFFE8590C)),
            _prob('X-Class', w.pX, C.red),
          ]),
        ]),
      ),
    ];
  }

  Widget _prob(String l, double? v, Color c) => Text('$l: ${v == null ? '–' : '${v.round()}%'}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16.5));

  Widget _darkBox(String l, String v) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .25), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFD6A8), fontSize: 13.5)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19))),
        ]),
      );

  // ------------------------------------------------------------------ Kp index
  List<Widget> _kp(SpaceWx w) {
    final kp = w.kp;
    final quiet = kp == null || kp < 4;
    final badge = kp == null ? '–' : (kp < 4 ? 'GO · QUIET' : (kp < 5 ? 'WATCH' : 'STORM'));
    final badgeCol = kp == null || kp < 4 ? const Color(0xFF34D399) : (kp < 5 ? const Color(0xFFFFC53D) : const Color(0xFFFF6B6B));
    final cut = kp == null ? null : auroraCutoffLat(kp).round();
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4F2DD8), Color(0xFF0A5BA8), Color(0xFF0B1636)]),
          boxShadow: [BoxShadow(color: const Color(0xFF4F2DD8).withValues(alpha: .3), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.monitor_heart_outlined, color: Color(0xFF5EEAD4), size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('PLANETARY KP-INDEX', style: TextStyle(color: Color(0xFF5EEAD4), fontWeight: FontWeight.w800, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: badgeCol.withValues(alpha: .18), borderRadius: BorderRadius.circular(99), border: Border.all(color: badgeCol.withValues(alpha: .6))),
              child: Text(badge, style: TextStyle(color: badgeCol, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(kp == null ? '–' : kp.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(width: 10),
            const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('/ 9.0 Scale', style: TextStyle(color: Color(0xFFD6E4FF), fontSize: 22, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          const Text('Monitors global geomagnetic storms, auroral oval extensions, and electrical power grid induced currents.', style: TextStyle(color: Color(0xFFD6E4FF), fontSize: 15.5, height: 1.5)),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: .2), height: 1),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _kpBox('Aurora Cutoff Lat', cut == null ? '–' : '≥ $cut° N/S', Colors.white)),
            const SizedBox(width: 10),
            Expanded(child: _kpBox('GIC Grid Storm Risk', quiet ? 'Minimal / GO Quiet' : (kp < 5 ? 'Low / Watch' : 'Elevated / Storm'), badgeCol)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.monitor_heart_outlined, color: C.sky, size: 24),
            const SizedBox(width: 8),
            const Expanded(child: Text('24-HOUR KP HISTORY (3-HOUR BLOCKS)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.25))),
            Text('NOAA\nSWPC', textAlign: TextAlign.right, style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 12.5)),
          ]),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: w.kpHistory.isEmpty ? Center(child: Text('No history available', style: TextStyle(color: C.mute))) : _KpBars(w.kpHistory)),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.purple.withValues(alpha: .10), borderRadius: BorderRadius.circular(22), border: Border.all(color: C.purple.withValues(alpha: .3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome_outlined, color: C.purple),
            const SizedBox(width: 8),
            Expanded(child: Text('Aurora Visibility Boundary: Lat ≥ ${cut ?? '–'}°', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: C.purple))),
          ]),
          const SizedBox(height: 6),
          Text('Visible poleward of ${cut ?? '–'}° latitude (Alaska, Scandinavia, Northern Canada)', style: TextStyle(color: C.mute, fontSize: 14.5, height: 1.4)),
        ]),
      ),
    ];
  }

  Widget _kpBox(String l, String v, Color vc) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .10), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFBFD3F7), fontSize: 13.5)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: TextStyle(color: vc, fontWeight: FontWeight.w800, fontSize: 19))),
        ]),
      );

  // --------------------------------------------------------------- sun report
  List<Widget> _sunReport() {
    final now = DateTime.now();
    final info = dayInfo(now, s.site.lat, s.site.lon);
    final psh = s.monthly?.forMonth(now.month) ?? 0;
    final irr = s.irr, wthr = s.weather;
    final cloud = wthr?.cloud ?? irr?.cloud ?? 0;
    final clear = (100 - cloud).clamp(0, 100).round();
    final ghi = irr?.ghi ?? wthr?.ghi ?? 0;
    final noon = info.noon;
    String hm(DateTime? d) => d == null ? '--:--' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    String h12(DateTime d) => '${(d.hour % 12 == 0 ? 12 : d.hour % 12).toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
    final winA = noon?.subtract(const Duration(hours: 2, minutes: 30)), winB = noon?.add(const Duration(hours: 2, minutes: 30));
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0A74F0), Color(0xFF2358EE), Color(0xFF5A32E0)]),
          boxShadow: [BoxShadow(color: const Color(0xFF2358EE).withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_outlined, color: Color(0xFFFFD66B), size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('DAILY SUN INTELLIGENCE REPORT', style: TextStyle(color: Color(0xFFFFD66B), fontWeight: FontWeight.w800, fontSize: 14.5))),
            Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .22), borderRadius: BorderRadius.circular(99)), child: Text(s.site.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(psh == 0 ? '–' : psh.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(width: 10),
            const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Peak Sun Hours', style: TextStyle(color: Color(0xFFD6E4FF), fontSize: 22, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text('Clear sky factor is $clear%. Prime power window is between ${winA == null ? '--' : h12(winA)} and ${winB == null ? '--' : h12(winB)}.', style: const TextStyle(color: Color(0xFFE3EDFF), fontSize: 15.5, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _tile('Solar Irradiance (GHI)', '${ghi.round()} W/m²', C.amber, mono: true)),
        const SizedBox(width: 10),
        Expanded(child: _tile('UV Radiation Index', wthr == null ? '–' : wthr.uv.toStringAsFixed(1), C.purple, mono: true)),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _tile('Sunrise / Sunset', '${hm(info.rise)} - ${hm(info.set)}', C.text)),
        const SizedBox(width: 10),
        Expanded(child: _tile('Weather Status', cloud < 20 ? 'Clear sky / Optimal Sun' : (cloud < 60 ? 'Partly cloudy' : 'Overcast'), cloud < 60 ? C.green : C.mute)),
      ]),
    ];
  }

  Widget _tile(String l, String v, Color c, {bool mono = false}) => Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.toUpperCase(), maxLines: 2, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.25)),
          const SizedBox(height: 8),
          Text(v, style: TextStyle(color: c, fontWeight: mono ? FontWeight.w700 : FontWeight.w800, fontSize: mono ? 24 : 17.5, fontFamilyFallback: mono ? kMono : null, height: 1.2)),
        ]),
      );
}

class _KpBars extends StatelessWidget {
  final List<KpBlock> blocks;
  const _KpBars(this.blocks);
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final b in blocks)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(b.kp.toStringAsFixed(1), style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 12.5))),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final hgt = math.max(8.0, box.maxHeight * (b.kp / 9).clamp(0.0, 1.0));
                  return Container(
                    decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: hgt,
                      decoration: BoxDecoration(color: b.kp < 4 ? const Color(0xFF00A6F4) : (b.kp < 5 ? C.amber : C.red), borderRadius: const BorderRadius.vertical(top: Radius.circular(10), bottom: Radius.circular(10))),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, child: Text('${b.time.hour.toString().padLeft(2, '0')}:00', style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 12))),
            ]),
          ),
        ),
    ]);
  }
}
