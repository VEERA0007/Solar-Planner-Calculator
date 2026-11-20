import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/calc.dart';
import '../core/store.dart';
import 'pdf_quote.dart';
import 'theme.dart';

class EstimatorPage extends StatefulWidget {
  final AppState state;
  const EstimatorPage({super.key, required this.state});
  @override
  State<EstimatorPage> createState() => _EstimatorPageState();
}

class _EstimatorPageState extends State<EstimatorPage> {
  int sub = 0; // 0 estimate, 1 results, 2 saved
  final usc = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final search = TextEditingController();
  final Map<String, TextEditingController> nums = {};
  String uscMsg = '';
  Color uscColor = C.mute;
  String mode = 'units';
  String category = 'residential';
  bool subsidy = true;

  static const _fields = <String, String>{
    'monthlyUnits': 'Average units per month (kWh)',
    'monthlyBill': 'Average bill per month (Rs.)',
    'tariff': 'Avg tariff (Rs./unit)',
    'coverage': 'Offset (% of use)',
    'yieldPerKwDay': 'Yield (kWh/kW/day)',
    'panelWp': 'Panel (Wp)',
    'costPerKw': 'Cost (Rs./kW)',
    'areaPerKw': 'Roof area (sq m/kW)',
    'degradation': 'Degradation (%/yr)',
    'escalation': 'Tariff rise (%/yr)',
  };

  @override
  void initState() {
    super.initState();
    _fill(EstimateInput());
    final p = widget.state.profile;
    usc.text = p.serviceNo;
    name.text = p.name;
    phone.text = p.mobile;
    address.text = p.address;
  }

  void _fill(EstimateInput d) {
    final j = d.toJson();
    for (final k in _fields.keys) {
      final v = j[k] as num;
      final t = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
      (nums[k] ??= TextEditingController()).text = t;
    }
    mode = d.mode;
    category = d.category;
    subsidy = d.subsidy;
  }

  @override
  void dispose() {
    for (final c in [usc, name, phone, address, search, ...nums.values]) {
      c.dispose();
    }
    super.dispose();
  }

  EstimateInput _readInput() {
    double n(String k) => double.tryParse(nums[k]!.text.trim().replaceAll(',', '')) ?? double.nan;
    final d = EstimateInput();
    double or(String k, double def) {
      final v = n(k);
      return v.isFinite ? v : def;
    }

    return EstimateInput(
      mode: mode,
      monthlyUnits: or('monthlyUnits', 0),
      monthlyBill: or('monthlyBill', 0),
      tariff: or('tariff', 0),
      coverage: or('coverage', d.coverage),
      yieldPerKwDay: or('yieldPerKwDay', d.yieldPerKwDay),
      panelWp: or('panelWp', d.panelWp),
      costPerKw: or('costPerKw', d.costPerKw),
      areaPerKw: or('areaPerKw', d.areaPerKw),
      degradation: or('degradation', d.degradation),
      escalation: or('escalation', d.escalation),
      category: widget.state.prefs.category == 'domestic' ? 'residential' : 'commercial',
      subsidy: subsidy,
    );
  }

  Customer _readCustomer() => Customer(
        usc: normalizeUsc(usc.text),
        name: name.text.trim(),
        phone: phone.text.trim(),
        address: address.text.trim(),
      );

  void _uscChanged(String _) {
    final v = normalizeUsc(usc.text);
    setState(() {
      if (v.isEmpty) {
        uscMsg = '';
      } else if (isValidUsc(v)) {
        uscMsg = 'Valid 9-digit USC format.';
        uscColor = C.green;
      } else {
        uscMsg = 'USC numbers are normally 9 digits. You can still search.';
        uscColor = C.amber;
      }
    });
  }

  void _uscSearch() {
    final s = widget.state;
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
        uscMsg = 'Found saved estimate for ${exact.first.customer.name.isEmpty ? 'this USC' : exact.first.customer.name} (${exact.length} saved). Details filled in.';
        uscColor = C.green;
      });
      toast(context, 'USC found - details loaded');
      return;
    }
    final partial = s.records.where((r) => normalizeUsc(r.customer.usc).contains(v)).length;
    if (partial > 0) {
      search.text = v;
      setState(() => sub = 2);
      toast(context, '$partial partial match(es)');
      return;
    }
    setState(() {
      uscMsg = 'No saved estimate for this USC yet. Enter units from the bill below, or open the DISCOM site to check the bill.';
      uscColor = C.amber;
    });
  }

  void _load(SavedRecord r) {
    usc.text = r.customer.usc;
    name.text = r.customer.name;
    phone.text = r.customer.phone;
    address.text = r.customer.address;
    _fill(r.input);
  }

  void _calc() {
    final inp = _readInput();
    final use = inp.mode == 'bill' ? inp.monthlyBill : inp.monthlyUnits;
    if (!(use > 0)) return toast(context, 'Enter monthly units or bill');
    final s = widget.state;
    final plan = s.tariffCat;
    // slab tariff: units from the bill, and the average rate actually avoided by solar
    final units = inp.mode == 'bill' ? plan.unitsForBill(inp.monthlyBill) : inp.monthlyUnits;
    final off = units * inp.coverage.clamp(0, 100) / 100;
    final eff = off > 0 ? (plan.bill(units) - plan.bill(units - off)) / off : plan.marginal(units);
    inp
      ..monthlyBill = plan.bill(units)
      ..mode = 'units'
      ..monthlyUnits = units
      ..tariff = double.parse(eff.toStringAsFixed(2))
      ..yieldPerKwDay = double.parse(s.locationYield.toStringAsFixed(2));
    s.input = inp;
    s.customer = _readCustomer();
    s.result = calculate(inp);
    s.publishEstimate(s.result!.kw, inp.tariff);
    setState(() => sub = 1);
  }

  void _save() {
    final s = widget.state;
    final r = s.result;
    if (r == null) return;
    final c = _readCustomer();
    if (c.usc.isEmpty && c.name.isEmpty) {
      toast(context, 'Add a USC number or customer name first');
      setState(() => sub = 0);
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
      await shareQuote(c, r, widget.state.brand);
    } catch (e) {
      if (mounted) toast(context, 'Could not create PDF: $e');
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _ro(String label, String value, {double top = 10}) => Padding(
        padding: EdgeInsets.only(top: top),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: Icon(Icons.lock_outline, size: 16, color: C.mute)),
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _tf(String key, {double top = 10}) => Padding(
        padding: EdgeInsets.only(top: top),
        child: TextField(
          controller: nums[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: _fields[key]),
        ),
      );

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const PageHead('Estimator', 'Size, cost, subsidy and payback · USC search'),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 0, label: Text('Estimate')),
            const ButtonSegment(value: 1, label: Text('Results')),
            ButtonSegment(value: 2, label: Text('Saved (${s.records.length})')),
          ],
          selected: {sub},
          onSelectionChanged: (v) => setState(() => sub = v.first),
        ),
        const SizedBox(height: 14),
        if (sub == 0) ..._form(),
        if (sub == 1) ..._results(),
        if (sub == 2) ..._saved(),
      ],
    );
  }

  List<Widget> _form() => [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('Customer & USC'),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  controller: usc,
                  keyboardType: TextInputType.number,
                  onChanged: _uscChanged,
                  onSubmitted: (_) => _uscSearch(),
                  decoration: const InputDecoration(labelText: 'USC number (Unique Service Connection)', hintText: 'e.g. 123456789'),
                ),
              ),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 2), child: FilledButton(onPressed: _uscSearch, style: FilledButton.styleFrom(minimumSize: const Size(0, 50)), child: const Text('Search'))),
            ]),
            if (uscMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(uscMsg, style: TextStyle(color: uscColor, fontSize: 12.5))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: () => _open('https://tgsouthernpower.org'), child: const Text('Open TGSPDCL bill site')),
              OutlinedButton(onPressed: () => _open('https://tgnpdcl.com'), child: const Text('Open TGNPDCL')),
            ]),
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer name'))),
            Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'))),
            Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: address, decoration: const InputDecoration(labelText: 'Address / location'))),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('Consumption'),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'units', label: Text('Monthly units')), ButtonSegment(value: 'bill', label: Text('Monthly bill'))],
              selected: {mode},
              onSelectionChanged: (v) => setState(() => mode = v.first),
            ),
            _tf(mode == 'units' ? 'monthlyUnits' : 'monthlyBill'),
            Row(children: [Expanded(child: _ro('Tariff (Rs./unit)', widget.state.unitPrice.toStringAsFixed(2))), const SizedBox(width: 10), Expanded(child: _tf('coverage'))]),
            Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text('${widget.state.slabText} · ${widget.state.discom.name}. Change state, grid or category in Settings.', style: TextStyle(color: C.mute, fontSize: 12))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _ro('Category', widget.state.t(widget.state.prefs.category), top: 0)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<bool>(
                  initialValue: subsidy,
                  decoration: const InputDecoration(labelText: 'Subsidy (PM Surya Ghar)'),
                  items: const [DropdownMenuItem(value: true, child: Text('Apply')), DropdownMenuItem(value: false, child: Text('Do not apply'))],
                  onChanged: (v) => setState(() => subsidy = v ?? subsidy),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('Advanced assumptions', style: TextStyle(color: C.amber, fontWeight: FontWeight.w800)),
              children: [
                Row(children: [Expanded(child: _ro('Yield (kWh/kW/day), from location', widget.state.locationYield.toStringAsFixed(2), top: 4)), const SizedBox(width: 10), Expanded(child: _tf('panelWp', top: 4))]),
                Row(children: [Expanded(child: _tf('costPerKw')), const SizedBox(width: 10), Expanded(child: _tf('areaPerKw'))]),
                Row(children: [Expanded(child: _tf('degradation')), const SizedBox(width: 10), Expanded(child: _tf('escalation'))]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => setState(() => _fill(EstimateInput())), child: const Text('Reset to defaults')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _calc,
          style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 18), backgroundColor: C.amber, foregroundColor: Color(0xFF1C1300)),
          child: const Text('Calculate estimate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ];

  /// Night battery backup sized from the appliance profile (hours without sun).
  List<Widget> _battery() {
    final s = widget.state;
    final load = s.loadHourly();
    var night = 0.0;
    for (var h = 0; h < 24; h++) {
      if (h < 6 || h >= 18) night += load[h];
    }
    final usable = night / 0.9; // 90% depth of discharge
    final peak = load.fold<double>(0, (a, b) => a > b ? a : b);
    return [
      Panel(
        border: C.blue,
        child: Row(children: [
          Icon(Icons.battery_charging_full, color: C.blue, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('battery_sim'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('Night load ${night.toStringAsFixed(1)} kWh → battery about ${usable.toStringAsFixed(1)} kWh, inverter peak ${peak.toStringAsFixed(1)} kW',
                  style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _results() {
    final r = widget.state.result;
    if (r == null) {
      return [Panel(child: Center(child: Text('Enter consumption on the Estimate tab to see your solar plan.', style: TextStyle(color: C.mute), textAlign: TextAlign.center)))];
    }
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Text('${fmt1(r.kw)} kW', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Color(0xFF1C1300))),
          Text('${r.panels} x ${r.panelWp.round()} Wp panels', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF3A2A00))),
        ]),
      ),
      const SizedBox(height: 12),
      if (widget.state.prefs.battery) ..._battery(),
      StatGrid([
        StatTile('Roof area needed', '${r.roofSqft.round()} sq ft (${r.roofSqm.round()} sq m)'),
        StatTile('Generation / year', '${groupIndian(r.gen1)} kWh'),
        StatTile('Project cost', inr(r.cost)),
        StatTile('Subsidy', r.subsidy > 0 ? inr(r.subsidy) : 'None'),
        StatTile('Net cost', inr(r.netCost), hi: true),
        StatTile('Payback', r.paybackYears == null ? 'Over ${r.years} yrs' : '${fmt1(r.paybackYears!)} years', hi: true),
        StatTile('Saving, year 1', inr(r.year1Saving)),
        StatTile('Saving / month', inr(r.monthlySaving)),
        StatTile('${r.years}-yr profit', inr(r.lifetimeProfit)),
        StatTile('CO₂ avoided / yr', '${fmt1(r.co2Tonnes)} t'),
      ]),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _h('Cumulative net savings'),
          const SizedBox(height: 8),
          NetChart(r.series.map((e) => e.net).toList()),
          const SizedBox(height: 6),
          Text('Bars below zero are money still to be recovered. Includes panel degradation and yearly tariff rise.', style: TextStyle(color: C.mute, fontSize: 12.5)),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: FilledButton(onPressed: _save, style: FilledButton.styleFrom(backgroundColor: C.amber, foregroundColor: Color(0xFF1C1300), padding: EdgeInsets.symmetric(vertical: 16)), child: Text('Save estimate', style: TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton(onPressed: () => _quote(_readCustomer(), r), style: FilledButton.styleFrom(backgroundColor: C.amber, foregroundColor: Color(0xFF1C1300), padding: EdgeInsets.symmetric(vertical: 16)), child: Text('Quote PDF', style: TextStyle(fontWeight: FontWeight.w800)))),
      ]),
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
                  setState(() => sub = 1);
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
