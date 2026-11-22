import 'package:flutter/material.dart';
import '../core/appliance_data.dart';
import '../core/calc.dart';
import '../core/store.dart';
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
  bool bomOpen = true;
  final backup = TextEditingController();
  final scroll = ScrollController();
  final resultsKey = GlobalKey();

  AppState get s => widget.state;
  ApplCfg get cfg => s.appl;

  @override
  void initState() {
    super.initState();
    backup.text = cfg.backupHours;
  }

  @override
  void dispose() {
    backup.dispose();
    scroll.dispose();
    super.dispose();
  }

  // ---------- derived numbers ----------
  double get baseDaily => s.dailyLoad;
  double get monthly => baseDaily * 30 * cfg.profile.factor;
  double get daily => monthly / 30;
  double get connectedKw => s.appliances.fold(0.0, (a, e) => a + e.watts * e.qty) / 1000;

  SysOption option(SysType t) => buildOption(
        type: t,
        dailyKwh: daily,
        connectedKw: connectedKw,
        yieldPerKwp: s.locationYield,
        tariff: s.unitPrice,
        dcr: cfg.dcr,
        profile: cfg.profile,
        backupHours: cfg.hours,
      );

  void _commit() => s.saveAppl();

  void _setSys(SysType t) {
    cfg.sys = t;
    _commit();
  }

  void _calculate() {
    if (s.appliances.isEmpty) return toast(context, 'Add at least one appliance first');
    setState(() => calculated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = resultsKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.02);
    });
  }

  void _openEstimator() {
    final o = option(cfg.sys);
    final inp = EstimateInput(
      monthlyUnits: double.parse(monthly.toStringAsFixed(0)),
      coverage: 100,
      yieldPerKwDay: double.parse(s.locationYield.toStringAsFixed(2)),
      panelWp: 550,
      costPerKw: (o.gross / o.kwp).roundToDouble(),
      category: cfg.profile == LoadProfile.residential ? 'residential' : 'commercial',
      subsidy: cfg.dcr,
    );
    s.estimatePush = inp;
    s.publishEstimate(o.kwp, s.unitPrice);
    s.setTab(1);
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
    if (s.tab != 2) calculated = false; // results collapse when you leave the tab, like the reference
    final dark = s.isDark(DateTime.now());
    final psh = s.monthly?.forMonth(DateTime.now().month);
    final sub = calculated ? '${cfg.sys.label} · ${cfg.dcr ? 'DCR' : 'Non-DCR'} · ${monthly.round()} kWh/mo' : '${cfg.profile.label.toUpperCase()} · ${monthly.round()} kWh/mo';
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
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wb_cloudy_outlined, size: 18, color: C.orange),
              const SizedBox(width: 5),
              Text(psh == null ? '–' : '${psh.toStringAsFixed(1)}h', style: TextStyle(fontWeight: FontWeight.w800, color: C.sky)),
            ]),
          ),
          const SizedBox(width: 6),
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
            _profileCard(),
            _presetsCard(),
            _appliancesList(),
            _calcButton(),
            if (calculated) ...[
              KeyedSubtree(key: resultsKey, child: _moduleCard()),
              _optionsCard(),
              _interlinkCard(),
              _batteryBanner(),
              _bomCard(),
              _openButton(),
            ],
          ],
        ),
      ),
    ]);
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
  Widget _tile(String title, String sub, bool on, VoidCallback tap) => Expanded(
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
              FittedBox(fit: BoxFit.scaleDown, child: Text(title, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: on ? Colors.white : C.text))),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text(sub, maxLines: 1, style: TextStyle(fontSize: 12.5, color: on ? Colors.white.withValues(alpha: .9) : C.mute))),
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
              }),
              if (p != LoadProfile.industrial) const SizedBox(width: 8),
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
          ],
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

  // ---------- results ----------
  Widget _moduleCard() {
    final eligible = cfg.dcr;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipGreen, shape: BoxShape.circle), child: Icon(Icons.verified_user_outlined, color: C.green)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('MODULE STANDARD: DCR VS NON-DCR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
              Text('Controls PM Surya Ghar subsidy eligibility & per-kW panel Capex', style: TextStyle(color: C.mute, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: eligible ? C.chipGreen : C.chipBlue, borderRadius: BorderRadius.circular(14)),
            child: Text(eligible ? 'Subsidy Eligible' : 'Open Category', style: TextStyle(color: eligible ? C.green : C.sky, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: C.amber.withValues(alpha: .4))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cfg.dcr ? 'DCR (Made-in-India / ALMM)' : 'Non-DCR (Open Category)', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 3),
                Text(cfg.dcr ? 'Eligible for PM Surya Ghar subsidy (residential, grid-connected)' : 'Lower upfront equipment cost · open supply, no DBT subsidy', style: TextStyle(color: C.mute, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 8),
            _dcrSwitch(),
          ]),
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

  Widget _optionsCard() {
    final rec = recommend(cfg.profile, daily);
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
          decoration: BoxDecoration(color: C.amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: C.amber.withValues(alpha: .4))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.wb_sunny_outlined, color: C.orange, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14.5, height: 1.35), children: [
                TextSpan(text: 'Recommended (${rec.label}): ', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800)),
                TextSpan(text: recommendText(option(rec), cfg.profile, daily, connectedKw)),
              ])),
            ),
          ]),
        ),
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

  Widget _interlinkCard() {
    final o = option(cfg.sys);
    final mini = (IconData ic, Color ic2, String l, String v, Color vc, String sub) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(ic, size: 16, color: ic2), const SizedBox(width: 4), Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5)))]),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: TextStyle(color: vc, fontWeight: FontWeight.w800, fontSize: 15))),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(sub, maxLines: 1, style: _mono(11.5, C.mute, w: FontWeight.w500))),
            ]),
          ),
        );
    Widget chip(String t, bool on, VoidCallback tap) => GestureDetector(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: on ? C.green : C.chip, borderRadius: BorderRadius.circular(16)),
            child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: on ? Colors.white : C.text)),
          ),
        );
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: C.chipBlue, shape: BoxShape.circle), child: Icon(Icons.link, color: C.blue)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('3-WAY LIVE SYSTEM INTERLINK', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3)),
              Text('Application Load ↔ DCR/Non-DCR ↔ Architecture & BOM', style: TextStyle(color: C.mute, fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            mini(Icons.memory_outlined, C.green, '1. APPLICATION', cfg.profile.label, C.text, '${monthly.round()} kWh · ${connectedKw.toStringAsFixed(2)}kW'),
            const SizedBox(width: 8),
            mini(Icons.shield_outlined, C.orange, '2. MODULE', cfg.dcr ? 'DCR (ALMM)' : 'Non-DCR', C.green, '${o.panels} × ${o.kwp.toStringAsFixed(2)} kWp'),
            const SizedBox(width: 8),
            mini(Icons.bolt, C.orange, '3. SYSTEM', cfg.sys.label, C.orange, '${o.batteryKwh.toStringAsFixed(o.batteryKwh == 0 ? 0 : 1)} kWh ${o.batteryKwh == 0 ? 'Battery' : 'LFP'}'),
          ]),
        ),
        Divider(height: 24, color: C.line),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('App Type:', style: TextStyle(color: C.mute, fontWeight: FontWeight.w700)),
          for (final p in LoadProfile.values)
            chip(p.label, cfg.profile == p, () {
              cfg.profile = p;
              _commit();
            }),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18)), child: FittedBox(fit: BoxFit.scaleDown, child: _dcrSwitch()))),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                for (final t in SysType.values)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setSys(t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(color: cfg.sys == t ? C.orange : Colors.transparent, borderRadius: BorderRadius.circular(15)),
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text(t.label, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cfg.sys == t ? Colors.white : C.mute))),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
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
    final bom = buildBom(o, dcr: cfg.dcr, profile: cfg.profile);
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
            Expanded(flex: 2, child: Text(i.group, textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
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

  Widget _openButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: FilledButton(
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
