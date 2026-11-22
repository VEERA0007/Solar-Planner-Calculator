import 'package:flutter/material.dart';
import '../core/appliance_data.dart';
import '../core/calc.dart';
import '../core/store.dart';
import 'appliance_history.dart';
import 'pdf_appliance.dart';
import 'theme.dart';

TextStyle _mono(double size, Color color, {FontWeight w = FontWeight.w700}) =>
    TextStyle(fontFamilyFallback: kMono, fontSize: size, color: color, fontWeight: w);

String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Appliance Load Analysis: load profile, system type, appliance list, then
/// (after Calculate) module standard, the three system options, BOM and hand-off
/// to the Estimator.
class AppliancePage extends StatefulWidget {
  final AppState state;
  const AppliancePage({super.key, required this.state});
  @override
  State<AppliancePage> createState() => _AppliancePageState();
}

class _AppliancePageState extends State<AppliancePage> {
  bool calculated = false;
  String cat = 'All';
  String query = '';
  int bomTab = 0;
  bool bomOpen = false;
  bool siteOpen = false;
  String? savedSig;
  final backup = TextEditingController();
  final sanc = TextEditingController(), roof = TextEditingController(), cut = TextEditingController(), shade = TextEditingController();
  final scroll = ScrollController();
  final resultsKey = GlobalKey(), loadKey = GlobalKey(), cmpKey = GlobalKey(), bomKey = GlobalKey();
  late Analysis an;

  AppState get s => widget.state;
  ApplCfg get cfg => s.appl;

  @override
  void initState() {
    super.initState();
    backup.text = cfg.backupHours;
    String t(double v) => v == 0 ? '' : _n(v);
    sanc.text = t(cfg.sanctionedKw);
    roof.text = t(cfg.roofSqft);
    cut.text = t(cfg.cutHours);
    shade.text = t(cfg.shadePct);
    siteOpen = cfg.sanctionedKw > 0 || cfg.roofSqft > 0 || cfg.cutHours > 0 || cfg.shadePct > 0 || cfg.phase != 0;
    an = _analyze();
  }

  @override
  void dispose() {
    for (final c in [backup, sanc, roof, cut, shade]) {
      c.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  // ---------- derived numbers ----------
  List<LoadItem> get items => [for (final a in s.appliances) LoadItem(a.name, a.watts, a.qty, a.hours, a.start, backup: a.backup)];
  Analysis _analyze() => analyze(items: items, cfg: cfg, rates: s.rates, yieldPerKwp: s.locationYield, tariff: s.unitPrice);
  double get monthly => an.monthly;
  double get daily => an.daily;
  double get connectedKw => an.stats.connectedKw;
  SysOption option(SysType t) => an.of(t);

  void _commit() => s.saveAppl();

  void _setSys(SysType t) {
    cfg.sys = t;
    _commit();
  }

  ApplRecord _record({String? id, String? label}) {
    final o = an.selected;
    final n = s.applHistory.length + 1;
    return ApplRecord(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      at: DateTime.now().millisecondsSinceEpoch,
      label: label ?? 'Calculation $n · ${cfg.profile.label}',
      cfg: cfg.copy(),
      items: [for (final a in s.appliances) a.toJson()],
      monthly: an.monthly,
      kwp: o.kwp,
      invKw: o.invKw,
      batteryKwh: o.batteryKwh,
      gross: o.gross,
      subsidy: o.subsidy,
      savePerMonth: o.savePerMonth,
      payback: o.payback,
    );
  }

  String get _sig => _record().signature;
  bool get _isSaved => savedSig != null && savedSig == _sig;

  /// Saves the current result to history. The same inputs and result only refresh
  /// the time of the latest entry instead of adding a duplicate.
  void _saveHistory() {
    if (s.appliances.isEmpty) return;
    final r = _record();
    if (s.applHistory.isNotEmpty && s.applHistory.first.signature == r.signature) {
      s.applHistory.first.at = r.at;
    } else {
      s.applHistory.insert(0, r);
    }
    savedSig = r.signature;
    s.saveApplHistory();
  }

  void _calculate() {
    if (s.appliances.isEmpty) return toast(context, 'Add at least one appliance first');
    setState(() => calculated = true);
    _saveHistory();
    _scrollTo(resultsKey);
  }

  void _scrollTo(GlobalKey k) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = k.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.02);
    });
  }

  void _openEstimator() {
    _saveHistory();
    final o = option(cfg.sys);
    final inp = EstimateInput(
      monthlyUnits: double.parse(monthly.toStringAsFixed(0)),
      coverage: 100,
      yieldPerKwDay: double.parse(s.locationYield.toStringAsFixed(2)),
      panelWp: 550,
      costPerKw: (o.gross / o.kwp).roundToDouble(),
      category: cfg.profile == LoadProfile.residential ? 'residential' : 'commercial',
      subsidy: cfg.dcr && cfg.profile == LoadProfile.residential,
    );
    s.estimatePush = inp;
    s.publishEstimate(o.kwp, s.unitPrice);
    s.setTab(1);
  }

  Future<void> _shareProposal() async {
    _saveHistory();
    try {
      final bytes = await buildApplianceProposal(an: an, items: items, brand: s.brand, label: s.applHistory.isNotEmpty ? s.applHistory.first.label : 'Proposal', tariff: s.unitPrice);
      await shareApplianceProposal(bytes, s.applHistory.isNotEmpty ? s.applHistory.first.label : 'Proposal');
    } catch (e) {
      if (mounted) toast(context, 'Could not create the PDF: $e');
    }
  }

  Future<void> _shareRecord(ApplRecord r) async {
    final list = [for (final j in r.items) Appliance.fromJson(j)];
    final li = [for (final a in list) LoadItem(a.name, a.watts, a.qty, a.hours, a.start, backup: a.backup)];
    final a2 = analyze(items: li, cfg: r.cfg, rates: s.rates, yieldPerKwp: s.locationYield, tariff: s.unitPrice);
    try {
      final bytes = await buildApplianceProposal(an: a2, items: li, brand: s.brand, label: r.label, tariff: s.unitPrice);
      await shareApplianceProposal(bytes, r.label);
    } catch (e) {
      if (mounted) toast(context, 'Could not create the PDF: $e');
    }
  }

  /// Restores a saved calculation: appliances and settings come back and the
  /// results are recomputed with today's rates.
  void _restore(ApplRecord r) {
    s.appliances
      ..clear()
      ..addAll([for (final j in r.items) Appliance.fromJson(j)]);
    s.appl = r.cfg.copy();
    s.saveAppliances();
    s.saveAppl();
    backup.text = s.appl.backupHours;
    String t(double v) => v == 0 ? '' : _n(v);
    sanc.text = t(cfg.sanctionedKw);
    roof.text = t(cfg.roofSqft);
    cut.text = t(cfg.cutHours);
    shade.text = t(cfg.shadePct);
    setState(() {
      calculated = true;
      savedSig = null;
    });
    s.setTab(2);
    an = _analyze();
    savedSig = r.signature == _sig ? r.signature : null;
    _scrollTo(resultsKey);
  }

  void _openHistory() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (c) => ApplHistoryPage(
        state: s,
        onOpen: (r) {
          Navigator.of(c).pop();
          _restore(r);
        },
        onShare: _shareRecord,
      ),
    ));
  }

  Future<void> _edit(Appliance a, {bool isNew = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _EditSheet(a: a, isNew: isNew, onSave: () {
        if (isNew) s.appliances.add(a);
        s.saveAppliances();
      }),
    );
  }

  void _addPreset(Preset p) {
    s.appliances.add(Appliance(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: p.name,
      watts: p.watts,
      qty: 1,
      hours: p.hours,
      start: p.start,
    ));
    s.saveAppliances();
    toast(context, 'Added ${p.name} · tap the pencil to set quantity & usage');
  }

  @override
  Widget build(BuildContext context) {
    an = _analyze();
    final dark = s.isDark(DateTime.now());
    final psh = s.monthly?.forMonth(DateTime.now().month);
    final sub = calculated ? '${cfg.sys.label} · ${cfg.dcr ? 'DCR' : 'Non-DCR'} · ${monthly.round()} kWh/mo' : '${cfg.profile.label.toUpperCase()} · ${monthly.round()} kWh/mo';
    final count = s.applHistory.length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          IconButton(onPressed: () => s.setTab(0), icon: const Icon(Icons.arrow_back), tooltip: 'Home', visualDensity: VisualDensity.compact),
          const SizedBox(width: 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Appliance Load Analysis', maxLines: 1, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ),
          IconButton(onPressed: () => s.setDark(!dark), visualDensity: VisualDensity.compact, icon: Icon(dark ? Icons.wb_sunny_outlined : Icons.nightlight_outlined, color: dark ? C.sun : C.mute)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wb_cloudy_outlined, size: 17, color: C.orange),
              const SizedBox(width: 4),
              Text(psh == null ? '–' : '${psh.toStringAsFixed(1)}h', style: TextStyle(fontWeight: FontWeight.w800, color: C.sky)),
            ]),
          ),
          IconButton(
            key: const ValueKey('history-btn'),
            onPressed: _openHistory,
            tooltip: 'Calculation history',
            visualDensity: VisualDensity.compact,
            icon: Badge(isLabelVisible: count > 0, label: Text(count > 99 ? '99+' : '$count'), backgroundColor: C.orange, child: Icon(Icons.history, color: C.text)),
          ),
          InkWell(
            onTap: () => _edit(Appliance(id: DateTime.now().microsecondsSinceEpoch.toString(), name: 'New appliance', watts: 100, qty: 1, hours: 4, start: 18), isNew: true),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: C.green, shape: BoxShape.circle),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          children: [
            _summary(),
            _stepStrip(),
            KeyedSubtree(key: loadKey, child: _profileCard()),
            _presetsCard(),
            _appliancesList(),
            if (s.appliances.isNotEmpty) _curveCard(),
            if (s.appliances.isNotEmpty) _insightsCard(),
            _calcButton(),
            if (calculated) ...[
              KeyedSubtree(key: resultsKey, child: _statusRow()),
              KeyedSubtree(key: cmpKey, child: _systemCard()),
              _savingsCard(),
              _batteryBanner(),
              KeyedSubtree(key: bomKey, child: _bomCard()),
              _actionButtons(),
              _ratesCard(),
            ],
          ],
        ),
      ),
    ]);
  }

  // ---------- step strip ----------
  Widget _stepStrip() {
    final steps = [
      ('Load', Icons.electrical_services, loadKey, true),
      ('System', Icons.bolt, resultsKey, calculated),
      ('Compare', Icons.compare_arrows, cmpKey, calculated),
      ('BOM', Icons.inventory_2_outlined, bomKey, calculated),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (!steps[i].$4) return toast(context, 'Tap Calculate to unlock this step');
                if (i == 2) setState(() => bomOpen = bomOpen);
                if (i == 3) setState(() => bomOpen = true);
                _scrollTo(steps[i].$3);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: steps[i].$4 ? C.chipGreen : C.card2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: steps[i].$4 ? C.green.withValues(alpha: .6) : C.line),
                ),
                child: Column(children: [
                  Icon(steps[i].$2, size: 19, color: steps[i].$4 ? C.green : C.mute),
                  const SizedBox(height: 3),
                  Text('${i + 1}. ${steps[i].$1}', maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: steps[i].$4 ? C.green : C.mute)),
                ]),
              ),
            ),
          ),
          if (i < steps.length - 1) const SizedBox(width: 6),
        ],
      ]),
    );
  }

  // ---------- summary ----------
  Widget _summary() {
    final box = (String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .07), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .12))),
            child: Column(children: [
              SizedBox(height: 28, child: Center(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11, fontWeight: FontWeight.w800, height: 1.15)))),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: _mono(17, c))),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF035B4A), Color(0xFF05382F), Color(0xFF071A24)]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(calculated ? 'CALCULATED CONSUMPTION & SIZING' : 'APPLICATION ENERGY CONSUMPTION', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: .5, height: 1.25))),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: .18), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF10B981).withValues(alpha: .4))),
              child: Text(calculated ? '${cfg.sys.label} · ${cfg.dcr ? 'DCR' : 'Non-DCR'}' : cfg.profile.loadWord, textAlign: TextAlign.center, style: _mono(12.5, const Color(0xFF6EE7B7), w: FontWeight.w600)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('${monthly.round()}', style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                const Text('kWh/mo', style: TextStyle(color: Color(0xFF34D399), fontSize: 24, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Daily: ${daily.toStringAsFixed(2)} kWh', style: _mono(13, Colors.white70, w: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            box('CONNECTED LOAD', '${connectedKw.toStringAsFixed(2)} kW', const Color(0xFF7DD3FC)),
            const SizedBox(width: 8),
            if (calculated) ...[
              box('INVERTER', '${_n(option(cfg.sys).invKw)} kW', Colors.white),
              const SizedBox(width: 8),
              box('BATTERY BANK', option(cfg.sys).batteryKwh > 0 ? '${option(cfg.sys).batteryKwh.toStringAsFixed(1)} kWh' : 'Grid-Only', const Color(0xFFFBBF24)),
            ] else ...[
              box('APPLIANCES', '${s.appliances.length} Items', Colors.white),
              const SizedBox(width: 8),
              box('ANNUAL USAGE', '${inr0(monthly * 12)} kWh', const Color(0xFFFBBF24)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withValues(alpha: .12), height: 1),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.link, color: Color(0xFF34D399), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(calculated ? 'Synced live with Solar Estimator' : 'Configure appliances & calculate below', style: const TextStyle(color: Colors.white, fontSize: 14))),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: calculated ? _openEstimator : _calculate,
            icon: Icon(calculated ? Icons.arrow_forward : Icons.calculate_outlined, size: 20),
            label: Text(calculated ? 'Open Estimator' : 'Calculate', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFA000), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          ),
        ]),
      ]),
    );
  }

  String inr0(num v) {
    final t = rupee(v);
    return t.substring(1);
  }

  // ---------- profile & system type ----------
  Widget _tile(String title, String sub, bool on, VoidCallback tap, {bool small = false}) => Expanded(
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            decoration: BoxDecoration(
              color: on ? C.orange : C.card2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? C.orange : C.line),
              boxShadow: on ? [BoxShadow(color: C.orange.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 3))] : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(title, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 14.5 : 16, color: on ? Colors.white : C.text))),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text(sub, maxLines: 1, style: TextStyle(fontSize: small ? 11 : 12.5, color: on ? Colors.white.withValues(alpha: .9) : C.mute))),
            ]),
          ),
        ),
      );

  Widget _backupField() => TextField(
        controller: backup,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) {
          cfg.backupHours = v;
          _commit();
        },
        style: const TextStyle(fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: 'Enter backup hours based on inverter',
          filled: true,
          fillColor: C.card2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: C.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: C.line)),
        ),
      );

  Widget _numField(String label, String hint, TextEditingController c, void Function(double) set, {String? suffix}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) {
          set(double.tryParse(v.trim()) ?? 0);
          _commit();
        },
        decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      );

  Widget _siteDetails() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => siteOpen = !siteOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.home_work_outlined, color: C.blue, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Site details (optional)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text('Roof · sanctioned load · shade', style: TextStyle(color: C.mute, fontSize: 11.5)),
              Icon(siteOpen ? Icons.expand_less : Icons.expand_more, color: C.mute),
            ]),
          ),
        ),
        if (siteOpen) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _numField('Sanctioned load', 'kW', sanc, (v) => cfg.sanctionedKw = v, suffix: 'kW')),
            const SizedBox(width: 10),
            Expanded(child: _numField('Roof area', 'sq ft', roof, (v) => cfg.roofSqft = v, suffix: 'sq ft')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _numField('Power cuts', 'hours / day', cut, (v) => cfg.cutHours = v, suffix: 'h/day')),
            const SizedBox(width: 10),
            Expanded(child: _numField('Shading loss', '%', shade, (v) => cfg.shadePct = v.clamp(0, 60).toDouble(), suffix: '%')),
          ]),
          const SizedBox(height: 12),
          Text('SUPPLY PHASE', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final e in const [(0, 'Auto'), (1, 'Single-phase'), (2, 'Three-phase')])
              ChoiceChip(
                label: Text(e.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                selected: cfg.phase == e.$1,
                onSelected: (_) {
                  cfg.phase = e.$1;
                  _commit();
                },
              ),
          ]),
        ],
      ]);

  Widget _profileCard() => _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: C.chipBlue, shape: BoxShape.circle),
              child: Icon(Icons.bolt, color: C.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('APPLICATION PROFILE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: .4)),
                Text('Adjusts load profile & monthly energy usage across Solar Estimator', style: TextStyle(color: C.mute, fontSize: 13.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            for (final p in LoadProfile.values) ...[
              _tile(p.label, p.sub, cfg.profile == p, () {
                cfg.profile = p;
                _commit();
              }, small: true),
              if (p != LoadProfile.values.last) const SizedBox(width: 6),
            ],
          ]),
          Divider(height: 28, color: C.line),
          Row(children: [
            const Expanded(child: Text('System Type', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            Text(cfg.sys.status, style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final t in SysType.values) ...[
              _tile(t.label, t.sub, cfg.sys == t, () => _setSys(t)),
              if (t != SysType.offGrid) const SizedBox(width: 8),
            ],
          ]),
          if (cfg.sys.hasBattery) ...[
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.battery_charging_full, color: C.orange, size: 20),
              const SizedBox(width: 6),
              const Expanded(child: Text('Battery Backup (Hours)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text('Based on Inverter', style: TextStyle(color: C.mute, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            _backupField(),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(s.appliances.any((a) => a.backup) ? 'Battery is sized from the appliances marked Backup.' : 'Tip: mark the appliances that must run in a power cut with Backup, so the battery is sized from them.', style: TextStyle(color: C.mute, fontSize: 12.5)),
            ),
          ],
          Divider(height: 28, color: C.line),
          _siteDetails(),
        ]),
      );

  // ---------- presets ----------
  Widget _presetsCard() {
    final q = query.trim().toLowerCase();
    final list = [for (final p in kPresets) if ((cat == 'All' || p.cat == cat) && (q.isEmpty || p.name.toLowerCase().contains(q) || p.cat.toLowerCase().contains(q))) p];
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, color: C.orange, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('COMMON APPLIANCE PRESETS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3))),
          Text('1-Click Add', style: TextStyle(color: C.mute, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            hintText: 'Search ${kPresets.length}+ appliances (AC, pump, EV charger...)',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: C.card2,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.line)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in kPresetCats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(c, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cat == c ? Colors.white : C.mute)),
                  selected: cat == c,
                  showCheckmark: false,
                  selectedColor: C.blue,
                  backgroundColor: C.card2,
                  side: BorderSide(color: cat == c ? C.blue : C.line),
                  onSelected: (_) => setState(() => cat = c),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 230),
          child: list.isEmpty
              ? Padding(padding: const EdgeInsets.all(10), child: Text('No match. Use + to add a custom appliance.', style: TextStyle(color: C.mute)))
              : SingleChildScrollView(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in list)
                      ActionChip(
                        onPressed: () => _addPreset(p),
                        avatar: Icon(Icons.add, size: 18, color: C.blue),
                        label: Text.rich(TextSpan(children: [
                          TextSpan(text: p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: '  (${_n(p.watts)}W)', style: TextStyle(color: C.mute, fontSize: 12)),
                        ])),
                        backgroundColor: C.card2,
                        side: BorderSide(color: C.line),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }

  // ---------- configured appliances ----------
  Widget _appliancesList() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Row(children: [
            Expanded(child: Text('CONFIGURED APPLIANCES (${s.appliances.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: .3))),
            TextButton.icon(
              onPressed: () => _edit(Appliance(id: DateTime.now().microsecondsSinceEpoch.toString(), name: 'Custom appliance', watts: 100, qty: 1, hours: 4, start: 18), isNew: true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Custom Appliance', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        if (s.appliances.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('No appliances yet. Tap a preset above.', style: TextStyle(color: C.mute))),
        for (final a in s.appliances) _applianceCard(a),
      ]);

  Widget _applianceCard(Appliance a) {
    final perDay = a.watts * a.qty * a.hours / 1000;
    final perMo = perDay * 30 * cfg.profile.factor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(a.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(9)), child: Text('Qty: ${a.qty}', style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 12.5))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(9)), child: Text('230V · ${ampsFor(a.watts, a.qty).toStringAsFixed(1)}A', style: _mono(12.5, C.blue))),
            ]),
            const SizedBox(height: 6),
            Text('${_n(a.watts)} W · ${_n(a.hours)} hrs/day · 30 days/mo', style: TextStyle(color: C.mute, fontSize: 13.5)),
            if (cfg.sys.hasBattery || isMotorLoad(a.name)) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (cfg.sys.hasBattery)
                  GestureDetector(
                    onTap: () {
                      a.backup = !a.backup;
                      s.saveAppliances();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: a.backup ? C.orange : C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: a.backup ? C.orange : C.line)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(a.backup ? Icons.battery_charging_full : Icons.battery_0_bar, size: 15, color: a.backup ? Colors.white : C.mute),
                        const SizedBox(width: 4),
                        Text('Backup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: a.backup ? Colors.white : C.mute)),
                      ]),
                    ),
                  ),
                if (isMotorLoad(a.name)) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: C.chipSun, borderRadius: BorderRadius.circular(12)), child: Text('Motor · 3× start surge', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.orange))),
              ]),
            ],
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(perMo.toStringAsFixed(1), style: _mono(17, C.green)),
            const SizedBox(width: 3),
            Text('kWh/mo', style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          Text('${(perMo / 30).toStringAsFixed(2)} kWh/day', style: _mono(11.5, C.mute, w: FontWeight.w500)),
        ]),
        Column(children: [
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _edit(a), icon: Icon(Icons.edit_outlined, size: 20, color: C.mute), tooltip: 'Edit'),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              s.appliances.removeWhere((x) => x.id == a.id);
              s.saveAppliances();
            },
            icon: Icon(Icons.delete_outline, size: 20, color: C.mute),
            tooltip: 'Remove',
          ),
        ]),
      ]),
    );
  }

  Widget _calcButton() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        child: FilledButton(
          onPressed: _calculate,
          style: FilledButton.styleFrom(
            backgroundColor: C.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          ),
          child: const Row(children: [
            Icon(Icons.calculate_outlined, size: 24),
            SizedBox(width: 12),
            Expanded(child: Text('Calculate Application & View System Options', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, height: 1.25))),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 22),
          ]),
        ),
      );

  // ---------- load curve & insights ----------
  Widget _curveCard() {
    final st = an.stats;
    final o = an.of(cfg.sys);
    final gen = solarCurve(o.kwp * an.yieldEff);
    String hh(int h) => '${h % 12 == 0 ? 12 : h % 12}${h >= 12 ? 'pm' : 'am'}';
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipSun, shape: BoxShape.circle), child: Icon(Icons.show_chart, color: C.orange)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('24-HOUR LOAD vs SOLAR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
              Text('Shows how much of your load the panels can serve directly', style: TextStyle(color: C.mute, fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(painter: _CurvePainter(st.hourly, gen, C.blue, C.sun, C.mute, C.line)),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (final l in [('Load', C.blue), ('Solar (${o.kwp.toStringAsFixed(2)} kWp)', C.sun)]) ...[
            Container(width: 10, height: 10, decoration: BoxDecoration(color: l.$2, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(l.$1, style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 14),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill('Day ${(st.dayShare * 100).round()}% · Night ${100 - (st.dayShare * 100).round()}%', C.chipSun, C.orange),
          _pill('Peak ${st.peakKw.toStringAsFixed(2)} kW at ${hh(st.peakHour)}', C.chipBlue, C.sky),
          if (st.dayShare < .4 && cfg.sys == SysType.onGrid) _pill('Mostly night use: consider Hybrid', C.chip, C.mute),
        ]),
      ]),
    );
  }

  Widget _insightsCard() {
    final list = [for (final a in s.appliances) (a.name, a.watts * a.qty * a.hours / 1000)]..sort((a, b) => b.$2.compareTo(a.$2));
    final total = list.fold(0.0, (x, e) => x + e.$2);
    final tips = efficiencyTips(items, cfg.profile.factor);
    if (total <= 0) return const SizedBox();
    String panelsSaved(double kwhMonth) => (kwhMonth / 30 / an.yieldEff * 1000 / 550).toStringAsFixed(1);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipGreen, shape: BoxShape.circle), child: Icon(Icons.lightbulb_outline, color: C.green)),
          const SizedBox(width: 12),
          const Expanded(child: Text('WHERE YOUR POWER GOES', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3))),
        ]),
        const SizedBox(height: 12),
        for (final e in list.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${(e.$2 / total * 100).round()}%', style: _mono(13.5, C.orange)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: e.$2 / total, minHeight: 7, backgroundColor: C.chip, color: C.orange)),
            ]),
          ),
        if (tips.isNotEmpty) ...[
          Divider(height: 22, color: C.line),
          Text('SAVE ENERGY, NEED FEWER PANELS', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 8),
          for (final t in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.eco_outlined, size: 18, color: C.green),
                const SizedBox(width: 8),
                Expanded(child: Text(t.text, style: const TextStyle(fontSize: 14, height: 1.3))),
                const SizedBox(width: 8),
                Text('-${t.kwhMonth.round()} kWh/mo\n≈ ${panelsSaved(t.kwhMonth)} panels', textAlign: TextAlign.right, style: _mono(11.5, C.green, w: FontWeight.w600)),
              ]),
            ),
        ],
      ]),
    );
  }

  // ---------- results ----------
  Widget _statusRow() {
    final saved = _isSaved;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(color: (saved ? C.green : C.orange).withValues(alpha: .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: (saved ? C.green : C.orange).withValues(alpha: .45))),
      child: Row(children: [
        Icon(saved ? Icons.check_circle_outline : Icons.edit_note, color: saved ? C.green : C.orange, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text(saved ? 'Saved to history' : 'Changed since saved', style: TextStyle(fontWeight: FontWeight.w800, color: saved ? C.green : C.orange))),
        TextButton(
          onPressed: saved
              ? _openHistory
              : () {
                  setState(_saveHistory);
                  toast(context, 'Saved to history');
                },
          child: Text(saved ? 'View history' : 'Save now', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _dcrSwitch() => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('DCR', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 13)),
        Switch(
          value: !cfg.dcr,
          onChanged: (v) {
            cfg.dcr = !v;
            _commit();
          },
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStatePropertyAll(C.amber),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        Text('Non-DCR', style: TextStyle(color: C.text, fontWeight: FontWeight.w800, fontSize: 13)),
      ]);

  Widget _noteBox(IconData ic, Color c, Widget child) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: c.withValues(alpha: .4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(ic, color: c, size: 22), const SizedBox(width: 10), Expanded(child: child)]),
      );

  Widget _systemCard() {
    final rec = recommend(cfg.profile, daily, cutHours: cfg.cutHours);
    final sel = an.selected;
    final eligible = cfg.profile == LoadProfile.residential && cfg.dcr && cfg.sys != SysType.offGrid;
    final warns = limitWarnings(sel, cfg);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipSun, shape: BoxShape.circle), child: Icon(Icons.battery_charging_full, color: C.orange)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SYSTEM OPTIONS BY CONSUMPTION (${daily.toStringAsFixed(2)} KWH/DAY)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
              Text('Compare inverter type, added battery bank & net cost for On-Grid, Off-Grid & Hybrid', style: TextStyle(color: C.mute, fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('MODULE STANDARD', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .4))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: eligible ? C.chipGreen : C.chipBlue, borderRadius: BorderRadius.circular(12)),
                child: Text(eligible ? 'Subsidy Eligible' : (cfg.dcr ? 'DCR Modules' : 'Open Category'), style: TextStyle(color: eligible ? C.green : C.sky, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cfg.dcr ? 'DCR (Made-in-India / ALMM)' : 'Non-DCR (Open Category)', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 3),
                  Text(cfg.dcr ? 'Required for the PM Surya Ghar subsidy' : 'Lower upfront cost · no DBT subsidy', style: TextStyle(color: C.mute, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 8),
              _dcrSwitch(),
            ]),
            const SizedBox(height: 8),
            Text(subsidyNote(cfg.profile, cfg.dcr, cfg.sys), style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.35)),
          ]),
        ),
        _noteBox(
          Icons.wb_sunny_outlined,
          C.amber,
          Text.rich(TextSpan(style: const TextStyle(fontSize: 14.5, height: 1.35), children: [
            TextSpan(text: 'Recommended (${rec.label}): ', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800)),
            TextSpan(text: recommendText(option(rec), cfg.profile, daily, connectedKw, cutHours: cfg.cutHours)),
          ])),
        ),
        for (final w in warns) _noteBox(Icons.warning_amber_rounded, C.red, Text(w, style: const TextStyle(fontSize: 14, height: 1.35))),
        if (cfg.sys.hasBattery) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Row(children: [
              const Text('Battery Backup:', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: backup,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  onChanged: (v) {
                    cfg.backupHours = v;
                    _commit();
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter hrs (inverter)',
                    isDense: true,
                    filled: true,
                    fillColor: C.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: C.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: C.line)),
                  ),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        for (final t in SysType.values) _optionCard(option(t), t == rec),
      ]),
    );
  }

  Widget _optionCard(SysOption o, bool best) {
    final sel = cfg.sys == o.type;
    final title = '${o.type.label} System';
    final sub = const ['Lowest Capex · Net Metering Export', 'Grid Export + Instant Battery Backup', '100% Standalone · Zero Grid Dependency'][o.type.index];
    final warn = limitWarnings(o, cfg).isNotEmpty;
    final mini = (String l, String v, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .3)),
              const SizedBox(height: 3),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w800))),
            ]),
          ),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setSys(o.type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? C.orange.withValues(alpha: .08) : C.card2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: sel ? C.orange : C.line, width: sel ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(sel ? Icons.check_circle_outline : Icons.circle_outlined, color: sel ? C.orange : C.mute, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (best) _pill('Best Match', C.chipGreen, C.green),
                  if (sel) _pill('Selected', C.orange, Colors.white),
                  if (warn) _pill('Site limit', C.red.withValues(alpha: .2), C.red),
                ]),
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub, style: TextStyle(color: C.mute, fontSize: 13.5))),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rupee(o.net), style: _mono(18, C.text)),
              Text(o.subsidy > 0 ? 'Net after -${rupee(o.subsidy)} subsidy' : (o.type == SysType.offGrid ? 'Standalone (0 Subsidy)' : 'Turnkey Cost'), textAlign: TextAlign.right, style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            mini('PV ARRAY (${cfg.dcr ? 'DCR' : 'NON-DCR'})', '${o.kwp.toStringAsFixed(2)} kWp (${o.panels} nos)', C.text),
            const SizedBox(width: 8),
            mini('INVERTER', o.invLabel, C.blue),
            const SizedBox(width: 8),
            mini('BATTERIES', o.batteryKwh > 0 ? '${o.batteryKwh.toStringAsFixed(1)} kWh LFP' : 'None (0 kWh)', C.text),
          ]),
          const SizedBox(height: 10),
          Divider(height: 1, color: C.line),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(const ['Grid-Tied String MPPT Inverter', 'Bidirectional Hybrid MPPT (<10ms UPS)', 'Off-Grid Pure Sine MPPT PCU'][o.type.index], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 12.5))),
            const SizedBox(width: 6),
            Text('Save ${rupee(o.savePerMonth)}/mo · ${o.payback.toStringAsFixed(1)} Yrs', style: _mono(12.5, C.green)),
          ]),
        ]),
      ),
    );
  }

  Widget _pill(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
      );

  Widget _savingsCard() {
    final o = an.selected;
    final e = economics(o, an.monthly);
    Widget box(String l, String v, Color c, {String? sub}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11)),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16))),
              if (sub != null) Text(sub, style: TextStyle(color: C.mute, fontSize: 11)),
            ]),
          ),
        );
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipGreen, shape: BoxShape.circle), child: Icon(Icons.savings_outlined, color: C.green)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CUSTOMER SAVINGS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
              Text('${o.type.label} · ${o.kwp.toStringAsFixed(2)} kWp', style: TextStyle(color: C.mute, fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            box('BILL BEFORE', '${rupee(e.billBefore / 12)}/mo', C.red),
            const SizedBox(width: 8),
            box('BILL AFTER', '${rupee(e.billAfter / 12)}/mo', C.green),
          ]),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            box('SAVING / YEAR', rupee(e.saveYear), C.green),
            const SizedBox(width: 8),
            box('25-YEAR SAVING', rupee(e.save25), C.orange, sub: '3% tariff rise'),
            const SizedBox(width: 8),
            box('CO₂ AVOIDED', '${(e.co2Year / 1000).toStringAsFixed(1)} t/yr', C.sky),
          ]),
        ),
      ]),
    );
  }

  Widget _batteryBanner() {
    final t = cfg.sys;
    final (Color c, String title, String tag, String body) = switch (t) {
      SysType.onGrid => (C.green, 'Battery Not Required (Removed)', 'NO BATTERY NEEDED', 'Utility grid acts as virtual storage via Bi-Directional Net Metering. All battery packs, racks, and BMS components are automatically removed from this On-Grid BOM.'),
      SysType.hybrid => (C.orange, 'Battery Backup Required (Enter Hours)', 'BATTERY INCLUDED', 'Enter your battery backup value based on your ${_n(option(t).invKw)} kW inverter to size the Hybrid battery bank for power-cut backup.'),
      SysType.offGrid => (C.orange, 'Battery Backup Required (Enter Hours)', 'BATTERY INCLUDED', 'Enter your battery backup value based on your ${_n(option(t).invKw)} kW inverter to size the Off-Grid battery bank.'),
    };
    Widget cell(SysType x, String head, String desc, Color hc) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: t == x ? C.card : C.card.withValues(alpha: .4), borderRadius: BorderRadius.circular(16), border: Border.all(color: t == x ? hc : C.line, width: t == x ? 1.6 : 1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(head, style: TextStyle(color: hc, fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(desc, style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.25)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: .09), borderRadius: BorderRadius.circular(22), border: Border.all(color: c.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.battery_charging_full, color: c, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: t == SysType.onGrid ? C.green : C.orange, borderRadius: BorderRadius.circular(14)), child: Text(tag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11))),
        ]),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(fontSize: 14.5, height: 1.4)),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cell(SysType.onGrid, 'On-Grid', 'Battery NOT needed (Grid Net Meter)', C.green),
            const SizedBox(width: 8),
            cell(SysType.hybrid, 'Hybrid', 'Needed only for power-cut backup', C.orange),
            const SizedBox(width: 8),
            cell(SysType.offGrid, 'Off-Grid', 'Mandatory (No grid night power)', C.red),
          ]),
        ),
      ]),
    );
  }

  Widget _bomCard() {
    final o = option(cfg.sys);
    final bom = buildBom(o, dcr: cfg.dcr, profile: cfg.profile, rates: s.rates);
    const tabs = ['All Parts', 'PV, Inv & Battery', 'BOS & Structure', 'Meters & Docs'];
    final shown = [for (final i in bom.items) if (bomTab == 0 || i.tab == bomTab - 1) i];
    final counts = [bom.items.length, for (var k = 0; k < 3; k++) bom.items.where((i) => i.tab == k).length];
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => bomOpen = !bomOpen),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipGreen, shape: BoxShape.circle), child: Icon(Icons.inventory_2_outlined, color: C.green)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('REQUIRED PARTS & BOM (${bom.items.length} ACTIVE)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
                Text('${cfg.sys.label} · ${cfg.dcr ? 'DCR ALMM' : 'Non-DCR'} · ${o.threePhase ? '3-Phase 415V' : '1-Phase 230V'}', style: TextStyle(color: C.mute, fontSize: 13)),
              ]),
            ),
            if (bom.removed.isNotEmpty) Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(12)), child: Text('${bom.removed.length} Auto-Removed', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11.5))),
            Icon(bomOpen ? Icons.expand_less : Icons.expand_more, color: C.mute),
          ]),
        ),
        if (bomOpen) ...[
          if (bom.removed.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.cancel_outlined, color: C.mute, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14, height: 1.35), children: [
                  TextSpan(text: 'Automatically Removed for ${cfg.sys.label}: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: bom.removed.join(' · ')),
                ]))),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => bomTab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: bomTab == i ? (C.dark ? Colors.white : const Color(0xFF0F172A)) : C.card2, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
                      child: Text('${tabs[i]} (${counts[i]})', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: bomTab == i ? (C.dark ? Colors.black : Colors.white) : C.text)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          for (final i in shown) _bomItem(i),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.chipSun, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Expanded(child: Text('Total system price', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(rupee(bom.total), style: _mono(18, C.orange)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _bomItem(BomItem i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline, color: C.green, size: 24),
            const Spacer(),
            Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(12)), child: Text(i.qty, textAlign: TextAlign.center, style: _mono(12.5, C.green)))),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(i.group, textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5)),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: Text(rupee(i.price), style: _mono(15, C.orange))),
              ]),
            ),
          ]),
          Padding(padding: const EdgeInsets.only(left: 12, top: 4), child: Text(i.spec, style: TextStyle(color: C.mute, fontSize: 13.5, height: 1.35))),
          Divider(height: 20, color: C.line),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.description_outlined, size: 18, color: C.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(i.why, style: TextStyle(color: C.mute, fontSize: 13, height: 1.35))),
          ]),
        ]),
      );

  Widget _actionButtons() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Column(children: [
        OutlinedButton.icon(
          onPressed: _shareProposal,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Share proposal PDF (with BOM & prices)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), foregroundColor: C.orange, side: BorderSide(color: C.orange), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _openEstimator,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF059669),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text('Open ${cfg.sys.label} (${cfg.dcr ? 'DCR' : 'Non-DCR'} · ${monthly.round()} kWh) in Estimator', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25))),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 22),
          ]),
        ),
      ]),
    );
  }

  Widget _ratesCard() {
    final r = s.rates;
    String when() {
      if (r.updated == 0) return 'Default rates · not edited yet';
      return 'Rates updated on ${historyDate(r.updated).split(' · ').first}';
    }
    Widget row(String k, double v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: C.mute, fontSize: 13.5))), Text(rupee(v), style: _mono(13.5, C.text))]),
        );
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipBlue, shape: BoxShape.circle), child: Icon(Icons.price_change_outlined, color: C.blue)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PRICE LIST USED', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
              Text(when(), style: TextStyle(color: r.updated == 0 ? C.orange : C.mute, fontSize: 13)),
            ]),
          ),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: C.card,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
              builder: (_) => _RatesSheet(state: s),
            ),
            child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        row('DCR system (per kWp)', r.dcr),
        row('Non-DCR system (per kWp)', r.nonDcr),
        row('Hybrid extra (per kWp)', r.hybridExtra),
        row('Off-Grid extra (per kWp)', r.offExtra),
        row('Battery (per kWh)', r.battery),
      ]),
    );
  }
}

/// Paints 24 load bars with the solar generation line over them.
class _CurvePainter extends CustomPainter {
  final List<double> load, gen;
  final Color barColor, genColor, text, grid;
  _CurvePainter(this.load, this.gen, this.barColor, this.genColor, this.text, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0;
    final h = size.height - bottom, w = size.width;
    final maxV = [...load, ...gen, 0.1].reduce((a, b) => a > b ? a : b) * 1.12;
    final gp = Paint()..color = grid..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final y = h - h * k / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), gp);
    }
    final bw = w / 24;
    final bp = Paint()..color = barColor.withValues(alpha: .75);
    for (var i = 0; i < 24; i++) {
      final bh = load[i] / maxV * h;
      if (bh > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * bw + 1.5, h - bh, bw - 3, bh), const Radius.circular(3)), bp);
    }
    final path = Path();
    for (var i = 0; i < 24; i++) {
      final x = i * bw + bw / 2, y = h - gen[i] / maxV * h;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = genColor..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);
    for (final hr in [0, 6, 12, 18, 23]) {
      final label = hr == 0 ? '12a' : hr == 12 ? '12p' : hr > 12 ? '${hr - 12}p' : '${hr}a';
      final tp = TextPainter(text: TextSpan(text: label, style: TextStyle(color: text, fontSize: 10.5)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset((hr * bw + bw / 2 - tp.width / 2).clamp(0, w - tp.width), h + 3));
    }
  }

  @override
  bool shouldRepaint(_CurvePainter o) => true;
}

/// Edit the price list. Saving stamps the "updated on" date.
class _RatesSheet extends StatefulWidget {
  final AppState state;
  const _RatesSheet({required this.state});
  @override
  State<_RatesSheet> createState() => _RatesSheetState();
}

class _RatesSheetState extends State<_RatesSheet> {
  late final List<TextEditingController> c;
  @override
  void initState() {
    super.initState();
    final r = widget.state.rates;
    c = [for (final v in [r.dcr, r.nonDcr, r.hybridExtra, r.offExtra, r.battery]) TextEditingController(text: _n(v))];
  }

  @override
  void dispose() {
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  void _save({bool reset = false}) {
    double v(int i, double d) => double.tryParse(c[i].text.trim()) ?? d;
    const d = Rates();
    widget.state.rates = reset
        ? const Rates()
        : Rates(dcr: v(0, d.dcr), nonDcr: v(1, d.nonDcr), hybridExtra: v(2, d.hybridExtra), offExtra: v(3, d.offExtra), battery: v(4, d.battery), updated: DateTime.now().millisecondsSinceEpoch);
    widget.state.saveRates();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['DCR system (₹ per kWp)', 'Non-DCR system (₹ per kWp)', 'Hybrid extra (₹ per kWp)', 'Off-Grid extra (₹ per kWp)', 'Battery (₹ per kWh)'];
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Edit price list', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          Text('Every quote and BOM uses these rates. Saving records today as the update date.', style: TextStyle(color: C.mute, fontSize: 13)),
          const SizedBox(height: 12),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(controller: c[i], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: labels[i], isDense: true)),
            ),
          Row(children: [
            TextButton(onPressed: () => _save(reset: true), child: const Text('Reset to default')),
            const Spacer(),
            FilledButton(onPressed: _save, style: FilledButton.styleFrom(backgroundColor: C.orange), child: const Text('Save rates', style: TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ]),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: C.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: C.dark ? .25 : .05), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: child,
      );
}

/// Bottom sheet to add or edit one appliance. Rating chips and usage chips
/// suggest the wattage and the daily hours.
class _EditSheet extends StatefulWidget {
  final Appliance a;
  final bool isNew;
  final VoidCallback onSave;
  const _EditSheet({required this.a, required this.isNew, required this.onSave});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController name, watts, qty, hours, start;
  Preset? preset;

  @override
  void initState() {
    super.initState();
    final a = widget.a;
    name = TextEditingController(text: a.name);
    watts = TextEditingController(text: _n(a.watts));
    qty = TextEditingController(text: '${a.qty}');
    hours = TextEditingController(text: _n(a.hours));
    start = TextEditingController(text: '${a.start}');
    preset = presetFor(a.name);
  }

  @override
  void dispose() {
    for (final c in [name, watts, qty, hours, start]) {
      c.dispose();
    }
    super.dispose();
  }

  double get w => double.tryParse(watts.text) ?? 0;
  int get q => (int.tryParse(qty.text) ?? 1).clamp(1, 1000);
  double get h => (double.tryParse(hours.text) ?? 0).clamp(0, 24).toDouble();

  void _save() {
    final a = widget.a;
    a.name = name.text.trim().isEmpty ? 'Appliance' : name.text.trim();
    a.watts = w.clamp(0, 1000000).toDouble();
    a.qty = q;
    a.hours = h;
    a.start = (int.tryParse(start.text) ?? 0).clamp(0, 23);
    widget.onSave();
    Navigator.pop(context);
  }

  Widget _field(String label, TextEditingController c, {bool decimal = false, int flex = 1}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final kwhDay = w * q * h / 1000;
    final p = preset;
    Widget chipRow(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: chips),
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.isNew ? 'Add appliance' : 'Edit appliance', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          TextField(
            controller: name,
            onChanged: (v) => setState(() => preset = presetFor(v)),
            decoration: const InputDecoration(labelText: 'Appliance name'),
          ),
          const SizedBox(height: 10),
          Row(children: [_field('Watts (each)', watts, decimal: true, flex: 2), _field('Qty', qty), _field('Hours/day', hours, decimal: true, flex: 2), _field('Start hr', start)]),
          if (p != null && p.variants.isNotEmpty)
            chipRow('SUGGESTED RATINGS', [
              for (final v in p.variants)
                ChoiceChip(
                  label: Text('${v.$1} · ${_n(v.$2)}W', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  selected: (w - v.$2).abs() < .5,
                  onSelected: (_) => setState(() => watts.text = _n(v.$2)),
                ),
            ]),
          chipRow('USAGE LEVEL (SETS HOURS PER DAY)', [
            for (final u in const [('Light', .6), ('Normal', 1.0), ('Heavy', 1.5)])
              ActionChip(
                label: Text(u.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                onPressed: () {
                  final base = p?.hours ?? widget.a.hours;
                  setState(() => hours.text = _n(double.parse((base * u.$2).clamp(0, 24).toStringAsFixed(1))));
                },
              ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Row(children: [
              Icon(Icons.bolt, color: C.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${kwhDay.toStringAsFixed(2)} kWh/day · ${(kwhDay * 30).toStringAsFixed(1)} kWh/mo · ${ampsFor(w, q).toStringAsFixed(1)} A', style: _mono(13.5, C.text))),
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: C.orange, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: Text(widget.isNew ? 'Add appliance' : 'Save changes', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }
}
