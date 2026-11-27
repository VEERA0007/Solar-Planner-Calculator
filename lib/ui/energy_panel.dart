import 'package:flutter/material.dart';

import '../core/calc.dart';
import '../core/inverter_energy.dart';
import 'theme.dart';

/// "Today's energy" from the latest inverter reading, or the weather estimate when none is saved.
class EnergyPanel extends StatefulWidget {
  final double capacityKwp;
  final double electricityRate;
  final double latitude;
  final double longitude;
  final double? psh;

  const EnergyPanel({
    super.key,
    required this.capacityKwp,
    required this.electricityRate,
    required this.latitude,
    required this.longitude,
    this.psh,
  });

  @override
  State<EnergyPanel> createState() => _EnergyPanelState();
}

class _EnergyPanelState extends State<EnergyPanel> {
  InverterSnapshot? _snap;
  List<InverterDayLog> _logs = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    InverterStore.version.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    InverterStore.version.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final snap = await InverterStore.loadSnapshot();
    final logs = await InverterStore.loadLogs();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _logs = logs;
      _loaded = true;
    });
  }

  String _kwh(double v) => '${fmt1(v)} kWh';
  String _rs(num v) => '₹${v.round()}';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final e = resolveInverterEnergy(
      snap: _snap,
      logs: _logs,
      capacityKwp: widget.capacityKwp,
      electricityRate: widget.electricityRate,
      latitude: widget.latitude,
      longitude: widget.longitude,
      psh: widget.psh,
    );
    final title = TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800);
    final when = !e.isConnected
        ? 'Weather estimate. Connect an inverter above for real figures.'
        : e.isTodayReading
            ? 'Live reading from today'
            : 'Last reading is from an earlier day (${_snap!.dateKey})';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Today's energy", style: title),
          const SizedBox(height: 4),
          Text('${e.meterModeLabel} · $when', style: TextStyle(color: C.mute, fontSize: 12.5)),
          const SizedBox(height: 12),
          StatGrid([
            StatTile('Generated', _kwh(e.displayGenKwh)),
            StatTile('Power now', '${e.displayLiveKw.toStringAsFixed(2)} kW'),
            StatTile('Self-consumed', _kwh(e.selfConsumedKwh)),
            StatTile('Exported', _kwh(e.exportedKwh)),
            StatTile('Imported', _kwh(e.importedKwh)),
            StatTile('Savings today', _rs(e.totalSavingsInr)),
            StatTile('CO₂ avoided', '${fmt1(e.co2AvoidedKg)} kg'),
            StatTile('Coverage', '${e.solarCoveragePercent}%'),
          ]),
          const SizedBox(height: 10),
          Text(
            e.isSurplus
                ? 'Surplus of ${fmt1(e.netBalanceKwh)} kWh today. Export earns about ${_rs(e.exportEarningsInr)} at ₹${e.exportTariffInr.toStringAsFixed(2)}/kWh.'
                : 'Shortfall of ${fmt1(-e.netBalanceKwh)} kWh today. Grid import covers the rest.',
            style: TextStyle(color: C.mute, fontSize: 12.5),
          ),
          if (e.performanceRatioPct != null)
            Text('Performance vs weather estimate: ${e.performanceRatioPct!.toStringAsFixed(0)}%',
                style: TextStyle(color: C.mute, fontSize: 12.5)),
        ]),
      ),
      if (_logs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Daily log on this phone', style: title),
            const SizedBox(height: 4),
            Text(
              '${_logs.length} day${_logs.length == 1 ? '' : 's'} · ${_kwh(e.cumulativeLoggedGenKwh)} generated in total',
              style: TextStyle(color: C.mute, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            for (final l in _logs.take(14))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: Text(l.dateKey, style: TextStyle(color: C.mute, fontSize: 13))),
                  Text(_kwh(l.generationKwh), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}
