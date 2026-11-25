import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/calc.dart';
import '../core/usc.dart';
import 'theme.dart';

/// The USC block of the Estimator's New Install page: lookup, official bill,
/// 12-month averages, DISCOM ledger and saved history.
/// [onApply] receives the record when the user chooses to use its 12-month average.
class UscSection extends StatefulWidget {
  final UscSource source;
  final void Function(UscRecord record) onApply;
  const UscSection({super.key, required this.onApply, this.source = const UnconfiguredUscSource()});

  @override
  State<UscSection> createState() => _UscSectionState();
}

class _UscSectionState extends State<UscSection> {
  final usc = TextEditingController();
  final captcha = TextEditingController();
  UscRegion? region = UscRegion.telangana;
  Discom? discom = kDiscoms.first;
  bool busy = false;
  bool showLedger = false;
  String? error;
  String? notice;
  UscRecord? result;
  Set<int> openRows = {};
  List<UscRecord> saved = [];

  @override
  void initState() {
    super.initState();
    UscStore.load().then((v) {
      if (mounted) setState(() => saved = v);
    });
  }

  @override
  void dispose() {
    usc.dispose();
    captcha.dispose();
    super.dispose();
  }

  bool get _validUsc => validateUsc(usc.text, discom: discom) == null;

  /// Matches the typed number to a DISCOM by its confirmed length rule.
  /// Sets the state and DISCOM when one rule matches; otherwise asks the user to choose.
  void _onNumberChanged() {
    final candidates = detectDiscoms(usc.text);
    setState(() {
      error = null;
      if (candidates.length == 1 && candidates.first != discom) {
        final d = candidates.first;
        region = d.region;
        discom = d;
        result = null;
        captcha.clear();
        notice = 'Matched ${d.region.label} (${d.code}) by USC length.';
      } else if (candidates.length > 1 && (discom == null || !candidates.contains(discom))) {
        notice = 'This length fits ${candidates.map((d) => d.code).join(' or ')}. Choose one.';
      } else {
        notice = null;
      }
    });
  }

  Future<void> _fetch() async {
    final d = discom;
    if (d == null) {
      setState(() => error = 'Choose a state and DISCOM first');
      return;
    }
    final problem = validateUsc(usc.text, discom: d);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    final needsCaptcha = widget.source.needsCaptcha(d);
    if (needsCaptcha && captcha.text.trim().isEmpty) {
      setState(() => error = 'Type the captcha shown by ${d.code}');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final r = await widget.source.fetch(
        usc: cleanUscNumber(usc.text),
        discom: d,
        captcha: needsCaptcha ? captcha.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        busy = false;
        result = r;
        openRows = {};
      });
    } on UscException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message;
        captcha.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Could not reach ${d.code}. Check the connection and try again.';
      });
    }
  }

  Future<void> _saveCurrent() async {
    final r = result;
    if (r == null) return;
    final next = [r, ...saved.where((s) => !_same(s, r))];
    setState(() => saved = next);
    await UscStore.save(next);
  }

  Future<void> _deleteSaved(UscRecord r) async {
    final next = saved.where((s) => !_same(s, r)).toList();
    setState(() => saved = next);
    await UscStore.save(next);
  }

  bool _same(UscRecord a, UscRecord b) => a.usc == b.usc && a.discom.code == b.discom.code;

  void _rerun(UscRecord r) {
    setState(() {
      region = r.discom.region;
      discom = r.discom;
      usc.text = r.usc;
      captcha.clear();
      error = null;
      notice = 'Type the ${r.discom.code} captcha and tap Fetch to refresh.';
    });
  }

  Future<void> _openPortal(Discom d) async {
    final url = portalUrlFor(d);
    if (url == null) {
      toast(context, 'Portal link for ${d.code} is not set yet');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Unique Service Number (USC No.)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          if (usc.text.isNotEmpty) _pill(_validUsc ? 'USC Format Ready' : 'Check USC format', _validUsc ? C.sky : C.red),
        ]),
        const SizedBox(height: 10),
        _regionRow(),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 300;
          final field = TextField(
            controller: usc,
            keyboardType: TextInputType.number,
            onChanged: (_) => _onNumberChanged(),
            decoration: InputDecoration(
              hintText: 'Enter USC number',
              isDense: true,
              prefixIcon: Icon(Icons.search, color: C.mute),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _validUsc ? C.green : C.line, width: 1.4)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.green, width: 1.6)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          );
          final button = FilledButton.icon(
            onPressed: busy ? null : _fetch,
            style: FilledButton.styleFrom(backgroundColor: C.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(busy ? 'Fetching…' : 'Fetch Govt Bill', style: const TextStyle(fontWeight: FontWeight.w800)),
          );
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, const SizedBox(height: 10), button]);
          }
          return Row(children: [Expanded(child: field), const SizedBox(width: 10), button]);
        }),
        if (discom != null && widget.source.needsCaptcha(discom!)) ...[
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: captcha,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Captcha',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Enter the captcha shown on ${discom!.code}', style: TextStyle(color: C.mute, fontSize: 12))),
          ]),
        ],
        if (_validUsc && discom != null) ...[
          const SizedBox(height: 10),
          Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: C.mute, height: 1.4), children: [
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.check, size: 15, color: C.green)),
            TextSpan(text: ' Valid USC format', style: TextStyle(color: C.green, fontWeight: FontWeight.w800)),
            TextSpan(text: ' · ${cleanUscNumber(usc.text).length}-digit USC No matched ${discom!.region.label} (${discom!.code}) · USC Number (Unique Service 8-12 digits)'),
          ])),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: TextStyle(color: C.red, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
        if (notice != null) ...[
          const SizedBox(height: 10),
          Text(notice!, style: TextStyle(color: C.amber, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        _infoBox(Icons.receipt_long_outlined, C.green, 'Monthly units & bills are synced automatically from official government DISCOM portals.'),
        if (r != null) ..._resultBlocks(r),
        if (saved.isNotEmpty) ..._historyBlock(),
      ]),
    );
  }

  Widget _regionRow() => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final reg in UscRegion.values)
          ChoiceChip(
            label: Text(reg.label, style: const TextStyle(fontSize: 12.5)),
            selected: region == reg,
            onSelected: (_) => setState(() {
              region = reg;
              discom = discomsFor(reg).first;
              result = null;
              error = null;
              notice = null;
            }),
          ),
        if (region != null)
          for (final d in discomsFor(region!))
            ChoiceChip(
              label: Text(d.code, style: const TextStyle(fontSize: 12.5)),
              selected: discom == d,
              onSelected: (_) => setState(() {
                discom = d;
                result = null;
                error = null;
                notice = null;
                captcha.clear();
              }),
            ),
      ]);

  List<Widget> _resultBlocks(UscRecord r) {
    final months = r.last12;
    final missing = r.missingMonths;
    final ledger = r.months; // all months, newest first in the table
    final verified = r.verifiedMonths;
    final total = r.months.length;
    return [
      const SizedBox(height: 14),
      // Consumer card
      Panel(
        border: C.green.withValues(alpha: .5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline, color: C.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.consumerName.isEmpty ? 'Consumer name not on portal' : r.consumerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                _pill('$verified/$total Portal Verified', C.green),
                const SizedBox(height: 6),
                Text('${r.discom.region.label} (${r.discom.code}) · Verified Live · ${r.discom.code} Official Portal History',
                    style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.35)),
                Text('Live Sync: ${_stamp(r.fetchedAt)} IST', style: TextStyle(color: C.green, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
            Column(children: [
              IconButton(
                tooltip: 'Fetch again',
                onPressed: () => _rerun(r),
                icon: Icon(Icons.refresh, color: C.mute),
              ),
              OutlinedButton(
                onPressed: () => _openPortal(r.discom),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Portal'), const SizedBox(width: 4), Icon(Icons.open_in_new, size: 14, color: C.blue)]),
              ),
            ]),
          ]),
          const SizedBox(height: 12),
          _infoBox(Icons.apartment_outlined, C.blue,
              'Fetched $total verified billing months${r.bill != null ? ' + live bill (${r.consumerName}): ${r.bill!.billUnits.round()} kWh · ₹${groupIndian(r.bill!.billAmount.round())} · ${r.bill!.loadPhase} from ${r.discom.code}.' : ' from ${r.discom.code}.'}'),
        ]),
      ),
      if (r.bill != null) ...[const SizedBox(height: 12), _officialBill(r)],
      const SizedBox(height: 12),
      // Averages
      Row(children: [
        Expanded(child: _avgCard('12-Mo Verified Avg Units', '${r.avgUnits.round()} kWh', '12M Total (${_range(r)}): ${groupIndian(r.totalUnits12.round())} kWh', C.amber)),
        const SizedBox(width: 10),
        Expanded(child: _avgCard('12-Mo Verified Avg Bill', '₹${groupIndian(r.avgBill.round())}', '12M Total ${_money2(r.totalBill12)} · Peak ${_peak(r)}', C.green)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Icon(Icons.trending_up, size: 18, color: C.green),
        const SizedBox(width: 6),
        Expanded(child: Text('${_range(r)} (12M Live Avg)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        Text('Blended ₹${r.blendedRate.toStringAsFixed(2)}/kWh', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: C.green)),
      ]),
      const SizedBox(height: 8),
      Panel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        child: Column(children: [
          BarChart(
            height: 130,
            series: [BarSeries('Units', [for (final m in ledger) m.units], C.green)],
            labels: [for (final m in ledger) m.month.split(' ').first],
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text('#1 Verified: ${ledger.isEmpty ? '' : ledger.first.month}', style: TextStyle(color: C.mute, fontSize: 12))),
            Text('Latest: ${ledger.isEmpty ? '' : ledger.last.month}', style: TextStyle(color: C.green, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ]),
      ),
      if (missing > 0) ...[
        const SizedBox(height: 8),
        Text('$missing of 12 months not on the portal. They count as 0.', style: TextStyle(color: C.amber, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ],
      const SizedBox(height: 12),
      // Ledger
      Row(children: [
        _pill('Govt DISCOM Bills', C.green),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => showLedger = !showLedger),
          child: Text(showLedger ? 'Hide ${total}-Mo DISCOM Bills' : 'Show ${total}-Mo DISCOM Bills', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
      if (showLedger) _ledger(ledger),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () => widget.onApply(r),
          child: Text(
            'Synced (12-Mo Avg · ${_range(r)}): ${r.avgUnits.round()} kWh/mo · ₹${groupIndian(r.avgBill.round())}/mo',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _saveCurrent, child: const Text('Save to history'))),
      ]),
    ];
  }

  Widget _officialBill(UscRecord r) {
    final b = r.bill!;
    return Panel(
      border: C.blue.withValues(alpha: .5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _pill('OFFICIAL DISCOM BILL', C.blue),
          const Spacer(),
          OutlinedButton(
            onPressed: () => _openPortal(r.discom),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Official e-Bill'), const SizedBox(width: 4), Icon(Icons.open_in_new, size: 14, color: C.blue)]),
          ),
        ]),
        const SizedBox(height: 10),
        Text('Bill #${b.billNo}', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('${b.billUnits.round()} kWh · ₹${groupIndian(b.billAmount.round())}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28)),
        ),
        Text('${r.consumerName} · USC ${r.usc}', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('ERO: ${b.ero} · Sec: ${b.section} · Meter: ${b.meterNo}', style: TextStyle(color: C.mute, fontSize: 12.5)),
        if (r.address.isNotEmpty) Text(r.address, style: TextStyle(color: C.mute, fontSize: 12.5)),
        const Divider(height: 22),
        _kv2('Category', b.category, 'Load/Phase', b.loadPhase),
        _kv2('Meter', b.meterReading, 'Bill Date', b.billDate),
        _kv2('Due Date', b.dueDate, 'Last Paid', b.lastPaid),
        _kv2('Disconn. Date', b.disconnDate, 'Total Payable', '₹${groupIndian(b.totalPayable.round())}'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GOVT BILL CHARGE BREAKUP (${r.discom.code} OFFICIAL API)', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, children: [
              for (final c in b.charges)
                SizedBox(
                  width: 140,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Flexible(child: Text(c.label, style: TextStyle(color: C.mute, fontSize: 12.5))),
                    Text(c.amount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _ledger(List<UscMonth> ledger) {
    final rows = ledger.reversed.toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            Expanded(flex: 4, child: Text('Month (Govt Ledger)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
            Expanded(flex: 2, child: Text('Units (kWh)', textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
            Expanded(flex: 3, child: Text('DISCOM Bill (₹)', textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
          ]),
        ),
        const Divider(height: 1),
        for (var i = 0; i < rows.length; i++) _ledgerRow(rows, i),
      ]),
    );
  }

  Widget _ledgerRow(List<UscMonth> rows, int i) {
    final m = rows[i];
    final open = openRows.contains(i);
    return Column(children: [
      InkWell(
        onTap: m.present || !m.onPortal
            ? null
            : () => setState(() {
                  open ? openRows.remove(i) : openRows.add(i);
                }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(
              flex: 5,
              child: Row(children: [
                Text('${i + 1}.', style: TextStyle(color: C.mute, fontSize: 12.5)),
                const SizedBox(width: 6),
                Flexible(child: Text(m.month, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                if (m.present)
                  _pill('Present', C.sky)
                else if (m.onPortal)
                  _pill('Govt', C.green),
              ]),
            ),
            Expanded(flex: 2, child: Text(m.onPortal ? '${m.units.round()}' : '0', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 3,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(m.onPortal ? groupIndian(m.bill.round()) : '0', style: TextStyle(fontWeight: FontWeight.w800, color: C.green)),
                if (!m.present && m.onPortal) Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: C.mute),
              ]),
            ),
          ]),
        ),
      ),
      if (open && m.onPortal)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            _mini('Arrears', '₹${groupIndian(m.arrears.round())}'),
            _mini('Bill', '₹${groupIndian(m.bill.round())}'),
            _mini('Paid', '₹${groupIndian(m.paid.round())}'),
            _mini('Adjst', '₹${groupIndian(m.adjust.round())}'),
            _mini('Bal', '₹${groupIndian(m.balance.round())}'),
          ]),
        ),
      const Divider(height: 1),
    ]);
  }

  List<Widget> _historyBlock() => [
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('USC History', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          _pill('${saved.length} Saved', C.green),
        ]),
        const SizedBox(height: 4),
        Text('Saved on this device.', style: TextStyle(color: C.mute, fontSize: 12.5)),
        const SizedBox(height: 10),
        for (final s in saved)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              radius: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('USC #${s.usc}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                  _pill(s.discom.code, C.amber),
                  const SizedBox(width: 6),
                  _pill('Local Only', C.mute),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _deleteSaved(s),
                    icon: Icon(Icons.delete_outline, color: C.mute),
                  ),
                ]),
                const SizedBox(height: 4),
                _pill('${s.verifiedMonths}/${s.months.length} Verified', C.green),
                const SizedBox(height: 6),
                Text('${s.consumerName.isEmpty ? 'Consumer' : s.consumerName} · 12M Avg ${s.avgUnits.round()} kWh/mo · ₹${groupIndian(s.avgBill.round())}/mo',
                    style: TextStyle(color: C.mute, fontSize: 12.5)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: C.orange, foregroundColor: Colors.white),
                      onPressed: () => _rerun(s),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Re-Run Fetch'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        result = s;
                        openRows = {};
                        error = null;
                        notice = null;
                      }),
                      child: const Text('Load in Audit'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
      ];

  // ---- small helpers ----

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.withValues(alpha: .4))),
        child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );

  Widget _infoBox(IconData ic, Color c, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .3))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: C.text))),
        ]),
      );

  Widget _avgCard(String label, String value, String sub, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withValues(alpha: .4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24))),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.3)),
        ]),
      );

  Widget _kv2(String a, String av, String b, String bv) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text.rich(TextSpan(style: TextStyle(color: C.text, fontSize: 13), children: [
            TextSpan(text: '$a: ', style: TextStyle(color: C.mute)),
            TextSpan(text: av, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]))),
          Expanded(child: Text.rich(TextSpan(style: TextStyle(color: C.text, fontSize: 13), children: [
            TextSpan(text: '$b: ', style: TextStyle(color: C.mute)),
            TextSpan(text: bv, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]))),
        ]),
      );

  Widget _mini(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: C.mute, fontSize: 11)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ]);

  String _range(UscRecord r) {
    final l = r.last12;
    if (l.isEmpty) return '';
    return '${l.first.month} to ${l.last.month}';
  }

  String _peak(UscRecord r) {
    final l = r.last12;
    if (l.isEmpty) return '';
    var best = l.first;
    for (final m in l) {
      if (m.bill > best.bill) best = m;
    }
    return best.month;
  }

  String _money2(double v) {
    final paise = (v * 100).round();
    return '₹${groupIndian(paise ~/ 100)}.${(paise % 100).toString().padLeft(2, '0')}';
  }

  String _stamp(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${two(l.day)} ${mon[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
  }
}

/// Official portal page for each DISCOM. Null means not confirmed yet, so no link is shown.
String? portalUrlFor(Discom d) => null;
