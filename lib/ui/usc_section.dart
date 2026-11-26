import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/calc.dart';
import '../core/usc.dart';
import '../core/usc_http.dart';
import 'theme.dart';

/// A request to show a saved or fetched USC record in the lookup.
/// [refetch] true fills the form and asks for a fresh captcha; false shows the saved result.
class UscLoad {
  final UscRecord record;
  final bool refetch;
  const UscLoad(this.record, {this.refetch = false});
}

/// Shared between the USC lookup (inside the Monthly card) and the USC History card at the
/// bottom of the New Install page.
class UscLink {
  final ValueNotifier<UscLoad?> load = ValueNotifier<UscLoad?>(null);
  final ValueNotifier<List<UscRecord>> saved = ValueNotifier<List<UscRecord>>(const []);

  void dispose() {
    load.dispose();
    saved.dispose();
  }
}

/// USC lookup body: state and DISCOM interlink, USC field, fetch, official bill,
/// 12-month averages, chart and DISCOM ledger. Placed inside the Monthly card.
class UscSection extends StatefulWidget {
  final UscSource? source;
  final void Function(UscRecord record) onApply;
  final UscLink link;
  const UscSection({super.key, required this.link, required this.onApply, this.source});

  @override
  State<UscSection> createState() => _UscSectionState();
}

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Short state chip label as in the screens: TG, AP, OD, CHD.
String stateChipLabel(UscRegion r) => switch (r) {
      UscRegion.telangana => 'TG',
      UscRegion.andhra => 'AP',
      UscRegion.odisha => 'OD',
      UscRegion.chhattisgarh => 'CHD',
    };

String _monthLabel(DateTime d) => '${_monthShort[d.month - 1]} ${d.year}';

Widget uscPill(String text, Color c, {bool solid = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? c : c.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .4)),
      ),
      child: Text(text, style: TextStyle(color: solid ? Colors.white : c, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );

class _UscSectionState extends State<UscSection> {
  UscSource get _source => widget.source ?? defaultUscSource();

  final usc = TextEditingController();
  final captcha = TextEditingController();
  final pasteCtl = TextEditingController();
  UscRegion region = UscRegion.telangana;
  Discom? discom = kDiscoms.first;
  bool busy = false;
  bool showLedger = true;
  bool showPaste = false;
  String? pasteError;
  String? error;
  String? notice;
  UscRecord? result;

  @override
  void initState() {
    super.initState();
    widget.link.load.addListener(_onLoad);
    final pending = widget.link.load.value;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onLoad();
      });
    }
  }

  @override
  void dispose() {
    widget.link.load.removeListener(_onLoad);
    usc.dispose();
    captcha.dispose();
    pasteCtl.dispose();
    super.dispose();
  }

  bool get _validUsc => validateUsc(usc.text, discom: discom) == null;

  UscRegion get _region => region;

  Discom get _d => discom ?? kDiscoms.first;

  /// Shows a record sent from History or from the Units tab. Consumes the request.
  void _onLoad() {
    final req = widget.link.load.value;
    if (req == null || !mounted) return;
    widget.link.load.value = null;
    final r = req.record;
    setState(() {
      region = r.discom.region;
      discom = r.discom;
      usc.text = r.usc;
      error = null;
      pasteError = null;
      if (req.refetch) {
        result = null;
        captcha.clear();
        notice = 'Type the ${r.discom.code} captcha and tap Fetch to refresh.';
      } else {
        result = r;
        notice = null;
      }
    });
  }

  /// Matches the typed number to a DISCOM by its confirmed length rule.
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
    final needsCaptcha = _source.needsCaptcha(d);
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
      final r = await _source.fetch(
        usc: cleanUscNumber(usc.text),
        discom: d,
        captcha: needsCaptcha ? captcha.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        busy = false;
        result = r;
      });
      await _saveToHistory(r);
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

  Future<void> _saveToHistory(UscRecord r) async {
    final next = [r, ...widget.link.saved.value.where((s) => !(s.usc == r.usc && s.discom.code == r.discom.code))];
    widget.link.saved.value = next;
    await UscStore.save(next);
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _interlink(),
      const SizedBox(height: 14),
      Row(children: [
        const Expanded(child: Text('Unique Service Number (USC No.)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        if (usc.text.isNotEmpty) uscPill(_validUsc ? 'USC Format Ready' : 'Check USC format', _validUsc ? C.sky : C.red),
      ]),
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
              : const Icon(Icons.sync, size: 18),
          label: Text(busy ? 'Fetching…' : 'Fetch Govt Bill', style: const TextStyle(fontWeight: FontWeight.w800)),
        );
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, const SizedBox(height: 10), button]);
        }
        return Row(children: [Expanded(child: field), const SizedBox(width: 10), button]);
      }),
      if (_source.needsCaptcha(_d)) ...[
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
          Expanded(child: Text('Enter the captcha shown on ${_d.code}', style: TextStyle(color: C.mute, fontSize: 12))),
        ]),
      ],
      if (_validUsc && discom != null) ...[
        const SizedBox(height: 10),
        Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: C.mute, height: 1.4), children: [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.check, size: 15, color: C.green)),
          TextSpan(text: ' Valid USC format', style: TextStyle(color: C.green, fontWeight: FontWeight.w800)),
          TextSpan(text: ' · ${cleanUscNumber(usc.text).length}-digit USC No matched ${_d.region.label} (${_d.code}) · USC Number (Unique Service 8-12 digits)'),
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
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => showPaste = !showPaste),
          icon: const Icon(Icons.content_paste, size: 16),
          label: Text(showPaste ? 'Hide paste' : 'Paste bills from portal instead'),
        ),
      ),
      if (showPaste) _pasteBox(),
      const SizedBox(height: 10),
      _infoBox(Icons.receipt_long_outlined, C.green, 'Monthly units & bills are synced automatically from official government DISCOM portals.'),
      if (r != null) ..._resultBlocks(r),
    ]);
  }

  /// "4-State DISCOM Portal Interlink": state chips, 13-month range, DISCOM buttons.
  Widget _interlink() {
    final d = _d;
    final now = DateTime.now();
    final end = DateTime(now.year, now.month);
    final start = DateTime(now.year, now.month - 12);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.public, color: C.orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('4-State DISCOM Portal Interlink', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          uscPill('Auto-Detected: ${d.code}', C.green),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.amber.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.amber.withValues(alpha: .35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.schedule, color: C.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('13-Mo Range: ${_monthLabel(start)} to ${_monthLabel(end)}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9A4A00)))),
            ]),
            const SizedBox(height: 8),
            uscPill('12 Mo + Current (13 Mo)', C.orange, solid: true),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('Searching End Month:', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.amber.withValues(alpha: .6))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${_monthNames[now.month - 1]} ${now.year}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Icon(Icons.expand_more, size: 18, color: C.mute),
                ]),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (final reg in UscRegion.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _stateButton(reg),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('${_region.label}: ${d.code}', style: TextStyle(color: C.text, fontSize: 14)),
          ),
          InkWell(
            onTap: () => _openPortal(d),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Bill History Portal', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 14, color: C.blue),
            ]),
          ),
        ]),
        const Divider(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final x in discomsFor(_region)) _discomButton(x)]),
      ]),
    );
  }

  Widget _stateButton(UscRegion reg) {
    final on = region == reg;
    return GestureDetector(
      onTap: () => setState(() {
        region = reg;
        discom = discomsFor(reg).first;
        result = null;
        error = null;
        notice = null;
        captcha.clear();
      }),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.orange : C.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? C.orange : C.line),
        ),
        child: Text(stateChipLabel(reg), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: on ? Colors.white : C.text)),
      ),
    );
  }

  Widget _discomButton(Discom x) {
    final on = discom == x;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        discom = x;
        result = null;
        error = null;
        notice = null;
        captcha.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? C.chipBlue : C.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? C.blue : C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(x.code, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: C.text)),
          const SizedBox(width: 6),
          Icon(Icons.open_in_new, size: 13, color: C.mute),
        ]),
      ),
    );
  }

  List<Widget> _resultBlocks(UscRecord r) {
    final ledger = r.months;
    final missing = r.missingMonths;
    final total = r.months.length;
    return [
      const SizedBox(height: 14),
      // USC card
      Panel(
        border: C.green.withValues(alpha: .5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline, color: C.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('USC #${r.usc}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                uscPill('${r.verifiedMonths}/$total Portal Verified', C.green),
                const SizedBox(height: 6),
                Text('${r.discom.region.label} (${r.discom.code}) · Verified live from the official DISCOM portal',
                    style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.35)),
                Text('Live Sync: ${_stamp(r.fetchedAt)} IST', style: TextStyle(color: C.green, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
            Column(children: [
              IconButton(
                tooltip: 'Fetch again',
                onPressed: () => setState(() {
                  result = null;
                  captcha.clear();
                  notice = 'Type the ${r.discom.code} captcha and tap Fetch to refresh.';
                }),
                icon: Icon(Icons.refresh, color: C.mute),
              ),
              OutlinedButton(
                onPressed: () => _openPortal(r.discom),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Portal'), const SizedBox(width: 4), Icon(Icons.open_in_new, size: 14, color: C.blue)]),
              ),
            ]),
          ]),
        ]),
      ),
      if (r.bill != null) ...[const SizedBox(height: 12), _officialBill(r)],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _avgCard('12-Mo Verified Avg Units', '${r.avgUnits.round()} kWh', 'Total (${_range(r)}): ${groupIndian(r.totalUnits12.round())} kWh', C.amber)),
        const SizedBox(width: 10),
        Expanded(child: _avgCard('12-Mo Verified Avg Bill', '₹${groupIndian(r.avgBill.round())}', 'Period ${_money2(r.totalBill12)} · Peak ${_peak(r)}', C.green)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Icon(Icons.trending_up, size: 18, color: C.green),
        const SizedBox(width: 6),
        Expanded(child: Text('${_range(r)} (12M Live)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
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
      Row(children: [
        uscPill('Govt DISCOM Bills', C.green),
        const Spacer(),
        InkWell(
          onTap: () => setState(() => showLedger = !showLedger),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(showLedger ? 'Hide $total-Mo DISCOM Bills' : 'Show $total-Mo DISCOM Bills', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            Icon(showLedger ? Icons.expand_less : Icons.expand_more, size: 18),
          ]),
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
            'Synced (${_range(r)}): ${r.avgUnits.round()} kWh/mo · ₹${groupIndian(r.avgBill.round())}/mo',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ];
  }

  Widget _officialBill(UscRecord r) {
    final b = r.bill!;
    return Panel(
      border: C.blue.withValues(alpha: .5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          uscPill('OFFICIAL DISCOM BILL', C.blue, solid: true),
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

  /// Ledger: header row, then every month with its bill, paid and balance lines.
  Widget _ledger(List<UscMonth> ledger) {
    final rows = ledger.reversed.toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            Expanded(flex: 5, child: Text('Month (Govt Ledger)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
            Expanded(flex: 3, child: Text('Units (kWh)', textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
            Expanded(flex: 3, child: Text('DISCOM Bill (₹)', textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
          ]),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, i) => _ledgerRow(rows, i),
          ),
        ),
      ]),
    );
  }

  Widget _ledgerRow(List<UscMonth> rows, int i) {
    final m = rows[i];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: m.onPortal ? C.green.withValues(alpha: .06) : Colors.transparent,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            flex: 5,
            child: Row(children: [
              Text('${i + 1}.', style: TextStyle(color: C.mute, fontSize: 12.5)),
              const SizedBox(width: 6),
              Flexible(child: Text(m.month, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              if (m.present) uscPill('Present', C.sky) else if (m.onPortal) uscPill('Govt', C.green),
            ]),
          ),
          Expanded(flex: 3, child: Text(m.onPortal ? '${m.units.round()} kWh' : '0', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            flex: 3,
            child: Text(m.onPortal ? '₹${groupIndian(m.bill.round())}' : '₹0', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: C.green)),
          ),
        ]),
        if (m.onPortal) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Wrap(spacing: 12, children: [
              Text('Bill: ₹${groupIndian(m.bill.round())}', style: TextStyle(color: C.mute, fontSize: 12)),
              Text('Paid: ₹${groupIndian(m.paid.round())}', style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w700)),
              Text('Bal: ₹${groupIndian(m.balance.round())}', style: TextStyle(color: C.mute, fontSize: 12)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _pasteBox() {
    final d = discom;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Copy the month, units and bill rows from the ${d?.code ?? 'DISCOM'} portal and paste them here, one per line. Example: Nov 2025 360 2580',
          style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: pasteCtl,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(hintText: 'Nov 2025 360 2580', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        if (pasteError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(pasteError!, style: TextStyle(color: C.red, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _importPaste, child: const Text('Use pasted bills')),
        ),
      ]),
    );
  }

  void _importPaste() {
    final d = discom;
    final problem = validateUsc(usc.text, discom: d);
    if (d == null || problem != null) {
      setState(() => pasteError = problem ?? 'Choose a state and DISCOM first');
      return;
    }
    final parsed = parsePastedBills(pasteCtl.text);
    if (parsed.months.isEmpty) {
      setState(() => pasteError = 'No rows found. Each line needs a month, year, units and bill, e.g. Nov 2025 360 2580');
      return;
    }
    setState(() {
      pasteError = null;
      error = null;
      notice = parsed.skipped > 0
          ? '${parsed.skipped} line(s) could not be read and were skipped. ${parsed.months.length} months imported.'
          : 'Imported ${parsed.months.length} months from the pasted portal rows.';
      result = UscRecord(
        usc: cleanUscNumber(usc.text),
        discom: d,
        consumerName: '',
        months: parsed.months,
        fetchedAt: DateTime.now(),
      );
    });
  }

  // ---- small helpers ----

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
    return '${two(l.day)} ${_monthShort[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
  }
}

/// "USC History": saved lookups for quick re-runs or audits. Shown at the bottom of the page.
class UscHistory extends StatelessWidget {
  final UscLink link;
  final void Function(UscLoad request) onOpen;
  const UscHistory({super.key, required this.link, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UscRecord>>(
      valueListenable: link.saved,
      builder: (context, saved, _) {
        if (saved.isEmpty) return const SizedBox.shrink();
        return Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 18, backgroundColor: C.chipBlue, child: Icon(Icons.history, color: C.blue, size: 19)),
              const SizedBox(width: 10),
              const Expanded(child: Text('USC History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              uscPill('${saved.length} Saved', C.mute),
            ]),
            const SizedBox(height: 6),
            Text('Previously fetched USC accounts for quick re-runs or audits', style: TextStyle(color: C.mute, fontSize: 12.5, height: 1.35)),
            const SizedBox(height: 12),
            for (final s in saved) _item(context, s, saved),
          ]),
        );
      },
    );
  }

  Widget _item(BuildContext context, UscRecord s, List<UscRecord> saved) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        radius: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('USC #${s.usc}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            uscPill(s.discom.code, C.amber),
            const SizedBox(width: 6),
            uscPill('${s.verifiedMonths}/${s.months.length} Verified', C.green),
            IconButton(
              tooltip: 'Delete',
              onPressed: () async {
                final next = saved.where((x) => !(x.usc == s.usc && x.discom.code == s.discom.code)).toList();
                link.saved.value = next;
                await UscStore.save(next);
              },
              icon: Icon(Icons.delete_outline, color: C.mute),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${s.consumerName.isEmpty ? 'Consumer' : s.consumerName} · Avg ${s.avgUnits.round()} kWh/mo · ₹${groupIndian(s.avgBill.round())}/mo',
              style: TextStyle(color: C.mute, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.orange, foregroundColor: Colors.white),
                onPressed: () => onOpen(UscLoad(s, refetch: true)),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Re-Run Fetch'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(backgroundColor: C.chipBlue, foregroundColor: C.blue),
                onPressed: () => onOpen(UscLoad(s)),
                child: const Text('Load in Audit'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Official portal page for each DISCOM. Null means not confirmed yet, so no link is shown.
String? portalUrlFor(Discom d) => null;
