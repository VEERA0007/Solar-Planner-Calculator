import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calc.dart';
import '../core/i18n.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'location_sheet.dart';
import 'profile_dialog.dart';
import 'settings_dialog.dart';
import 'sun_scene.dart';
import 'theme.dart';

String fmtTrim(double v) {
  final t = v.toStringAsFixed(2);
  return t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

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
  DayInfo? _info;
  int _infoKey = -1;
  bool _cloudNotified = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final s = widget.state;
      if (s.prefs.autoSync && !s.syncing && (s.lastSync == null || _now.difference(s.lastSync!).inMinutes >= 60)) {
        s.sync();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DayInfo _dayInfo(AppState s) {
    final key = _now.day * 100000 + (s.site.lat * 100).round() * 7 + (s.site.lon * 100).round();
    if (_info == null || key != _infoKey) {
      _info = dayInfo(_now, s.site.lat, s.site.lon);
      _infoKey = key;
    }
    return _info!;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final site = s.site;
    final now = _now;
    final info = _dayInfo(s);
    final pos = solarPosition(now, site.lat, site.lon);
    final irr = s.irr;
    final hourly = irr?.hourly ?? const <double>[];
    final psh = hourly.fold(0.0, (a, b) => a + b) / 1000;
    final potential = site.kwp * psh * s.pr;
    final hNow = now.hour + now.minute / 60;
    var soFar = 0.0;
    for (var h = 0; h < hourly.length; h++) {
      if (h + 1 <= hNow) {
        soFar += hourly[h];
      } else if (h <= hNow) {
        soFar += hourly[h] * (hNow - h);
      }
    }
    soFar = soFar / 1000 * site.kwp * s.pr;
    final live = irr == null ? 0.0 : site.kwp * irr.ghi / 1000 * s.pr;
    final load = s.dailyLoad;
    final act = s.activeNow(now);
    final net = potential - load;
    final used = math.min(potential, load);
    final offset = load > 0 ? math.min(100, (potential / load * 100).round()) : 0;
    final monthPsh = s.monthly?.forMonth(now.month);
    final lang = s.lang;
    final t = s.t;
    final night = C.dark;
    final progress = arcProgress(now, info.rise, info.set, night: night);
    final cloud = irr?.cloud ?? 0;
    final skyKey = cloud < 20 ? 'clear_sky' : (cloud < 60 ? 'partly_cloudy' : 'overcast');
    final due = s.cleanDueInDays;

    // one-time cloud alert while the app is open
    if (s.prefs.cloudAlerts && irr != null && irr.live && pos.alt > 15) {
      final clear = clearSky(pos.alt).ghi;
      final drop = clear > 0 ? 1 - irr.ghi / clear : 0;
      if (drop > 0.5 && !_cloudNotified) {
        _cloudNotified = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) toast(context, t('cloud_alert_msg'));
        });
      } else if (drop < 0.3) {
        _cloudNotified = false;
      }
    }

    final subtitle = site.label.isEmpty ? (s.profile.address) : site.label;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ---------- header ----------
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showLocationSheet(context, s),
                child: Row(children: [
                  Icon(Icons.location_on, color: C.orange, size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(site.city, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800), maxLines: 1),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: C.mute),
                      ]),
                      Text(subtitle, style: TextStyle(color: C.mute, fontSize: 12.5), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            _RoundBtn(night ? Icons.wb_sunny_outlined : Icons.nightlight_outlined, () => s.setDark(!night),
                color: night ? C.sun : C.blue),
            const SizedBox(width: 8),
            _RoundBtn(Icons.settings_outlined, () => showSettingsDialog(context, s), color: C.blue),
            const SizedBox(width: 8),
            _Avatar(s.profile.name, () => showProfileDialog(context, s)),
          ]),
        ),
        // ---------- date + live clock ----------
        Panel(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(Icons.calendar_month_outlined, color: C.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(datePill(lang, now), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(99), border: Border.all(color: C.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Dot(C.green, 8),
                const SizedBox(width: 6),
                Text(clock12(now, seconds: true), style: TextStyle(fontFamilyFallback: kMono, color: C.sky, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 6),
                Text('LIVE', style: TextStyle(color: C.mute, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // ---------- hourly auto-sync ----------
        Panel(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _Dot(C.green, 16),
              const SizedBox(width: 8),
              Icon(Icons.wifi_tethering, color: C.sky, size: 20),
              const SizedBox(width: 6),
              Text(t('hourly_sync'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Icon(Icons.schedule, size: 15, color: C.mute),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  s.lastSync == null ? '--:--' : '${t('updated')}: ${_two(s.lastSync!.hour)}:${_two(s.lastSync!.minute)}',
                  style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Switch(
                value: s.prefs.autoSync,
                onChanged: (v) {
                  s.prefs.autoSync = v;
                  s.savePrefs();
                },
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: s.syncing
                    ? null
                    : () async {
                        await s.sync();
                        if (context.mounted) toast(context, '${t('updated')} ${clock12(DateTime.now())}');
                      },
                icon: s.syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Icon(Icons.sync, size: 18),
                label: Text(t('sync_now'), style: const TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        // ---------- sun card: animated scene fills the card ----------
        Panel(
          radius: 24,
          padding: EdgeInsets.zero,
          child: AspectRatio(
            aspectRatio: 2.3,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              return Stack(children: [
                Positioned.fill(child: SunScene(night: night, t: progress)),
                Positioned(
                  left: 16,
                  top: 10,
                  bottom: 10,
                  width: w * .40,
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 150,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.change_history, size: 14, color: C.blue),
                            const SizedBox(width: 4),
                            Flexible(child: Text(t('altitude'), style: TextStyle(color: C.mute, fontSize: 13))),
                          ]),
                          const SizedBox(height: 2),
                          Text('${pos.alt >= 0 ? '+' : ''}${pos.alt.toStringAsFixed(2)}°',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                          Divider(color: C.line, height: 18),
                          Row(children: [
                            Icon(Icons.wb_sunny_outlined, size: 16, color: C.orange),
                            const SizedBox(width: 5),
                            Flexible(child: Text(t('sun_status'), style: TextStyle(color: C.mute, fontSize: 13))),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            Flexible(
                              child: Text(pos.alt > 0 ? compassName(lang, pos.az) : t('below_horizon'),
                                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 6),
                            _Dot(pos.alt > 0 ? C.sun : C.mute, 11),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _Dot(C.green, 8),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text('${fmt1(soFar * kCo2PerKwh)} ${t('co2_avoided')}',
                                  style: TextStyle(fontFamilyFallback: kMono, color: C.green, fontSize: 11.5)),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: h * .06,
                  width: w * .56,
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (night ? Colors.black : Colors.white).withValues(alpha: night ? .35 : .72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${t('peak_at')} : '),
                        TextSpan(text: info.noon == null ? '-' : clock12(info.noon!), style: TextStyle(color: C.orange, fontWeight: FontWeight.w800)),
                      ]),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: night ? Colors.white : const Color(0xFF1F2937)),
                      ),
                      ),
                    ),
                  ),
                ),
              ]);
            }),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- heading + sky chip (adapts: one row when wide, stacked when narrow) ----------
        LayoutBuilder(builder: (context, box) {
          final heading = Text(t('energy_balance'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25));
          final hint = Text(t('tap_metric'), style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.3));
          final chip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(16)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(night ? Icons.nightlight_outlined : Icons.wb_cloudy_outlined, size: 18, color: C.orange),
                const SizedBox(width: 6),
                Text(irr == null ? '…' : (cloud < 20 ? '${t(skyKey)} / Opt…' : t(skyKey)),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5), maxLines: 1),
                const SizedBox(width: 10),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text((monthPsh ?? psh) > 0 ? (monthPsh ?? psh).toStringAsFixed(1) : '-',
                      style: TextStyle(fontFamilyFallback: kMono, color: C.amber, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('PSH', style: TextStyle(fontFamilyFallback: kMono, color: C.amber, fontSize: 10.5)),
                ]),
              ]),
            ),
          );
          if (box.maxWidth >= 520) {
            return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(flex: 11, child: heading),
              const SizedBox(width: 8),
              Expanded(flex: 9, child: hint),
              const SizedBox(width: 8),
              Expanded(flex: 11, child: chip),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(flex: 5, child: heading),
              const SizedBox(width: 10),
              Expanded(flex: 4, child: chip),
            ]),
            const SizedBox(height: 4),
            hint,
          ]);
        }),
        const SizedBox(height: 12),
        // ---------- 4 display-only metric cards ----------
        _pair(
          _Metric(
            icon: Icons.wb_sunny_outlined, iconBg: C.chipSun, iconColor: C.sun,
            name: t('potential_gain'),
            value: potential < 100 ? fmtTrim(potential) : potential.round().toString(),
            unit: 'kWh', unitColor: C.amber,
            foot1: '${live.toStringAsFixed(2)} kW ${t('live_word')}', foot2: '${(irr?.ghi ?? 0).round()} W/m²',
            desc: '${t('desc_yield')} ${site.kwp} ${t('desc_plant')}',
          ),
          _Metric(
            icon: Icons.monitor_heart_outlined, iconBg: C.chipBlue, iconColor: C.sky,
            name: t('actual_usage'), value: load.toStringAsFixed(1), unit: 'kWh', unitColor: C.sky,
            foot1: '${act.kw.toStringAsFixed(2)} kW ${t('active_word')}', foot2: '${s.appliances.length} ${t('appliances_word')}',
            desc: t('desc_load'),
          ),
        ),
        const SizedBox(height: 12),
        _pair(
          _Metric(
            icon: Icons.trending_down, iconBg: C.chipSun, iconColor: C.sun,
            name: net >= 0 ? t('grid_surplus') : t('grid_deficit'),
            value: '${net >= 0 ? '+' : '-'}${net.abs().toStringAsFixed(1)}', unit: 'kWh', unitColor: C.amber,
            foot1: '${t('offset_word')}: $offset%', foot2: net >= 0 ? t('self_sufficient') : t('grid_reliance'), foot2Color: C.amber,
            desc: net >= 0 ? t('desc_surplus') : t('desc_deficit'),
          ),
          _Metric(
            icon: Icons.auto_awesome, iconBg: C.chipPurple, iconColor: C.purple,
            name: t('financial_value'), value: '₹${groupIndian(used * s.unitPrice)}', unit: t('saved_word'), unitColor: C.green,
            foot1: '${fmt1(potential * kCo2PerKwh)} kg CO₂', foot2: t('clean_offset'), foot2Color: C.green,
            desc: '@ ₹${fmtTrim(s.unitPrice)}/kWh ${t('tariff_word')}',
          ),
        ),
        const SizedBox(height: 14),
        // ---------- solar vs load ----------
        Panel(
          radius: 24,
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${t('solar_label')}: '),
                TextSpan(text: potential.toStringAsFixed(1), style: const TextStyle(fontFamilyFallback: kMono, fontWeight: FontWeight.w700)),
                const TextSpan(text: ' kWh'),
              ]), style: const TextStyle(fontSize: 14)),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${t('load')}: '),
                TextSpan(text: load.toStringAsFixed(1), style: const TextStyle(fontFamilyFallback: kMono, fontWeight: FontWeight.w700)),
                const TextSpan(text: ' kWh'),
              ]), style: const TextStyle(fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: math.max(1, (potential * 100).round()), child: Container(height: 12, decoration: BoxDecoration(color: const Color(0xFFFF9500), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(width: 6),
              Expanded(flex: math.max(1, (load * 100).round()), child: Container(height: 12, decoration: BoxDecoration(color: const Color(0xFF0A9BFF), borderRadius: BorderRadius.circular(99)))),
            ]),
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
              Text(irr == null ? '-' : '${irr.dni.round()} DNI · ${irr.ghi.round()} GHI', style: TextStyle(color: C.mute, fontSize: 13)),
              Text('${net >= 0 ? '+' : '-'}${net.abs().toStringAsFixed(1)} kWh ${net >= 0 ? t('net_export') : t('net_import')}',
                  style: TextStyle(color: C.amber, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ]),
        ),
        if (due != null && due <= 7) ...[
          const SizedBox(height: 12),
          Panel(
            radius: 20,
            border: C.amber,
            child: Row(children: [
              Icon(Icons.cleaning_services_outlined, color: C.amber),
              const SizedBox(width: 10),
              Expanded(child: Text('${t('to_clean')}${due > 0 ? ' · $due d' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: s.markCleaned, child: const Text('✓')),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _pair(Widget a, Widget b) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]),
      );
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
  final Color color;
  const _RoundBtn(this.icon, this.onTap, {required this.color});
  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        shape: CircleBorder(side: BorderSide(color: C.line)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 42, height: 42, child: Icon(icon, color: color, size: 22))),
      );
}

class _Avatar extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _Avatar(this.name, this.onTap);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 50,
        height: 50,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, color: C.card, border: Border.all(color: C.line)),
              child: Icon(Icons.person, color: C.sky, size: 24),
            ),
          ),
          Positioned(top: 0, right: 2, child: Icon(Icons.star, size: 11, color: C.blue)),
          Positioned(bottom: 3, left: 0, child: Icon(Icons.star, size: 11, color: C.blue)),
          Positioned(bottom: 1, right: 2, child: Icon(Icons.star, size: 11, color: C.blue)),
        ]),
      ),
    );
  }
}

/// Display-only metric card (no tap action).
class _Metric extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor, unitColor;
  final String name, value, unit, desc, foot1, foot2;
  final Color? foot2Color;
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
    this.foot2Color,
  });
  @override
  Widget build(BuildContext context) {
    return Panel(
      radius: 24,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.chevron_right, size: 18, color: C.mute)),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: const TextStyle(fontFamilyFallback: kMono, fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -1)),
            const SizedBox(width: 6),
            Text(unit, style: TextStyle(color: unitColor, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ),
        const SizedBox(height: 2),
        Text(desc, style: TextStyle(color: C.mute, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        Divider(color: C.line, height: 1),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 2, children: [
          Text(foot1, style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 11.5)),
          Text(foot2, style: TextStyle(fontFamilyFallback: kMono, color: foot2Color ?? C.mute, fontSize: 11.5)),
        ]),
      ]),
    );
  }
}
