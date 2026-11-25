import 'package:flutter/material.dart';

import '../core/calc.dart';
import '../core/usc.dart';
import 'theme.dart';

/// USC bill lookup. Pops with a [UscRecord] when the user chooses to use the result in the Estimator.
class UscPage extends StatefulWidget {
  final UscSource source;
  const UscPage({super.key, this.source = const UnconfiguredUscSource()});

  @override
  State<UscPage> createState() => _UscPageState();
}

class _UscPageState extends State<UscPage> {
  final usc = TextEditingController();
  final captcha = TextEditingController();
  UscRegion? region;
  Discom? discom;
  bool busy = false;
  String? error;
  UscRecord? result;
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

  Future<void> _fetch() async {
    final d = discom;
    if (d == null) {
      setState(() => error = 'Choose a state and a DISCOM first');
      return;
    }
    final problem = validateUsc(usc.text);
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
      result = null;
    });
    try {
      final r = await widget.source.fetch(
        usc: normalizeUsc(usc.text),
        discom: d,
        captcha: needsCaptcha ? captcha.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        busy = false;
        result = r;
      });
    } on UscException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Could not reach ${d.code}. Check the connection and try again.';
      });
    }
  }

  Future<void> _saveResult() async {
    final r = result;
    if (r == null) return;
    final next = [r, ...saved.where((s) => !(s.usc == r.usc && s.discom.code == r.discom.code))];
    setState(() => saved = next);
    await UscStore.save(next);
    if (mounted) toast(context, 'Saved USC ${r.usc}');
  }

  Future<void> _deleteSaved(UscRecord r) async {
    final next = saved.where((s) => !(s.usc == r.usc && s.discom.code == r.discom.code)).toList();
    setState(() => saved = next);
    await UscStore.save(next);
  }

  @override
  Widget build(BuildContext context) {
    final r = region;
    final d = discom;
    return Scaffold(
      appBar: AppBar(title: const Text('USC Bill Lookup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const PageHead('USC Bill Lookup', 'Pick the state and DISCOM, enter the USC number, and fetch the last 12 months from the official portal.'),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('State', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final reg in UscRegion.values)
                    ChoiceChip(
                      label: Text(reg.label),
                      selected: r == reg,
                      onSelected: (_) => setState(() {
                        region = reg;
                        discom = null;
                        result = null;
                        error = null;
                      }),
                    ),
                ]),
                const SizedBox(height: 14),
                if (r != null) ...[
                  Text('DISCOM', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final dis in discomsFor(r))
                      ChoiceChip(
                        label: Text(dis.code),
                        selected: d == dis,
                        onSelected: (_) => setState(() {
                          discom = dis;
                          result = null;
                          error = null;
                          captcha.clear();
                        }),
                      ),
                  ]),
                  if (d != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(d.name, style: TextStyle(color: C.mute, fontSize: 12.5))),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: usc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'USC number', hintText: '8 to 12 digits', isDense: true),
                  onChanged: (_) => setState(() => error = null),
                ),
                if (d != null && widget.source.needsCaptcha(d)) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: captcha,
                    decoration: InputDecoration(labelText: 'Captcha from ${d.code}', hintText: 'Type the characters shown on the portal', isDense: true),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : _fetch,
                    icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_outlined),
                    label: Text(busy ? 'Fetching…' : 'Fetch 12-month bills'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: C.red, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ]),
            ),
            if (result != null) ..._resultCards(result!),
            if (saved.isNotEmpty) ..._savedCards(),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultCards(UscRecord r) {
    final missing = r.missingMonths;
    return [
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r.discom.code} · USC ${r.usc}', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 4),
          Text(r.consumerName.isEmpty ? 'Consumer name not on portal' : r.consumerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          if (r.address.isNotEmpty) Text(r.address, style: TextStyle(color: C.mute, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text('Fetched ${_when(r.fetchedAt)}', style: TextStyle(color: C.mute, fontSize: 11.5)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _stat('12-MO AVG UNITS', '${r.avgUnits.round()} kWh', 'Total ${groupIndian(r.totalUnits12)} kWh', C.amber)),
            const SizedBox(width: 10),
            Expanded(child: _stat('12-MO AVG BILL', '₹${groupIndian(r.avgBill.round().toDouble())}', 'Total ₹${groupIndian(r.totalBill12.round().toDouble())}', C.green)),
          ]),
          if (missing > 0) ...[
            const SizedBox(height: 10),
            Text('$missing of 12 months not on the portal. They count as 0 in the average.', style: TextStyle(color: C.amber, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          _monthTable(r),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: _saveResult, child: const Text('Save')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(r),
                child: const Text('Use in Estimator'),
              ),
            ),
          ]),
        ]),
      ),
    ];
  }

  Widget _stat(String label, String value, String sub, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22))),
          Text(sub, style: TextStyle(color: C.mute, fontSize: 11.5)),
        ]),
      );

  Widget _monthTable(UscRecord r) {
    final rows = r.last12.reversed.toList(); // newest first
    return Column(children: [
      Row(children: [
        Expanded(flex: 3, child: Text('Month', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
        Expanded(flex: 2, child: Text('Units', textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
        Expanded(flex: 2, child: Text('Bill ₹', textAlign: TextAlign.right, style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5))),
      ]),
      const Divider(height: 14),
      for (final m in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Row(children: [
                Flexible(child: Text(m.month, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                if (m.present) Padding(padding: const EdgeInsets.only(left: 6), child: Text('Present', style: TextStyle(color: C.sky, fontSize: 11, fontWeight: FontWeight.w800))),
              ]),
            ),
            Expanded(flex: 2, child: Text(m.onPortal ? '${m.units.round()}' : '0', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(m.onPortal ? groupIndian(m.bill.round().toDouble()) : '0', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (!m.onPortal) Text('not on portal', style: TextStyle(color: C.amber, fontSize: 10.5)),
              ]),
            ),
          ]),
        ),
    ]);
  }

  List<Widget> _savedCards() => [
        const SizedBox(height: 16),
        Text('Saved on this device', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        for (final s in saved)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              onTap: () => setState(() {
                result = s;
                error = null;
              }),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s.discom.code} · USC ${s.usc}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${s.consumerName.isEmpty ? 'Consumer' : s.consumerName} · ${s.avgUnits.round()} kWh/mo · ₹${groupIndian(s.avgBill.round().toDouble())}/mo', style: TextStyle(color: C.mute, fontSize: 12)),
                  ]),
                ),
                IconButton(icon: Icon(Icons.delete_outline, color: C.mute), onPressed: () => _deleteSaved(s)),
              ]),
            ),
          ),
      ];

  String _when(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}-${two(l.month)}-${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
