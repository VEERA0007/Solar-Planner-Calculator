import 'package:flutter/material.dart';
import '../core/calc.dart';
import '../core/store.dart';
import 'energy_panel.dart';
import 'inverter_sync_section.dart';
import 'theme.dart';

class SolarPage extends StatelessWidget {
  final AppState state;
  const SolarPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final site = state.site;
    final hk = state.solarHourlyKw();
    final psh = state.irr?.psh ?? 0.0;
    final mp = state.monthly;
    final pr = state.pr;
    final age = state.profile.commissionDate == null ? 0.0 : DateTime.now().difference(state.profile.commissionDate!).inDays / 365.25;
    final health = (1 - 0.005 * age).clamp(0.5, 1.0).toDouble(); // 0.5%/yr degradation
    final daily = hk.fold(0.0, (a, b) => a + b);
    final peakKw = hk.fold(0.0, (a, b) => a > b ? a : b);
    final year = DateTime.now().year;
    final monthly = List.generate(12, (i) => site.kwp * (mp?.psh[i] ?? kMonthPshHyd[i]) * pr * health * DateTime(year, i + 2, 0).day);
    final annual = monthly.fold(0.0, (a, b) => a + b);
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final title = TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        PageHead(state.t('solar'), '${state.site.city} · ${state.profile.panel.isEmpty ? 'Generation forecast for your plant' : state.profile.panel}'),
        const InverterSyncSection(),
        const SizedBox(height: 14),
        EnergyPanel(
          capacityKwp: site.kwp.toDouble(),
          electricityRate: site.tariff.toDouble(),
          latitude: site.lat.toDouble(),
          longitude: site.lon.toDouble(),
          psh: state.irr?.psh,
        ),
        const SizedBox(height: 14),
        StatGrid([
          StatTile('Plant size', '${site.kwp} kWp'),
          StatTile("Today's yield", '${fmt1(daily)} kWh'),
          StatTile('Peak sun hours', psh > 0 ? '${psh.toStringAsFixed(1)} h' : '-'),
          StatTile('Peak output', '${peakKw.toStringAsFixed(2)} kW'),
        ]),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Today by hour (kW)', style: title),
            const SizedBox(height: 10),
            BarChart(series: [BarSeries('kW', hk, const Color(0xFFF59E0B))], labels: List.generate(24, (i) => i % 3 == 0 ? '$i' : null), highlight: DateTime.now().hour),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Typical monthly yield (kWh)', style: title),
            const SizedBox(height: 10),
            BarChart(series: [BarSeries('kWh', monthly, const Color(0xFF38BDF8))], labels: months, highlight: DateTime.now().month - 1),
            const SizedBox(height: 6),
            Text('Long-term average sunshine for ${site.city}${mp != null && mp.fetched ? '' : ' (estimate while offline)'}, performance ratio ${(pr * 100).toStringAsFixed(1)}%${age > 0 ? ', plant age ${age.toStringAsFixed(1)} y' : ''}.', style: TextStyle(color: C.mute, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 14),
        StatGrid([
          StatTile('Annual generation', '${groupIndian(annual)} kWh', hi: true),
          StatTile('Specific yield', '${(annual / (site.kwp < 0.1 ? 0.1 : site.kwp)).round()} kWh/kWp'),
          StatTile('Annual value', '₹${groupIndian(annual * site.tariff)}'),
          StatTile('CO₂ avoided / yr', '${fmt1(annual * kCo2PerKwh / 1000)} t'),
        ]),
      ],
    );
  }
}
