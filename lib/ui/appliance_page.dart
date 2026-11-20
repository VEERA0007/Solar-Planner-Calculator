import 'package:flutter/material.dart';
import '../core/calc.dart';
import '../core/store.dart';
import 'theme.dart';

final List<String?> kHourLabels = List.generate(24, (i) => i % 3 == 0 ? '$i' : null);

class AppliancePage extends StatelessWidget {
  final AppState state;
  const AppliancePage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final lh = state.loadHourly();
    final sh = state.solarHourlyKw();
    final day = lh.fold(0.0, (a, b) => a + b);
    final act = state.activeNow();
    final peak = lh.fold(0.0, (a, b) => a > b ? a : b);
    var solarUsed = 0.0;
    for (var i = 0; i < 24; i++) {
      solarUsed += lh[i] < sh[i] ? lh[i] : sh[i];
    }
    final cover = day > 0 ? (solarUsed / day * 100).round() : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const PageHead('Appliance Analysis', 'Household load profile vs solar generation'),
        StatGrid([
          StatTile('Daily consumption', '${fmt1(day)} kWh'),
          StatTile('Active now', '${act.kw.toStringAsFixed(2)} kW (${act.n})'),
          StatTile('Peak load', '${peak.toStringAsFixed(2)} kW'),
          StatTile('Solar coverage', '$cover% from solar', hi: true),
        ]),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Solar vs load by hour', style: TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            BarChart(
              series: [BarSeries('Solar', sh, const Color(0xFFF59E0B)), BarSeries('Load', lh, const Color(0xFF0A9BFF))],
              labels: kHourLabels,
              highlight: DateTime.now().hour,
            ),
            const SizedBox(height: 6),
            const Row(children: [
              _Sw(Color(0xFFF59E0B)), SizedBox(width: 4), Text('Solar kW', style: TextStyle(color: C.mute, fontSize: 12.5)),
              SizedBox(width: 14),
              _Sw(Color(0xFF0A9BFF)), SizedBox(width: 4), Text('Load kW · hour of day 0–23', style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appliances', style: TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (state.appliances.isEmpty) Text('No appliances. Add one below.', style: TextStyle(color: C.mute)),
            for (final a in state.appliances)
              _ApplianceRow(
                key: ValueKey(a.id),
                a: a,
                onChanged: state.saveAppliances,
                onDelete: () {
                  state.appliances.removeWhere((x) => x.id == a.id);
                  state.saveAppliances();
                },
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  state.appliances.add(Appliance(id: DateTime.now().microsecondsSinceEpoch.toString(), name: 'New appliance', watts: 100, qty: 1, hours: 4, start: 18));
                  state.saveAppliances();
                },
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('+ Add appliance', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Sw extends StatelessWidget {
  final Color c;
  const _Sw(this.c);
  @override
  Widget build(BuildContext context) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));
}

class _ApplianceRow extends StatefulWidget {
  final Appliance a;
  final VoidCallback onChanged, onDelete;
  const _ApplianceRow({super.key, required this.a, required this.onChanged, required this.onDelete});
  @override
  State<_ApplianceRow> createState() => _ApplianceRowState();
}

class _ApplianceRowState extends State<_ApplianceRow> {
  late final TextEditingController name, watts, qty, hours, start;

  String _s(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    final a = widget.a;
    name = TextEditingController(text: a.name);
    watts = TextEditingController(text: _s(a.watts));
    qty = TextEditingController(text: _s(a.qty));
    hours = TextEditingController(text: _s(a.hours));
    start = TextEditingController(text: _s(a.start));
  }

  @override
  void dispose() {
    for (final c in [name, watts, qty, hours, start]) {
      c.dispose();
    }
    super.dispose();
  }

  void _commit() {
    final a = widget.a;
    a.name = name.text;
    a.watts = (double.tryParse(watts.text) ?? 0).clamp(0, 1000000).toDouble();
    a.qty = (int.tryParse(qty.text) ?? 1).clamp(1, 1000).toInt();
    a.hours = (double.tryParse(hours.text) ?? 0).clamp(0, 24).toDouble();
    a.start = (int.tryParse(start.text) ?? 0).clamp(0, 23).toInt();
    widget.onChanged();
  }

  Widget _n(String label, TextEditingController c, {bool decimal = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            onChanged: (_) => _commit(),
            decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Column(children: [
        TextField(controller: name, onChanged: (_) => _commit(), style: const TextStyle(fontWeight: FontWeight.w700), decoration: const InputDecoration(labelText: 'Appliance')),
        const SizedBox(height: 10),
        Row(children: [_n('Watts', watts, decimal: true), _n('Qty', qty), _n('Hours/day', hours, decimal: true), _n('Start hr', start)]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${(a.watts * a.qty * a.hours / 1000).toStringAsFixed(2)} kWh/day', style: TextStyle(color: C.mute, fontSize: 13)),
          TextButton(onPressed: widget.onDelete, child: Text('Remove', style: TextStyle(color: C.red))),
        ]),
      ]),
    );
  }
}
