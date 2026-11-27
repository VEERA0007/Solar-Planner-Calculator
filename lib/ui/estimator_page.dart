import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/appliance_data.dart';
import '../core/backend_service.dart';
import '../core/calc.dart';
import '../core/estimator_data.dart';
import '../core/service_data.dart';
import '../core/store.dart';
import '../core/tariff.dart';
import 'pdf_quote.dart';
import 'roof_map.dart';
import 'theme.dart';

/// Solar Estimator: New Install (with 4-state USC bill fetch, inline tariff/DISCOM
/// selector, custom rate override, roof map, BOM, ROI & Customer page),
/// Existing Plant Audit, and standalone Power Generation & Yield Calculator.
class EstimatorPage extends StatefulWidget {
  final AppState state;
  const EstimatorPage({super.key, required this.state});
  @override
  State<EstimatorPage> createState() => _EstimatorPageState();
}

class _EstimatorPageState extends State<EstimatorPage> {
  int tab = 0; // 0 New Install, 1 Existing Plant, 2 Generation
  int stage = 0; // 0 form, 1 results, 2 ROI, 3 customer page, 4 saved
  String mode = 'units'; // units | bill
  String category = 'residential';
  bool dcr = true;
  SysType sys = SysType.onGrid;
  int panelIdx = 1;
  bool custOpen = false;
  bool uscOpen = false;
  bool bomOpen = false;
  int bomTab = 0;
  double escalation = 3, omPct = 1;
  bool yearly = false;
  Map<SysType, SysOption> opts = {};
  bool slabOpen = false;

  // Live USC & Tariff sync state
  bool fetchingUsc = false;
  bool syncingTariff = false;
  String uscMsg = '';
  bool uscErr = false;
  List<UscMonthEntry> uscMonths = [];

  final units = TextEditingController(text: '400');
  final bill = TextEditingController();
  final uscCtrl = TextEditingController();
  final tariffOverride = TextEditingController();
  final roof = TextEditingController();
  final backup = TextEditingController();
  final inverterBrand = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final search = TextEditingController();
  final exWp = TextEditingController(text: '550'),
      exQty = TextEditingController(),
      exInv = TextEditingController(),
      exGen = TextEditingController();
  final customCost = TextEditingController();
  // Standalone Generation tab controllers
  final genKw = TextEditingController(text: '3.0');
  final genUse = TextEditingController(text: '400');
  final genTariff = TextEditingController();

  String exArch = 'String inverter (Central MPPT)';
  double? invOverride; // chosen inverter size in kW, null = the suggested size
  String payMsg = '';
  RoofResult? roofTrace;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final p = s.profile;
    name.text = p.name;
    phone.text = p.mobile;
    address.text = p.address;
    uscCtrl.text = p.serviceNo;
    _takePush();
  }

  @override
  void didUpdateWidget(covariant EstimatorPage old) {
    super.didUpdateWidget(old);
    if (s.estimatePush != null) setState(_takePush);
  }

  @override
  void dispose() {
    for (final c in [
      units, bill, uscCtrl, tariffOverride, roof, backup, inverterBrand,
      name, phone, address, search, exWp, exQty, exInv, exGen, customCost,
      genKw, genUse, genTariff,
    ]) {
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
    category = const ['residential', 'commercial', 'industrial', 'agricultural'].contains(d.category) ? d.category : 'residential';
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

  double get _monthlyUnits {
    switch (mode) {
      case 'bill':
        final ov = _num(tariffOverride);
        if (ov > 0) return _num(bill) / ov;
        return s.tariffCat.unitsForBill(_num(bill));
      default:
        return _num(units);
    }
  }

  double _activeRate(double u) {
    final ov = _num(tariffOverride);
    if (ov > 0) return ov;
    return u > 0 ? s.tariffCat.marginal(u) : s.unitPrice;
  }

  PanelModel get _panel {
    final l = panelsFor(dcr);
    return l[panelIdx.clamp(0, l.length - 1)];
  }

  LoadProfile get _profile => switch (category) {
        'commercial' => LoadProfile.commercial,
        'industrial' => LoadProfile.industrial,
        'agricultural' => LoadProfile.agricultural,
        _ => LoadProfile.residential,
      };

  double invKw(SysOption o) => invOverride ?? o.invKw;

  Map<SysType, SysOption> _options(double u) {
    final daily = u / 30;
    final rate = _activeRate(u);
    return {
      for (final t in SysType.values)
        t: buildOption(
          type: t,
          dailyKwh: daily,
          connectedKw: daily / 5,
          yieldPerKwp: s.locationYield,
          tariff: rate,
          dcr: dcr,
          profile: _profile,
          backupHours: _num(backup),
          panelWp: _panel.wp.toDouble(),
          rates: s.rates,
        )
    };
  }

  Customer _readCustomer() => Customer(
        usc: normalizeUsc(uscCtrl.text),
        name: name.text.trim(),
        phone: phone.text.trim(),
        address: address.text.trim(),
      );

  /// Builds the three options and the savings result. [go] opens the results page.
  void _calc({bool go = true}) {
    final u = _monthlyUnits;
    if (!(u > 0)) {
      if (go) toast(context, 'Enter monthly units or bill');
      return;
    }
    final plan = s.tariffCat;
    final ov = _num(tariffOverride);
    opts = _options(u);
    final o = opts[sys]!;
    final y = s.locationYield;
    final off = (o.kwp * y * 30) < u ? o.kwp * y * 30 : u;
    final eff = ov > 0 ? ov : (off > 0 ? (plan.bill(u) - plan.bill(u - off)) / off : plan.marginal(u));
    final inp = EstimateInput(
      mode: 'units',
      monthlyUnits: u,
      monthlyBill: ov > 0 ? u * ov : plan.bill(u),
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
    // Sync Generation tab inputs with latest estimate
    genKw.text = s.result!.kw.toStringAsFixed(2);
    genUse.text = u.round().toString();
    genTariff.text = inp.tariff.toStringAsFixed(2);
    if (go) {
      setState(() => stage = 1);
    } else {
      setState(() {});
    }
  }

  void _recalc() {
    if (s.result != null) _calc(go: false);
  }

  Future<void> _fetchUsc() async {
    final clean = normalizeUsc(uscCtrl.text);
    if (clean.isEmpty) {
      setState(() {
        uscErr = true;
        uscMsg = 'Enter your USC / Consumer Service Number.';
      });
      return;
    }
    setState(() {
      fetchingUsc = true;
      uscErr = false;
      uscMsg = 'Fetching 12-month bill history from ${s.discom.name}...';
    });

    final res = await BackendService.fetchUscBill(
      rawBaseUrl: s.prefs.backendUrl,
      usc: clean,
      stateId: s.prefs.stateId,
      discomId: s.prefs.discomId,
      category: s.prefs.category,
    );

    if (!mounted) return;
    if (res.ok) {
      setState(() {
        fetchingUsc = false;
        uscErr = false;
        uscMonths = res.history;
        if (res.avgMonthlyUnits > 0) {
          mode = 'units';
          units.text = res.avgMonthlyUnits.round().toString();
        } else if (res.avgMonthlyBill > 0) {
          mode = 'bill';
          bill.text = res.avgMonthlyBill.round().toString();
        }
        if (res.consumerName.isNotEmpty) name.text = res.consumerName;
        if (res.address.isNotEmpty) address.text = res.address;
        uscMsg = 'Fetched ${res.history.isNotEmpty ? '${res.history.length} months' : 'bill'} · '
            'Avg ${res.avgMonthlyUnits.round()} kWh/mo'
            '${res.consumerName.isNotEmpty ? ' · ${res.consumerName}' : ''}';
      });
      s.addUscHistory(UscHistoryItem(
        usc: clean,
        stateId: s.prefs.stateId,
        discomName: s.discom.name,
        consumerName: res.consumerName,
        avgMonthlyUnits: res.avgMonthlyUnits,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      setState(() {
        fetchingUsc = false;
        uscErr = true;
        uscMsg = res.error ?? 'Could not fetch bill.';
      });
    }
  }

  Future<void> _syncLiveTariff() async {
    setState(() => syncingTariff = true);
    final res = await BackendService.fetchRealtimeTariff(
      rawBaseUrl: s.prefs.backendUrl,
      stateId: s.prefs.stateId,
      discomId: s.prefs.discomId,
      category: s.prefs.category,
      monthlyUnits: _monthlyUnits > 0 ? _monthlyUnits : 400,
    );
    if (!mounted) return;
    setState(() => syncingTariff = false);
    if (res.ok && res.rate != null) {
      setState(() => tariffOverride.text = res.rate!.toStringAsFixed(2));
      toast(context, 'Live tariff synced: ₹${res.rate!.toStringAsFixed(2)}/kWh');
    } else {
      toast(context, 'Using official ${s.st.name('en')} slab table (${s.st.order})');
    }
  }

  void _save() {
    final r = s.result;
    if (r == null) return;
    final c = _readCustomer();
    if (c.name.isEmpty) {
      toast(context, 'Add the customer name first (Customer details on the Estimate page)');
      setState(() {
        stage = 0;
        custOpen = true;
      });
      return;
    }
    final idx = s.records.indexWhere((x) => x.customer.name == c.name && x.customer.phone == c.phone);
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
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _load(SavedRecord r) {
    uscCtrl.text = r.customer.usc;
    name.text = r.customer.name;
    phone.text = r.customer.phone;
    address.text = r.customer.address;
    _fill(r.input);
  }

  Future<void> _openRoofMap() async {
    final r = await Navigator.of(context).push<RoofResult>(MaterialPageRoute(builder: (_) => RoofMapPage(state: s, panel: _panel)));
    if (r == null || !mounted) return;
    setState(() {
      roofTrace = r;
      roof.text = r.areaM2.round().toString();
    });
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
    final book = s.book;
    final activeRate = _activeRate(u);

    return [
      // Collapsible 4-State Live USC / DISCOM Bill Fetch Panel
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => uscOpen = !uscOpen),
            child: Row(children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: C.chipBlue, shape: BoxShape.circle), child: Icon(Icons.electric_meter_outlined, color: C.sky, size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('USC / DISCOM Live Bill Fetch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${s.st.name('en')} · ${s.discom.name} (Auto-fill 12-mo units)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 12)),
                ]),
              ),
              Icon(uscOpen ? Icons.expand_less : Icons.expand_more, color: C.mute),
            ]),
          ),
          if (uscOpen) ...[
            const SizedBox(height: 12),
            if (book != null) ...[
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('est_st_${s.prefs.stateId}'),
                    initialValue: s.prefs.stateId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State', isDense: true),
                    items: [for (final x in book.states) DropdownMenuItem(value: x.id, child: Text(x.name('en'), overflow: TextOverflow.ellipsis))],
                    onChanged: (v) {
                      if (v == null) return;
                      s.chooseState(v);
                      s.savePrefs();
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('est_dc_${s.prefs.stateId}_${s.prefs.discomId}'),
                    initialValue: s.discom.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'DISCOM', isDense: true),
                    items: [for (final d in s.st.discoms) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) {
                      if (v == null) return;
                      s.prefs.discomId = v;
                      s.savePrefs();
                      setState(() {});
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Expanded(
                child: TextField(
                  controller: uscCtrl,
                  decoration: const InputDecoration(labelText: 'USC / Service Number', hintText: 'e.g. 102938475', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: fetchingUsc ? null : _fetchUsc,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48), backgroundColor: C.blue),
                child: Text(fetchingUsc ? '...' : 'Fetch', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: () => _open(s.discom.url),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: Text('Open ${s.discom.name} Portal', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              for (final h in s.uscHistory.take(3))
                ActionChip(
                  label: Text('${h.usc} (${h.avgMonthlyUnits.round()} U)', style: const TextStyle(fontSize: 12)),
                  onPressed: () => setState(() {
                    uscCtrl.text = h.usc;
                    if (h.avgMonthlyUnits > 0) {
                      mode = 'units';
                      units.text = h.avgMonthlyUnits.round().toString();
                    }
                    if (h.consumerName.isNotEmpty) name.text = h.consumerName;
                  }),
                ),
            ]),
            if (uscMsg.isNotEmpty) _note(uscErr ? Icons.info_outline : Icons.check_circle_outline, uscErr ? C.amber : C.green, uscMsg),
            if (uscMonths.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 54,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final m in uscMonths.take(12))
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(m.month, style: TextStyle(color: C.mute, fontSize: 10.5, fontWeight: FontWeight.w700)),
                          Text('${m.units.round()} U', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.receipt_long_outlined, C.amber, 'Monthly Bills & Units Enquiry', 'Enter your monthly units or a bill amount'),
          _gap(),
          Text('Monthly Consumption', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            _chip('Units (kWh)', mode == 'units', () => setState(() => mode = 'units')),
            _chip('Bill (₹)', mode == 'bill', () => setState(() => mode = 'bill')),
          ]),
          const SizedBox(height: 12),
          if (mode == 'units') _field(units, 'Units / Month (kWh)'),
          if (mode == 'bill') _field(bill, 'Bill / Month (energy charges)', prefix: '₹ '),
          if (u > 0) ...[
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.st.name('en').split(' ').first.toUpperCase()} · ${plan.slabLabel(u)}', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${u.round()} kWh → ₹${groupIndian(_num(tariffOverride) > 0 ? u * _num(tariffOverride) : plan.bill(u))}/mo (₹${(_num(tariffOverride) > 0 ? _num(tariffOverride) : plan.average(u)).toStringAsFixed(2)}/kWh avg)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (quick != null) ...[
                  const SizedBox(height: 4),
                  Text('Suggested: ${quick.kwp.toStringAsFixed(2)} kWp (${quick.panels} × ${_panel.wp}W)', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 14)),
                ],
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => setState(() => slabOpen = !slabOpen),
                  child: Row(children: [
                    Text(slabOpen ? 'Hide bill working' : 'How was this bill worked out?', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Icon(slabOpen ? Icons.expand_less : Icons.expand_more, color: C.blue, size: 18),
                  ]),
                ),
                if (slabOpen) ..._slabLines(plan, u),
              ]),
            ),
          ],
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
          Row(children: [
            Expanded(
              child: _field(
                tariffOverride,
                'Custom ₹/kWh (blank = auto ${activeRate.toStringAsFixed(2)})',
                hint: activeRate.toStringAsFixed(2),
                prefix: '₹ ',
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: syncingTariff ? null : _syncLiveTariff,
              icon: const Icon(Icons.sync, size: 17),
              label: Text(syncingTariff ? '...' : 'Sync', style: const TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: C.green, side: BorderSide(color: C.green.withValues(alpha: .6))),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${s.st.order}. Effective ${s.st.effective}. Auto slab: ₹${(u > 0 ? plan.marginal(u) : s.unitPrice).toStringAsFixed(2)}/kWh.', style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.3)),
          _gap(),
          Text('Roof Area in Square Meters (Optional)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field(roof, 'Roof area', suffix: 'sq m')),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _openRoofMap,
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: const Text('Map', style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: C.orange, side: BorderSide(color: C.orange.withValues(alpha: .6))),
            ),
          ]),
          if (roofTrace != null) _note(Icons.roofing, C.green, 'Traced roof: ${roofTrace!.areaM2.toStringAsFixed(1)} m². It fits ${roofTrace!.panels} panels (${roofTrace!.kwp.toStringAsFixed(2)} kWp).'),
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
              Expanded(child: Text('Analyzed Usage: ${u.round()} kWh · ₹${groupIndian(_num(tariffOverride) > 0 ? u * _num(tariffOverride) : plan.bill(u))}/mo', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(10)), child: Text('Validated', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11.5))),
            ])
          else
            Text('Enter units or a bill above.', style: TextStyle(color: C.mute)),
          _gap(),
          Row(children: [
            CircleAvatar(radius: 11, backgroundColor: C.orange, child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            const Text('Installation Category', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _chip('Residential', category == 'residential', () {
              setState(() => category = 'residential');
              s.prefs.category = 'domestic';
              s.savePrefs();
            }, sub: 'Open Capex'),
            _chip('Commercial', category == 'commercial', () {
              setState(() => category = 'commercial');
              s.prefs.category = 'commercial';
              s.savePrefs();
            }, sub: 'Lower Cost'),
            _chip('Industrial', category == 'industrial', () {
              setState(() => category = 'industrial');
              s.prefs.category = 'industrial';
              s.savePrefs();
            }, sub: 'Plant'),
            _chip('Agricultural', category == 'agricultural', () => setState(() => category = 'agricultural'), sub: 'Pumps'),
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
          ],
        ]),
      ),
    ];
  }

  /// One line per tariff slab so the customer can follow the bill.
  List<Widget> _slabLines(CategoryTariff plan, double u) {
    final sch = plan.scheduleFor(u);
    final rows = <Widget>[];
    var left = u, prev = 0.0, total = 0.0;
    for (final sl in sch.slabs) {
      final cap = sl.upTo == null ? double.infinity : sl.upTo! - prev;
      final take = left < cap ? left : cap;
      if (take > 0) {
        final amt = take * sl.rate;
        total += amt;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text('${prev.round()}-${sl.upTo == null ? u.round() : sl.upTo!.round()} units: ${_t(double.parse(take.toStringAsFixed(1)))} × ₹${sl.rate.toStringAsFixed(2)}', style: TextStyle(color: C.mute, fontSize: 12.5))),
            Text('₹${groupIndian(amt)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ));
      }
      left -= take;
      prev = sl.upTo ?? prev;
      if (left <= 0) break;
    }
    return [
      ...rows,
      Divider(height: 14, color: C.line),
      Row(children: [
        const Expanded(child: Text('Energy charges', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
        Text('₹${groupIndian(total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Fixed charges, electricity duty and fuel surcharge are not included, so your printed bill will be higher. Rates: ${s.st.order}.', style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.3)),
      ),
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
    final bom = buildBom(o, dcr: dcr, profile: _profile, rates: s.rates);
    final bomFiltered = bom.items.where((x) => x.tab == bomTab).toList();
    final roofSqm = _num(roof);
    final warns = <String>[];
    if (roofSqm > 0 && r.roofSqm > roofSqm) warns.add('This system needs about ${r.roofSqm.round()} sq m of roof but you entered ${roofSqm.round()} sq m. Reduce the system or check the roof.');
    if (roofTrace != null && o.panels > roofTrace!.panels) warns.add('The traced roof fits ${roofTrace!.panels} panels but this system needs ${o.panels}. Reduce the system, use higher-wattage panels or add another roof.');
    final needKw = (r.monthlyUnits / 30) / (s.locationYield > 0.5 ? s.locationYield : 3.5);
    if (o.kwp > needKw * 1.25 + 0.55) {
      warns.add('This system (${o.kwp.toStringAsFixed(2)} kWp) is much bigger than the usage needs (about ${needKw.toStringAsFixed(2)} kWp for ${r.monthlyUnits.round()} units a month). A smaller system will pay back faster.');
    }
    if (r.paybackYears == null || r.paybackYears! > 12) {
      warns.add(r.paybackYears == null ? 'This system does not pay back within ${r.years} years at this usage. Check the units entered or try On-Grid.' : 'Payback is ${r.paybackYears!.toStringAsFixed(1)} years. Low usage or battery cost stretches it. On-Grid is usually quickest.');
    }

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
          const SizedBox(height: 12),
          Text('INVERTER POWER (KW)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
            child: Row(children: [
              Expanded(child: Text(_t(invKw(o)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              Text(invOverride == null ? 'Auto (${_t(o.invKw)} kW)' : 'Chosen', style: TextStyle(color: C.mute, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Text('Standard sizes:', style: TextStyle(color: C.mute, fontSize: 12.5)),
            for (final k in standardInverterSizes(o.kwp))
              GestureDetector(
                onTap: () => setState(() => invOverride = k == o.invKw ? null : k),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: (invOverride ?? o.invKw) == k ? C.orange : C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: (invOverride ?? o.invKw) == k ? C.orange : C.line)),
                  child: Text('${_t(k)} kW${k == o.invKw ? ' ★' : ''}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: (invOverride ?? o.invKw) == k ? Colors.white : C.text)),
                ),
              ),
          ]),
          _note(Icons.tune, C.green, '${dcAcAdvice(o.kwp, invKw(o))}\nSuggested range: ${_t(double.parse((o.kwp * .8).toStringAsFixed(1)))} to ${_t(double.parse((o.kwp * 1.1).toStringAsFixed(1)))} kW AC for ${o.kwp.toStringAsFixed(2)} kWp of panels.'),
          const SizedBox(height: 12),
          TextField(controller: inverterBrand, decoration: const InputDecoration(labelText: 'Inverter brand', hintText: 'Type a brand (e.g. Sungrow, Havells, Deye)', isDense: true)),
          const SizedBox(height: 10),
          Text('SUGGESTED ${o.type.label.toUpperCase()} INVERTERS (TAP TO SELECT)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in inverterBrandInfo(o.type))
              GestureDetector(
                onTap: () => setState(() => inverterBrand.text = b.name),
                child: Container(
                  width: (MediaQuery.of(context).size.width - 28 - 36 - 8) / 2,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: inverterBrand.text == b.name ? C.chipSun : C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: inverterBrand.text == b.name ? C.orange : C.line)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))), Text('${b.eff}%', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11.5))]),
                    const SizedBox(height: 2),
                    Text(b.series, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 11)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text('Peak efficiencies are typical datasheet figures. Confirm model and availability with the supplier.', style: TextStyle(color: C.mute, fontSize: 11)),
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
      // Bill of Materials (BOM) & Interlink Breakdown inside Estimator Results
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => bomOpen = !bomOpen),
            child: Row(children: [
              Icon(Icons.inventory_2_outlined, color: C.sky, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Required Parts & BOM (${bom.items.length} items)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${o.type.label} · ${dcr ? 'DCR ALMM' : 'Non-DCR'} · ${o.threePhase ? '3-Phase' : '1-Phase'}', style: TextStyle(color: C.mute, fontSize: 12)),
                ]),
              ),
              if (bom.removed.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(10)),
                  child: Text('${bom.removed.length} Filtered', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 11)),
                ),
              Icon(bomOpen ? Icons.expand_less : Icons.expand_more, color: C.mute),
            ]),
          ),
          if (bomOpen) ...[
            const SizedBox(height: 10),
            Row(children: [
              _chip('PV & Inv', bomTab == 0, () => setState(() => bomTab = 0)),
              _chip('BOS & Str', bomTab == 1, () => setState(() => bomTab = 1)),
              _chip('Metering', bomTab == 2, () => setState(() => bomTab = 2)),
            ]),
            const SizedBox(height: 10),
            for (final item in bomFiltered)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                    Text(rupee(item.price), style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                  const SizedBox(height: 2),
                  Text('${item.qty} · ${item.spec}', style: TextStyle(color: C.mute, fontSize: 11.5)),
                ]),
              ),
          ],
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
          const Text('Investment Payback Period', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
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
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Want to know about your Payback period?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          const SizedBox(height: 4),
          Text('Add your installation cost and see how quickly you will start saving.', style: TextStyle(color: C.mute, fontSize: 12.5)),
          const SizedBox(height: 10),
          _field(customCost, 'Installation cost', prefix: '₹ '),
          const SizedBox(height: 10),
          _bigButton('Calculate', () {
            final c = _num(customCost);
            if (!(c > 0)) return toast(context, 'Enter the installation cost');
            final i = s.input.copy()
              ..costPerKw = c / r.kw
              ..subsidy = false;
            final x = calculate(i);
            setState(() => payMsg = x.paybackYears == null ? 'Not paid back within ${x.years} years at this cost.' : 'Payback in ${fmt1(x.paybackYears!)} years. 25-year net gain ${rupee(x.lifetimeProfit)}.');
          }),
          if (payMsg.isNotEmpty) _note(Icons.hourglass_bottom, C.green, payMsg),
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
  List<Widget> _existing() {
    final wp = _num(exWp), qty = _num(exQty), inv = _num(exInv), act = _num(exGen);
    final kwp = wp * qty / 1000;
    final y = s.locationYield;
    final expected = kwp * y * 30;
    final pr = expected > 0 && act > 0 ? act / expected * 100 : 0.0;
    final ratio = inv > 0 ? kwp / inv : 0.0;
    final snap = s.inverterSnap;
    DateTime? lastWash;
    for (final e in s.services) {
      if (e.type == ServiceType.cleaning && (lastWash == null || e.date.isAfter(lastWash))) lastWash = e.date;
    }
    final recs = <(String, Color)>[];
    if (kwp <= 0) {
      recs.add(('Enter the panel wattage and quantity to start the audit.', C.amber));
    } else if (act <= 0) {
      recs.add(('Enter last month\'s generation (kWh) from the inverter or meter to get the performance ratio.', C.amber));
    } else if (pr > 105) {
      recs.add(('PR is ${pr.round()}%, which is above 100%. Re-check the capacity and the generation figure.', C.amber));
    } else if (pr >= 75) {
      recs.add(('System is operating within prime efficiency benchmarks (PR ≥ 75%). Continue scheduled quarterly wipe-downs.', C.green));
    } else if (pr >= 60) {
      recs.add(('PR is ${pr.round()}%, below the 75% benchmark. Check soiling, shade and loose connections, and clean the panels.', C.amber));
    } else {
      recs.add(('PR is only ${pr.round()}%. Inspect string voltage and current, inverter error logs and shading as soon as possible.', C.red));
    }
    if (ratio > 1.3) {
      recs.add(('DC/AC ratio is ${ratio.toStringAsFixed(2)}, so the inverter will clip around noon. A larger inverter recovers that energy.', C.amber));
    } else if (ratio > 0 && ratio < .8) {
      recs.add(('DC/AC ratio is ${ratio.toStringAsFixed(2)}. The inverter is large for this array and runs at low load much of the day.', C.amber));
    } else if (ratio > 0) {
      recs.add(('Inverter conversion looks healthy with minimal clipping (DC/AC ${ratio.toStringAsFixed(2)}).', C.green));
    }
    if (lastWash == null) {
      recs.add(('No cleaning is logged yet. Log washes in Service so soiling loss can be tracked.', C.blue));
    } else {
      final d = DateTime.now().difference(lastWash).inDays;
      recs.add((d > 90 ? 'Last wash was $d days ago. Dust can cost 5 to 10% of output, so schedule a cleaning.' : 'Last wash was $d days ago. Cleaning is up to date.', d > 90 ? C.amber : C.green));
    }
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.health_and_safety_outlined, C.blue, 'Installed Equipment Specifications', 'Describe the plant to audit its performance'),
          if (snap != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  final rated = snap.ratedKw > 0 ? snap.ratedKw : s.site.kwp;
                  final panelW = _num(exWp) > 0 ? _num(exWp) : 550.0;
                  exQty.text = (rated * 1000 / panelW).round().toString();
                  exInv.text = rated.toStringAsFixed(1);
                  final mo = snap.monthKwh > 0 ? snap.monthKwh : snap.todayKwh * 30;
                  if (mo > 0) exGen.text = mo.round().toString();
                });
                toast(context, 'Loaded live inverter metrics into audit.');
              },
              icon: const Icon(Icons.electric_bolt, size: 17),
              label: Text('Load from Connected Inverter (${snap.brand.toUpperCase()})', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
          _gap(),
          Row(children: [
            Expanded(child: _field(exWp, 'Panel wattage', suffix: 'W')),
            const SizedBox(width: 10),
            Expanded(child: _field(exQty, 'Panel quantity', decimal: false)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Total capacity', style: TextStyle(color: C.mute, fontSize: 11.5)), Text('${kwp.toStringAsFixed(2)} kWp', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]))),
            const SizedBox(width: 10),
            Expanded(child: _field(exInv, 'Inverter capacity', suffix: 'kW')),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: exArch,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Inverter architecture', isDense: true),
            items: [for (final a in const ['String inverter (Central MPPT)', 'Micro-inverters', 'Power optimizers', 'Hybrid inverter', 'Off-grid PCU']) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (v) => setState(() => exArch = v ?? exArch),
          ),
          const SizedBox(height: 10),
          _field(exGen, 'Actual generation last month', suffix: 'kWh'),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AUDIT', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .5)),
          const SizedBox(height: 10),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_stat('EXPECTED / MONTH', '${expected.round()} kWh', sub: '${y.toStringAsFixed(1)} sun-hours/day'), _stat('ACTUAL', act > 0 ? '${act.round()} kWh' : '-', c: C.blue)])),
          const SizedBox(height: 8),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_stat('PERFORMANCE RATIO', pr > 0 ? '${pr.round()}%' : '-', c: pr >= 75 ? C.green : (pr > 0 ? C.amber : C.mute), sub: 'Benchmark 75%'), _stat('DC / AC RATIO', ratio > 0 ? ratio.toStringAsFixed(2) : '-', sub: 'Normal 0.9 to 1.3')])),
        ]),
      ),
      _gap(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.fact_check_outlined, color: C.green, size: 20), const SizedBox(width: 8), const Expanded(child: Text('DIAGNOSTIC & MAINTENANCE RECOMMENDATIONS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: .3)))]),
          const SizedBox(height: 10),
          for (var i = 0; i < recs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 11, backgroundColor: recs[i].$2.withValues(alpha: .18), child: Text('${i + 1}', style: TextStyle(color: recs[i].$2, fontWeight: FontWeight.w800, fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Text(recs[i].$1, style: const TextStyle(fontSize: 14, height: 1.35))),
              ]),
            ),
          Text('Performance ratio uses the sun-hours of your location, so treat it as an estimate. Use the logger or meter data for a formal audit.', style: TextStyle(color: C.mute, fontSize: 11.5)),
        ]),
      ),
      _gap(),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => s.setTab(0), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: C.text), child: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: () => s.setTab(4), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: C.blue), child: const Text('Log Maintenance', style: TextStyle(fontWeight: FontWeight.w800)))),
      ]),
    ];
  }

  // ---------- Standalone Generation Calculator ----------
  List<Widget> _generation() {
    final r = s.result;
    final kw = _num(genKw) > 0 ? _num(genKw) : (r?.kw ?? s.site.kwp);
    final use = _num(genUse) > 0 ? _num(genUse) : (r?.monthlyUnits ?? 400.0);
    final tariff = _num(genTariff) > 0 ? _num(genTariff) : (r != null ? s.input.tariff : s.unitPrice);
    final y = s.locationYield;
    final dailyGen = kw * y;
    final annualGen = dailyGen * 365;
    final monthlyGen = annualGen / 12;

    final flow = energyFlow(monthlyGen: monthlyGen, monthlyUse: use, tariff: tariff, exportRate: s.st.exportRate);
    final cover = use > 0 ? (flow.selfUse / use * 100).round() : 0;

    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(Icons.flash_on, C.green, 'Power Generation & Yield Calculator', '${s.site.city} · ${y.toStringAsFixed(2)} kWh/kWp/day location yield'),
          _gap(12),
          Row(children: [
            Expanded(child: _field(genKw, 'System size', suffix: 'kW')),
            const SizedBox(width: 10),
            Expanded(child: _field(genUse, 'Monthly usage', suffix: 'kWh')),
          ]),
          const SizedBox(height: 10),
          _field(genTariff, 'Tariff rate (blank = ₹${tariff.toStringAsFixed(2)})', prefix: '₹ ', suffix: '/kWh'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final preset in const [1.0, 2.0, 3.0, 5.0, 10.0])
              ChoiceChip(
                label: Text('${_t(preset)} kW', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                selected: (kw - preset).abs() < 0.05,
                onSelected: (_) => setState(() => genKw.text = _t(preset)),
              ),
          ]),
        ]),
      ),
      _gap(),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F9B8E), Color(0xFF0B6E8A)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.flash_on, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('ESTIMATED POWER GENERATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .4))),
            Text('${_t(double.parse(kw.toStringAsFixed(2)))} kW System', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(groupIndian(monthlyGen), style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            const Text('kWh / Month', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          const Divider(color: Colors.white24),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Daily Generation', style: TextStyle(color: Colors.white70, fontSize: 11.5)), Text('${dailyGen.toStringAsFixed(1)} kWh/day', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Annual Energy Output', style: TextStyle(color: Colors.white70, fontSize: 11.5)), Text('${groupIndian(annualGen)} kWh/yr', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
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
    final ql = q.toLowerCase();
    final rows = q.isEmpty
        ? s.records
        : s.records.where((r) {
            final c = r.customer;
            return [c.usc, c.name, c.phone, c.address].any((x) => x.toLowerCase().contains(ql));
          }).toList();
    return [
      TextField(
        controller: search,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by USC, name, phone or address'),
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
          Text('${c.usc.isEmpty ? '' : 'USC ${c.usc} · '}${c.phone.isEmpty ? 'No phone' : c.phone}${c.address.isEmpty ? '' : '\n${c.address}'}', style: TextStyle(color: C.mute, fontSize: 12.5)),
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
