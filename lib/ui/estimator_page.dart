import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/appliance_data.dart';
import '../core/calc.dart';
import '../core/estimator_data.dart';
import '../core/store.dart';
import 'pdf_quote.dart';
import 'theme.dart';

/// Solar Estimator: New Install flow (inputs, system, cost, ROI, customer page),
/// Existing Plant (next build) and Generation.
class EstimatorPage extends StatefulWidget {
  final AppState state;
  const EstimatorPage({super.key, required this.state});
  @override
  State<EstimatorPage> createState() => _EstimatorPageState();
}

class _EstimatorPageState extends State<EstimatorPage> {
  int tab = 0; // 0 New Install, 1 Existing Plant, 2 Generation
  int stage = 0; // 0 form, 1 results, 2 ROI, 3 customer page, 4 saved
  String mode = 'units'; // units | bill | usc
  String category = 'residential';
  bool dcr = true;
  SysType sys = SysType.onGrid;
  int panelIdx = 1;
  bool billHelp = false;
  bool custOpen = false;
  double escalation = 3, omPct = 1;
  bool yearly = false;
  Map<SysType, SysOption> opts = {};
  String uscMsg = '';
  Color uscColor = C.mute;

  final units = TextEditingController(text: '400');
  final bill = TextEditingController();
  final usc = TextEditingController();
  final roof = TextEditingController();
  final backup = TextEditingController();
  final inverterBrand = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final search = TextEditingController();

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final p = s.profile;
    usc.text = p.serviceNo;
    name.text = p.name;
    phone.text = p.mobile;
    address.text = p.address;
    _takePush();
  }

  @override
  void didUpdateWidget(covariant EstimatorPage old) {
    super.didUpdateWidget(old);
    if (s.estimatePush != null) setState(_takePush);
  }

  @override
  void dispose() {
    for (final c in [units, bill, usc, roof, backup, inverterBrand, name, phone, address, search]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Appliance Analysis hands its chosen system over through the app state.
  void _takePush() {
    final push = s.estimatePush;
    if (push == null) return;
    s.estimatePush = null;
    _fill(push);
    tab = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calc();
    });
  }

  String _t(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  void _fill(EstimateInput d) {
    mode = 'units';
    units.text = _t(d.monthlyUnits.round());
    category = const ['residential', 'commercial', 'agricultural'].contains(d.category) ? d.category : 'residential';
    dcr = d.dcr;
    sys = SysType.values[d.sys.clamp(0, 2)];
    backup.text = d.backupHours > 0 ? _t(d.backupHours) : '';
    final list = panelsFor(dcr);
    var best = 0;
    for (var i = 0; i < list.length; i++) {
      if ((list[i].wp - d.panelWp).abs() < (list[best].wp - d.panelWp).abs()) best = i;
    }
    panelIdx = best;
    escalation = d.escalation;
    omPct = d.omPct > 0 ? d.omPct : 1;
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  UscHistory? get _hist => s.uscHistory[normalizeUsc(usc.text)];

  double get _monthlyUnits {
    switch (mode) {
      case 'bill':
        return s.tariffCat.unitsForBill(_num(bill));
      case 'usc':
        return _hist?.average ?? 0;
      default:
        return _num(units);
    }
  }

  PanelModel get _panel {
    final l = panelsFor(dcr);
    return l[panelIdx.clamp(0, l.length - 1)];
  }

  LoadProfile get _profile => category == 'commercial' ? LoadProfile.commercial : (category == 'agricultural' ? LoadProfile.agricultural : LoadProfile.residential);

  Map<SysType, SysOption> _options(double u) {
    final daily = u / 30;
    final marginal = s.tariffCat.marginal(u);
    return {
      for (final t in SysType.values)
        t: buildOption(
          type: t,
          dailyKwh: daily,
          connectedKw: daily / 5,
          yieldPerKwp: s.locationYield,
          tariff: marginal,
          dcr: dcr,
          profile: _profile,
          backupHours: _num(backup),
          panelWp: _panel.wp.toDouble(),
          rates: s.rates,
        )
    };
  }

  Customer _readCustomer() => Customer(usc: normalizeUsc(usc.text), name: name.text.trim(), phone: phone.text.trim(), address: address.text.trim());

  /// Builds the three options and the savings result. [go] opens the results page.
  void _calc({bool go = true}) {
    final u = _monthlyUnits;
    if (!(u > 0)) {
      if (go) toast(context, mode == 'usc' ? 'Enter the 13-month units for this USC first' : 'Enter monthly units or bill');
      return;
    }
    final plan = s.tariffCat;
    opts = _options(u);
    final o = opts[sys]!;
    final y = s.locationYield;
    final off = (o.kwp * y * 30) < u ? o.kwp * y * 30 : u;
    final eff = off > 0 ? (plan.bill(u) - plan.bill(u - off)) / off : plan.marginal(u);
    final inp = EstimateInput(
      mode: 'units',
      monthlyUnits: u,
      monthlyBill: plan.bill(u),
      tariff: double.parse(eff.toStringAsFixed(2)),
      coverage: 100,
      yieldPerKwDay: double.parse(y.toStringAsFixed(2)),
      panelWp: _panel.wp.toDouble(),
      costPerKw: o.gross / o.kwp,
      category: category,
      subsidy: o.subsidy > 0,
      escalation: escalation,
      omPct: omPct,
      panelsOverride: o.panels,
      dcr: dcr,
      sys: sys.index,
      backupHours: _num(backup),
    );
    s.input = inp;
    s.customer = _readCustomer();
    s.result = calculate(inp);
    s.publishEstimate(s.result!.kw, inp.tariff);
    if (go) {
      setState(() => stage = 1);
    } else {
      setState(() {});
    }
  }

  void _recalc() {
    if (s.result != null) _calc(go: false);
  }

  void _save() {
    final r = s.result;
    if (r == null) return;
    final c = _readCustomer();
    if (c.usc.isEmpty && c.name.isEmpty) {
      toast(context, 'Add a USC number or customer name first (Customer details on the Estimate page)');
      setState(() {
        stage = 0;
        custOpen = true;
      });
      return;
    }
    final idx = c.usc.isNotEmpty ? s.records.indexWhere((x) => normalizeUsc(x.customer.usc) == c.usc && x.customer.name == c.name) : -1;
    final rec = SavedRecord(
      id: idx >= 0 ? s.records[idx].id : DateTime.now().millisecondsSinceEpoch.toString(),
      savedAt: DateTime.now().millisecondsSinceEpoch,
      customer: c,
      input: s.input.copy(),
    );
    if (idx >= 0) {
      s.records[idx] = rec;
    } else {
      s.records.insert(0, rec);
    }
    s.saveRecords();
    toast(context, idx >= 0 ? 'Estimate updated' : 'Estimate saved');
  }

  Future<void> _quote(Customer c, EstimateResult r) async {
    try {
      await shareQuote(c, r, s.brand);
    } catch (e) {
      if (mounted) toast(context, 'Could not create PDF: $e');
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _load(SavedRecord r) {
    usc.text = r.customer.usc;
    name.text = r.customer.name;
    phone.text = r.customer.phone;
    address.text = r.customer.address;
    _fill(r.input);
  }

  void _uscChanged(String _) {
    final v = normalizeUsc(usc.text);
    setState(() {
      if (v.isEmpty) {
        uscMsg = '';
      } else if (plausibleUsc(v)) {
        uscMsg = 'Valid USC format (${v.length} digits).';
        uscColor = C.green;
      } else {
        uscMsg = 'USC numbers are 8 to 12 digits. Check the number on the bill.';
        uscColor = C.amber;
      }
    });
  }

  void _uscSearch() {
    final v = normalizeUsc(usc.text);
    if (v.isEmpty) {
      setState(() {
        uscMsg = 'Enter a USC number to search.';
        uscColor = C.amber;
      });
      return;
    }
    final exact = s.records.where((r) => normalizeUsc(r.customer.usc) == v).toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    if (exact.isNotEmpty) {
      _load(exact.first);
      setState(() {
        uscMsg = 'Found a saved estimate for ${exact.first.customer.name.isEmpty ? 'this USC' : exact.first.customer.name} (${exact.length} saved). Details filled in.';
        uscColor = C.green;
      });
      toast(context, 'USC found, details loaded');
      return;
    }
    setState(() {
      uscMsg = _hist == null ? 'No saved data for this USC yet. Enter the 13-month units from the bill.' : 'History found for this USC.';
      uscColor = C.amber;
    });
  }

  Future<void> _editHistory() async {
    final v = normalizeUsc(usc.text);
    if (v.isEmpty) return toast(context, 'Enter the USC number first');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _UscSheet(state: s, usc: v),
    );
    if (mounted) setState(() {});
  }

  // ---------- small building blocks ----------
  Widget _title(IconData ic, Color c, String t, String sub) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: c.withValues(alpha: .15), shape: BoxShape.circle), child: Icon(ic, color: c, size: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.3)),
          ]),
        ),
      ]);

  Widget _gap([double h = 14]) => SizedBox(height: h);

  Widget _chip(String label, bool on, VoidCallback tap, {String? sub}) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(color: on ? C.orange : C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? C.orange : C.line)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: on ? Colors.white : C.text))),
              if (sub != null) FittedBox(fit: BoxFit.scaleDown, child: Text(sub, maxLines: 1, style: TextStyle(fontSize: 11, color: on ? Colors.white.withValues(alpha: .9) : C.mute))),
            ]),
          ),
        ),
      );

  Widget _field(TextEditingController c, String label, {String? hint, String? prefix, String? suffix, VoidCallback? onChanged, bool decimal = true}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        onChanged: (_) {
          setState(() {});
          onChanged?.call();
        },
        decoration: InputDecoration(labelText: label, hintText: hint, prefixText: prefix, suffixText: suffix, isDense: true),
      );

  Widget _note(IconData ic, Color c, String text) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, color: c, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ]),
      );

  Widget _stat(String l, String v, {Color? c, String? sub}) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, maxLines: 2, style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .3)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: TextStyle(color: c ?? C.text, fontSize: 19, fontWeight: FontWeight.w800))),
            if (sub != null) Text(sub, style: TextStyle(color: C.mute, fontSize: 11)),
          ]),
        ),
      );

  Widget _line(String l, String v, {bool bold = false, Color? c}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(l, style: TextStyle(color: bold ? C.text : C.mute, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 14))),
          const SizedBox(width: 8),
          Text(v, style: TextStyle(color: c ?? C.text, fontWeight: FontWeight.w800, fontSize: bold ? 16 : 14.5)),
        ]),
      );

  Widget _bigButton(String label, VoidCallback tap, {Color? color, IconData? icon}) => FilledButton(
        onPressed: tap,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: color ?? C.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20)],
        ]),
      );

  // ---------- page frame ----------
  @override
  Widget build(BuildContext context) {
    final sub = switch (tab) {
      1 => 'Existing Plant Audit & PR',
      2 => 'Power Generation & Yield',
      _ => switch (stage) {
          1 => 'Solar System Estimation',
          2 => 'Return on Investment Dashboard',
          3 => 'Your Solar Estimation',
          4 => 'Saved estimates',
          _ => 'Sizing, DCR Subsidy & Savings',
        },
    };
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          IconButton(
            onPressed: () {
              if (tab == 0 && stage > 0) {
                setState(() => stage = stage == 2 || stage == 3 ? 1 : 0);
              } else {
                s.setTab(0);
              }
            },
            icon: const Icon(Icons.arrow_back),
            visualDensity: VisualDensity.compact,
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Solar Estimator', maxLines: 1, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ),
          IconButton(
            key: const ValueKey('saved-btn'),
            onPressed: () => setState(() {
              tab = 0;
              stage = 4;
            }),
            tooltip: 'Saved estimates',
            visualDensity: VisualDensity.compact,
            icon: Badge(isLabelVisible: s.records.isNotEmpty, label: Text('${s.records.length}'), backgroundColor: C.orange, child: Icon(Icons.bookmark_border, color: C.text)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(14)),
            child: Text('INR (₹)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: _tabs()),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: switch (tab) {
            1 => _existing(),
            2 => _generation(),
            _ => switch (stage) {
                1 => s.result == null ? _form() : _results(),
                2 => s.result == null ? _form() : _roi(),
                3 => s.result == null ? _form() : _customerPage(),
                4 => _saved(),
                _ => _form(),
              },
          },
        ),
      ),
    ]);
  }

  Widget _tabs() {
    Widget t(int i, String a, String b) {
      final on = tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => tab = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(color: on ? C.card : Colors.transparent, borderRadius: BorderRadius.circular(16), border: on ? Border.all(color: C.line) : null),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(a, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: on ? C.orange : C.text))),
              FittedBox(fit: BoxFit.scaleDown, child: Text(b, maxLines: 1, style: TextStyle(fontSize: 11, color: on ? C.orange : C.mute))),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
      child: Row(children: [t(0, 'New Install', dcr ? 'DCR' : 'Non-DCR'), t(1, 'Existing Plant', 'Audit & Health'), t(2, 'Generation', 'Yield & Export')]),
    );
  }

  // ---------- 1. form ----------
  List<Widget> _form() {
    final plan = s.tariffCat;
    final u = _monthlyUnits;
    final quick = u > 0 ? _options(u)[SysType.onGrid] : null;
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.receipt_long_outlined, C.amber, 'Monthly Bills & Units Enquiry', 'Enter units, a bill amount, or use the USC history'),
          _gap(),
          Text('Monthly Consumption', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            _chip('Units (kWh)', mode == 'units', () => setState(() => mode = 'units')),
            _chip('Bill (₹)', mode == 'bill', () => setState(() => mode = 'bill')),
            _chip('USC Number', mode == 'usc', () => setState(() => mode = 'usc')),
          ]),
          const SizedBox(height: 12),
          if (mode == 'units') _field(units, 'Units / Month (kWh)'),
          if (mode == 'bill') _field(bill, 'Bill / Month (energy charges)', prefix: '₹ '),
          if (mode == 'usc') ..._uscBlock(),
          if (u > 0) ...[
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.st.name('en').split(' ').first.toUpperCase()} · ${plan.slabLabel(u)}', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${u.round()} kWh → ₹${groupIndian(plan.bill(u))}/mo (₹${plan.average(u).toStringAsFixed(2)}/kWh avg)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (quick != null) ...[
                  const SizedBox(height: 4),
                  Text('Suggested: ${quick.kwp.toStringAsFixed(2)} kWp (${quick.panels} × ${_panel.wp}W)', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ]),
            ),
          ],
          if (mode != 'usc') ...[
            const SizedBox(height: 12),
            Row(children: [
              for (final q in const [250, 400, 600])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      mode = 'units';
                      units.text = '$q';
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text('$q U (₹${groupIndian(plan.bill(q.toDouble()))})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                    ),
                  ),
                ),
            ]),
          ],
          if (mode == 'units') ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => mode = 'bill'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.amber.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.amber.withValues(alpha: .35))),
                child: Row(children: [
                  const Expanded(child: Text("Don't know your exact units? Calculate from bill", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                  Icon(Icons.expand_more, color: C.mute),
                ]),
              ),
            ),
          ],
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Electricity Cost Per Unit (₹/kWh)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(10)), child: Text(s.discom.name, style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11.5))),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Text(u > 0 ? plan.marginal(u).toStringAsFixed(2) : s.unitPrice.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          const SizedBox(height: 6),
          Text('${s.st.order}. Effective ${s.st.effective}. Energy charges only. Change state or category in Settings.', style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.3)),
          _gap(),
          Text('Roof Area in Square Meters (Optional)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field(roof, 'Roof area', suffix: 'sq m')),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => toast(context, 'Satellite roof map is planned for a later build'),
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: const Text('Map', style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: C.orange, side: BorderSide(color: C.orange.withValues(alpha: .6))),
            ),
          ]),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('System Type', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Text(sys.status, style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
          const SizedBox(height: 10),
          Row(children: [for (final t in SysType.values) _chip(t.label, sys == t, () => setState(() => sys = t), sub: t.sub)]),
          if (sys.hasBattery) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.battery_charging_full, color: C.orange, size: 19),
              const SizedBox(width: 6),
              const Expanded(child: Text('Battery Backup (Hours)', style: TextStyle(fontWeight: FontWeight.w800))),
              Text('Based on inverter', style: TextStyle(color: C.mute, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            _field(backup, 'Backup hours', hint: 'Enter backup hours based on inverter'),
          ],
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (u > 0)
            Row(children: [
              Icon(Icons.check_circle_outline, color: C.green, size: 19),
              const SizedBox(width: 6),
              Expanded(child: Text('Analyzed Usage: ${u.round()} kWh · ₹${groupIndian(plan.bill(u))}/mo', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(10)), child: Text('Validated', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11.5))),
            ])
          else
            Text('Enter units, a bill or a USC history above.', style: TextStyle(color: C.mute)),
          _gap(),
          Row(children: [
            CircleAvatar(radius: 11, backgroundColor: C.orange, child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            const Text('Installation Category', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _chip('Residential', category == 'residential', () => setState(() => category = 'residential'), sub: 'Open Capex'),
            _chip('Commercial', category == 'commercial', () => setState(() => category = 'commercial'), sub: 'Lower Cost'),
            _chip('Agricultural', category == 'agricultural', () => setState(() => category = 'agricultural'), sub: 'Captive'),
          ]),
          _gap(),
          Row(children: [
            CircleAvatar(radius: 11, backgroundColor: C.orange, child: const Text('2', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            const Expanded(child: Text('Select The Module', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text('DCR', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 13)),
            Switch(
              value: !dcr,
              onChanged: (v) => setState(() {
                dcr = !v;
                panelIdx = 1;
              }),
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStatePropertyAll(C.amber),
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            Text('Non-DCR', style: TextStyle(color: C.text, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          Text(subsidyNote(_profile, dcr, sys), style: TextStyle(color: C.mute, fontSize: 12, height: 1.35)),
        ]),
      ),
      _gap(),
      _bigButton('Calculate the Solar System', _calc, icon: Icons.arrow_forward),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => custOpen = !custOpen),
            child: Row(children: [
              Icon(Icons.person_outline, color: C.blue, size: 21),
              const SizedBox(width: 8),
              const Expanded(child: Text('Customer details (for Save & PDF)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Icon(custOpen ? Icons.expand_less : Icons.expand_more, color: C.mute),
            ]),
          ),
          if (custOpen) ...[
            const SizedBox(height: 10),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer name', isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address / location', isDense: true)),
            if (mode != 'usc') ...[
              const SizedBox(height: 10),
              TextField(controller: usc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'USC number (optional)', isDense: true)),
            ],
          ],
        ]),
      ),
    ];
  }

  List<Widget> _uscBlock() {
    final h = _hist;
    final months = last13Months(DateTime.now());
    final maxV = h == null || h.entered.isEmpty ? 1.0 : h.entered.reduce((a, b) => a > b ? a : b);
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(controller: usc, keyboardType: TextInputType.number, onChanged: _uscChanged, onSubmitted: (_) => _uscSearch(), decoration: const InputDecoration(labelText: 'Unique Service Number (USC No.)', isDense: true))),
        const SizedBox(width: 8),
        FilledButton(onPressed: _uscSearch, style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: C.orange), child: const Text('Check')),
      ]),
      if (uscMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(uscMsg, style: TextStyle(color: uscColor, fontSize: 12.5))),
      const SizedBox(height: 10),
      Text('Open the official bill site for ${s.st.name('en')}:', style: TextStyle(color: C.mute, fontSize: 12.5)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in s.st.discoms) OutlinedButton.icon(onPressed: () => _open(d.url), icon: const Icon(Icons.open_in_new, size: 16), label: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _editHistory,
        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
        label: Text(h == null || h.entered.isEmpty ? 'Enter 13-month units' : 'Edit 13-month units', style: const TextStyle(fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: C.blue),
      ),
      if (h != null && h.entered.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 70,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 13; i++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: ((h.units[i] ?? 0) / maxV * 64).clamp(2, 64).toDouble(),
                  decoration: BoxDecoration(color: h.units[i] == null ? C.line : C.green, borderRadius: BorderRadius.circular(3)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [Text(months.first, style: TextStyle(color: C.mute, fontSize: 11)), const Spacer(), Text(months.last, style: TextStyle(color: C.mute, fontSize: 11))]),
        _note(Icons.fact_check_outlined, C.green, 'Average of ${h.entered.length} months you entered: ${h.average.round()} kWh/month. Entered by hand from the bills. The app does not fetch it from the DISCOM.'),
      ] else
        _note(Icons.info_outline, C.blue, 'Live USC lookups are not possible: DISCOM portals need a login or captcha. Open the official site above, read the 13 months of units, and enter them here once. They are saved for this USC.'),
    ];
  }

  // ---------- 2. results ----------
  List<Widget> _results() {
    final r = s.result!;
    final o = opts[sys] ?? _options(r.monthlyUnits)[sys]!;
    final rates = s.rates;
    final rate = dcr ? rates.dcr : rates.nonDcr;
    final extra = o.type == SysType.hybrid ? o.kwp * rates.hybridExtra : (o.type == SysType.offGrid ? o.kwp * rates.offExtra : 0.0);
    final battery = o.batteryKwh * rates.battery;
    final pv = o.gross - extra.roundToDouble() - battery.roundToDouble();
    final models = panelsFor(dcr);
    final roofSqm = _num(roof);
    final warns = <String>[];
    if (roofSqm > 0 && r.roofSqm > roofSqm) warns.add('This system needs about ${r.roofSqm.round()} sq m of roof but you entered ${roofSqm.round()} sq m. Reduce the system or check the roof.');
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Solar System Estimation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                const SizedBox(height: 3),
                Text('${o.type.label} · ${dcr ? 'DCR' : 'Non-DCR'} · ${_t(double.parse(o.kwp.toStringAsFixed(2)))} kW (${o.type == SysType.onGrid ? 'Grid-Tied' : o.type == SysType.hybrid ? 'Hybrid' : 'Standalone'})', style: TextStyle(color: C.mute, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _quote(_readCustomer(), r), style: FilledButton.styleFrom(backgroundColor: C.text, foregroundColor: C.bg, minimumSize: const Size(0, 44)), child: const Text('PDF Studio', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            TextButton(onPressed: () => setState(() => stage = 0), child: const Text('Edit\nEnquiry', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
          ]),
          for (final w in warns) _note(Icons.warning_amber_rounded, C.red, w),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.verified_user_outlined, color: C.green, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('DCR Hardware Filter & Standard', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text('DCR', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Switch(
              value: !dcr,
              onChanged: (v) {
                setState(() {
                  dcr = !v;
                  panelIdx = 1;
                });
                _recalc();
              },
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              trackColor: WidgetStatePropertyAll(C.amber),
              trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            Text('Non-DCR', style: TextStyle(color: C.text, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ]),
          const SizedBox(height: 4),
          Text(dcr ? 'DCR modules use domestic cells (ALMM list). Needed for the PM Surya Ghar subsidy.' : 'Open panels (${models.first.wp}W to ${models.last.wp}W, ${models.length} typical models). Lower cost, no subsidy.', style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.3)),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < models.length; i++)
                GestureDetector(
                  onTap: () {
                    setState(() => panelIdx = i);
                    _recalc();
                  },
                  child: Container(
                    width: 108,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: panelIdx == i ? C.blue : C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: panelIdx == i ? C.blue : C.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(models[i].label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: panelIdx == i ? Colors.white : C.text)),
                      Text('${models[i].efficiency.toStringAsFixed(1)}% eff', style: TextStyle(fontSize: 11.5, color: panelIdx == i ? Colors.white70 : C.mute)),
                      Text(models[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: panelIdx == i ? Colors.white70 : C.mute)),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Typical sizes. Confirm the datasheet and ALMM listing before quoting.', style: TextStyle(color: C.mute, fontSize: 11.5)),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.bolt, C.orange, 'Inverter Brand, Power & Engineering', '${o.invLabel} · ${o.threePhase ? '3-phase 415V' : '1-phase 230V'}'),
          const SizedBox(height: 10),
          TextField(controller: inverterBrand, decoration: const InputDecoration(labelText: 'Inverter brand', hintText: 'Type a brand (e.g. Sungrow, Havells)', isDense: true)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final b in kInverterBrands[o.type]!)
              ActionChip(label: Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)), onPressed: () => setState(() => inverterBrand.text = b), visualDensity: VisualDensity.compact),
          ]),
          _note(Icons.tune, C.blue, inverterAdvice(o)),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('System Option (Inverter & Batteries)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text('${_t(o.invKw)} kW', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final t in SysType.values)
              _chip(t.label, sys == t, () {
                setState(() => sys = t);
                _recalc();
              }, sub: const ['String inverter', 'Hybrid inv + LFP', 'PCU + full bank'][t.index]),
          ]),
          if (sys.hasBattery) ...[
            const SizedBox(height: 10),
            _field(backup, 'Battery backup (hours)', hint: 'Enter hrs (inverter)', onChanged: _recalc),
          ],
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SIZING SUMMARY', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .5)),
          const SizedBox(height: 10),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_stat('DAILY USAGE', r.monthlyUnits / 30 < 10 ? (r.monthlyUnits / 30).toStringAsFixed(2) : (r.monthlyUnits / 30).toStringAsFixed(1), c: C.orange, sub: 'Units / Day'), _stat('SYSTEM SIZE', _t(double.parse(r.kw.toStringAsFixed(2))), c: C.blue, sub: 'kWp · ${r.panels} panels')])),
          const SizedBox(height: 8),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_stat('ROOF NEEDED', '${r.roofSqm.round()} sq m', sub: '${r.roofSqft.round()} sq ft'), _stat('GENERATION / YEAR', groupIndian(r.gen1), c: C.green, sub: 'kWh')])),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${dcr ? 'DCR' : 'Non-DCR'} Project Cost Breakdown', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${_profile.label} · Turnkey estimate', style: TextStyle(color: C.mute, fontSize: 12.5)),
              ]),
            ),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(12)), child: Text('${o.type.label} (${o.type == SysType.offGrid ? 'Standalone' : 'Grid'})', style: TextStyle(color: C.sky, fontWeight: FontWeight.w800, fontSize: 11.5))),
          ]),
          const SizedBox(height: 8),
          _line('PV array & mounting (${o.kwp.toStringAsFixed(2)} kW @ ${rupee(rate)}/kW)', rupee(pv)),
          _line('${o.invLabel}${o.type == SysType.onGrid ? '' : ' (type uplift)'}', o.type == SysType.onGrid ? 'Included' : '+ ${rupee(extra)}'),
          if (o.type.hasBattery) _line('Battery ${o.batteryKwh.toStringAsFixed(1)} kWh LiFePO₄', o.batteryKwh > 0 ? '+ ${rupee(battery)}' : 'Enter backup hours'),
          Divider(color: C.line),
          _line('Gross turnkey project cost', rupee(o.gross), bold: true),
          _line('PM Surya Ghar central subsidy', o.subsidy > 0 ? '- ${rupee(o.subsidy)}' : rupee(0), c: o.subsidy > 0 ? C.green : null),
          Text(subsidyNote(_profile, dcr, o.type), style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.3)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.chipSun, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Expanded(child: Text('Net project cost', style: TextStyle(fontWeight: FontWeight.w800))),
              Text(rupee(o.net), style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 19)),
            ]),
          ),
        ]),
      ),
      _gap(),
      _bigButton('ROI Dashboard', () => setState(() => stage = 2), icon: Icons.trending_up),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => stage = 3), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: C.text), child: const Text('Customer Page', style: TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton(onPressed: _save, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: C.text), child: const Text('Save estimate', style: TextStyle(fontWeight: FontWeight.w800)))),
      ]),
    ];
  }

  // ---------- 3. ROI dashboard ----------
  List<Widget> _roi() {
    final r = s.result!;
    final pb = r.paybackYears;
    final good = pb != null;
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Investment Payback Period', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('${r.years}-year break-even & financial return model', style: TextStyle(color: C.mute, fontSize: 12.5)),
          _gap(10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: (good ? C.green : C.red).withValues(alpha: .1), borderRadius: BorderRadius.circular(16), border: Border.all(color: (good ? C.green : C.red).withValues(alpha: .4))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ESTIMATED BREAK-EVEN POINT', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  Text(good ? 'Time to recover the net system cost' : 'Not recovered within ${r.years} years', style: TextStyle(color: C.mute, fontSize: 12.5)),
                ]),
              ),
              Text(good ? '${fmt1(pb)} Years' : '${r.years}+ Years', style: TextStyle(color: good ? C.green : C.red, fontWeight: FontWeight.w800, fontSize: 22)),
            ]),
          ),
          _gap(10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _stat('PAYBACK PERIOD', good ? '${fmt1(pb)} Yrs' : '${r.years}+ Yrs', c: C.blue),
              _stat('${r.years}-YR NET GAIN', rupee(r.lifetimeProfit), c: r.lifetimeProfit >= 0 ? C.green : C.red, sub: 'after O&M'),
              _stat('LIFETIME ROI', '${r.roi.round()}%', c: r.roi >= 0 ? C.orange : C.red),
            ]),
          ),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('ROI Sensitivity Sliders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text(good ? 'Payback: ${fmt1(pb)} Yrs' : 'Payback: ${r.years}+ Yrs', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('Expected annual tariff increase', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Text('${escalation.toStringAsFixed(1)}% / yr', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800)),
          ]),
          Slider(
            value: escalation.clamp(0, 10).toDouble(),
            min: 0,
            max: 10,
            divisions: 20,
            onChanged: (v) {
              escalation = v;
              _recalc();
            },
          ),
          Row(children: [
            const Expanded(child: Text('System maintenance cost', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Text('${omPct.toStringAsFixed(2)}% (${rupee(r.cost * omPct / 100)}/yr)', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800)),
          ]),
          Slider(
            value: omPct.clamp(0, 5).toDouble(),
            min: 0,
            max: 5,
            divisions: 20,
            activeColor: C.orange,
            onChanged: (v) {
              omPct = v;
              _recalc();
            },
          ),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cumulative Savings vs System Cost', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          NetChart(r.series.map((e) => e.net).toList()),
          const SizedBox(height: 6),
          Text('Bars below zero are money still to be recovered. Includes panel degradation, the yearly tariff rise and maintenance.', style: TextStyle(color: C.mute, fontSize: 12)),
        ]),
      ),
      _gap(),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => stage = 1), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: C.text), child: const Text('Back to Results', style: TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton.icon(onPressed: () => _quote(_readCustomer(), r), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Export PDF', style: TextStyle(fontWeight: FontWeight.w800)), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: C.text, foregroundColor: C.bg))),
      ]),
      const SizedBox(height: 10),
      _bigButton('Full Savings Page', () => setState(() => stage = 3)),
    ];
  }

  // ---------- 4. customer page ----------
  List<Widget> _customerPage() {
    final r = s.result!;
    final grossYear = r.year1Saving + r.cost * omPct / 100;
    final use = yearly ? r.monthlyUnits * 12 : r.monthlyUnits;
    Widget toggle(String t, bool on, VoidCallback f) => GestureDetector(
          onTap: f,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9), decoration: BoxDecoration(color: on ? C.green : C.card2, borderRadius: BorderRadius.circular(14)), child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : C.text))),
        );
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Your Solar Estimation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
            FilledButton.icon(onPressed: () => _quote(_readCustomer(), r), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w800)), style: FilledButton.styleFrom(backgroundColor: C.text, foregroundColor: C.bg)),
          ]),
          Text('Based on your inputs, here is your potential', style: TextStyle(color: C.mute, fontSize: 12.5)),
          _gap(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total Consumption Units / ${yearly ? 'Year' : 'Month'}', style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(groupIndian(use), style: TextStyle(color: C.green, fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('Units', style: TextStyle(color: C.green, fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
              Text('${groupIndian(r.monthlyUnits * 12)} units/year total', style: TextStyle(color: C.mute, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [toggle('Monthly', !yearly, () => setState(() => yearly = false)), const SizedBox(width: 8), toggle('Yearly', yearly, () => setState(() => yearly = true))]),
            ]),
          ),
          _gap(10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _stat('MONTHLY SAVINGS', '₹ ${groupIndian(grossYear / 12)}', c: C.orange, sub: 'Save more every month'),
              _stat('ANNUAL SAVINGS', '₹ ${groupIndian(grossYear)}', c: C.green, sub: 'More savings, more freedom'),
            ]),
          ),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.eco_outlined, C.green, 'Clean Energy. Bigger Savings.', 'You save money while contributing to a greener tomorrow.'),
          _gap(10),
          _line('System size', '${r.kw.toStringAsFixed(2)} kWp (${r.panels} panels)'),
          _line('Net cost', rupee(r.netCost)),
          _line('Payback', r.paybackYears == null ? '${r.years}+ years' : '${fmt1(r.paybackYears!)} years'),
          _line('CO₂ avoided per year', '${fmt1(r.co2Tonnes)} tonnes'),
        ]),
      ),
      _gap(),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => stage = 1), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: C.text), child: const Text('Back to Results', style: TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: C.orange), child: const Text('Save estimate', style: TextStyle(fontWeight: FontWeight.w800)))),
      ]),
    ];
  }

  // ---------- Existing plant ----------
  List<Widget> _existing() => [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title(Icons.health_and_safety_outlined, C.blue, 'Existing Plant Audit & Health', 'Performance ratio, expected vs actual generation and maintenance advice'),
            _note(Icons.schedule, C.amber, 'This tab is planned for the next build. Use New Install and Generation for now.'),
          ]),
        ),
      ];

  // ---------- Generation ----------
  List<Widget> _generation() {
    final r = s.result;
    if (r == null) {
      return [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title(Icons.flash_on, C.green, 'Power Generation & Yield', 'Run a New Install calculation first'),
            _gap(10),
            FilledButton(onPressed: () => setState(() => tab = 0), style: FilledButton.styleFrom(backgroundColor: C.orange), child: const Text('Go to New Install', style: TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ),
      ];
    }
    final tariff = s.input.tariff;
    final flow = energyFlow(monthlyGen: r.monthlyGen, monthlyUse: r.monthlyUnits, tariff: tariff, exportRate: s.st.exportRate);
    final cover = r.monthlyUnits > 0 ? (flow.selfUse / r.monthlyUnits * 100).round() : 0;
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F9B8E), Color(0xFF0B6E8A)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.flash_on, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('ESTIMATED POWER GENERATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .4))),
            Text('${_t(double.parse(r.kw.toStringAsFixed(2)))} kW System', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(groupIndian(r.monthlyGen), style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            const Text('kWh / Month', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          const Divider(color: Colors.white24),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Daily Generation', style: TextStyle(color: Colors.white70, fontSize: 11.5)), Text('${(r.gen1 / 365).toStringAsFixed(1)} kWh/day', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Annual Energy Output', style: TextStyle(color: Colors.white70, fontSize: 11.5)), Text('${groupIndian(r.gen1)} kWh/yr', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
          ]),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('ENERGY FLOW & GRID BALANCE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: .3))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(10)), child: Text('$cover% Solar Powered', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11.5))),
          ]),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _stat('SELF-CONSUMED', '${flow.selfUse.round()} kWh', c: C.orange, sub: 'Avoided utility cost'),
              _stat('GRID EXPORT', '${flow.export.round()} kWh', c: C.blue, sub: s.st.exportRate == null ? 'Net metering credit' : 'Sold at feed-in rate'),
              _stat('GRID IMPORT', '${flow.import.round()} kWh', sub: 'Night / peak balance'),
            ]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('COMBINED MONTHLY VALUE', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w800)), Text(rupee(flow.monthlyValue), style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 22))])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Annual benefit', style: TextStyle(color: C.mute, fontSize: 11.5)), Text('${rupee(flow.annualValue)} / yr', style: const TextStyle(fontWeight: FontWeight.w800))]),
            ]),
          ),
          _note(Icons.info_outline, C.blue, 'Self-use is valued at ₹${tariff.toStringAsFixed(2)}/kWh. ${s.st.exportRate == null ? 'Exports under net metering are banked as units against your bill, so they are not counted as cash here.' : 'Exports are valued at the state feed-in rate of ₹${s.st.exportRate!.toStringAsFixed(2)}/kWh.'}'),
        ]),
      ),
    ];
  }


  List<Widget> _saved() {
    final s = widget.state;
    final q = search.text.trim();
    final qn = normalizeUsc(q);
    final ql = q.toLowerCase();
    final rows = q.isEmpty
        ? s.records
        : s.records.where((r) {
            final c = r.customer;
            return normalizeUsc(c.usc).contains(qn) || [c.name, c.phone, c.address].any((x) => x.toLowerCase().contains(ql));
          }).toList();
    return [
      TextField(
        controller: search,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by USC number, name, phone or address'),
      ),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        Panel(child: Center(child: Text(s.records.isEmpty ? 'No saved estimates yet.' : 'No match.', style: TextStyle(color: C.mute)))),
      for (final rec in rows) _savedTile(rec),
      if (s.records.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _copyCsv(s),
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy all as CSV'),
          ),
        ),
    ];
  }

  Widget _savedTile(SavedRecord rec) {
    final c = rec.customer;
    final r = rec.result;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        radius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.name.isEmpty ? 'Unnamed customer' : c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('USC ${c.usc.isEmpty ? '-' : c.usc} · ${c.phone.isEmpty ? 'no phone' : c.phone}${c.address.isEmpty ? '' : '\n${c.address}'}', style: TextStyle(color: C.mute, fontSize: 12.5)),
          const SizedBox(height: 8),
          Text('${fmt1(r.kw)} kW · ${r.panels} panels · Net ${inr(r.netCost)} · Payback ${r.paybackYears == null ? '-' : '${fmt1(r.paybackYears!)} yrs'}', style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _load(rec);
                  final s = widget.state;
                  s.input = rec.input.copy();
                  s.customer = rec.customer;
                  s.result = calculate(rec.input);
                  setState(() => stage = 1);
                },
                child: const Text('Open'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _quote(c, r), child: const Text('Quote'))),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Delete saved estimate?'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))],
                    ),
                  );
                  if (ok == true) {
                    widget.state.records.removeWhere((x) => x.id == rec.id);
                    widget.state.saveRecords();
                  }
                },
                child: const Text('Delete'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _copyCsv(AppState s) async {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final lines = <String>[['USC', 'Name', 'Phone', 'Address', 'kW', 'Panels', 'Net cost (Rs)', 'Payback (yrs)'].map(q).join(',')];
    for (final rec in s.records) {
      final r = rec.result;
      lines.add([
        rec.customer.usc,
        rec.customer.name,
        rec.customer.phone,
        rec.customer.address,
        r.kw.toStringAsFixed(2),
        '${r.panels}',
        '${r.netCost.round()}',
        r.paybackYears == null ? '' : r.paybackYears!.toStringAsFixed(1),
      ].map(q).join(','));
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) toast(context, 'CSV copied. Paste it into Excel or a message.');
  }
}

/// Sheet to enter the 13 monthly unit readings of one USC.
class _UscSheet extends StatefulWidget {
  final AppState state;
  final String usc;
  const _UscSheet({required this.state, required this.usc});
  @override
  State<_UscSheet> createState() => _UscSheetState();
}

class _UscSheetState extends State<_UscSheet> {
  late final List<TextEditingController> c;
  late final List<String> months;

  @override
  void initState() {
    super.initState();
    months = last13Months(DateTime.now());
    final h = widget.state.uscHistory[widget.usc];
    c = [for (var i = 0; i < 13; i++) TextEditingController(text: h?.units[i] == null ? '' : h!.units[i]!.round().toString())];
  }

  @override
  void dispose() {
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  void _save() {
    final h = UscHistory(units: [for (final x in c) double.tryParse(x.text.trim())], at: DateTime.now().millisecondsSinceEpoch);
    if (h.entered.isEmpty) {
      widget.state.uscHistory.remove(widget.usc);
    } else {
      widget.state.uscHistory[widget.usc] = h;
    }
    widget.state.saveUsc();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('13-month units · USC ${widget.usc}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            Text('Enter units (kWh) from the customer bills or the DISCOM site. Leave a month empty if it is not known.', style: TextStyle(color: C.mute, fontSize: 12.5)),
            const SizedBox(height: 12),
            Wrap(runSpacing: 10, children: [
              for (var i = 0; i < 13; i++)
                FractionallySizedBox(
                  widthFactor: .5,
                  child: Padding(
                    padding: EdgeInsets.only(right: i.isEven ? 8 : 0, left: i.isEven ? 0 : 0),
                    child: TextField(controller: c[i], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: months[i], suffixText: 'kWh', isDense: true)),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, style: FilledButton.styleFrom(backgroundColor: C.orange, padding: const EdgeInsets.symmetric(vertical: 15)), child: const Text('Save units', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
          ]),
        ),
      );
}
