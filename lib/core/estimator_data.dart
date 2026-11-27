import 'appliance_data.dart';

/// A typical module option for the hardware filter. Sizes are typical for the
/// wattage class; efficiency is worked out from the size, so confirm the real
/// datasheet and the ALMM list before quoting.
class PanelModel {
  final String name;
  final int wp;
  final double lengthMm, widthMm;
  final bool dcr;
  const PanelModel(this.name, this.wp, this.lengthMm, this.widthMm, this.dcr);
  double get areaM2 => lengthMm * widthMm / 1e6;
  double get efficiency => wp / areaM2 / 10; // percent
  String get label => '${wp}W';
}

const kPanelModels = <PanelModel>[
  PanelModel('Mono PERC half-cut', 540, 2256, 1133, true),
  PanelModel('Mono PERC half-cut', 550, 2278, 1134, true),
  PanelModel('TOPCon half-cut', 580, 2278, 1134, true),
  PanelModel('TOPCon half-cut', 620, 2382, 1134, true),
  PanelModel('Mono PERC half-cut', 540, 2256, 1133, false),
  PanelModel('Mono PERC half-cut', 550, 2278, 1134, false),
  PanelModel('TOPCon half-cut', 580, 2278, 1134, false),
  PanelModel('TOPCon bifacial', 620, 2382, 1134, false),
  PanelModel('TOPCon bifacial', 650, 2382, 1303, false),
  PanelModel('TOPCon bifacial', 700, 2384, 1303, false),
];

List<PanelModel> panelsFor(bool dcr) => [for (final p in kPanelModels) if (p.dcr == dcr) p];

/// Well-known inverter makes by system type. Shown as starting points only.
const kInverterBrands = <SysType, List<String>>{
  SysType.onGrid: ['Sungrow', 'Growatt', 'GoodWe', 'Solis', 'Polycab', 'Havells'],
  SysType.hybrid: ['Deye', 'Growatt', 'Solis', 'Sungrow', 'Luminous', 'Microtek'],
  SysType.offGrid: ['Luminous', 'Microtek', 'Su-Kam', 'Growatt', 'Victron', 'Voltronic'],
};

/// Plain-language note on the inverter-to-array ratio.
/// Monthly energy split between your own use, export and grid import.
class EnergyFlow {
  final double selfUse, export, import, monthlyValue, annualValue;
  const EnergyFlow(this.selfUse, this.export, this.import, this.monthlyValue, this.annualValue);
}

EnergyFlow energyFlow({required double monthlyGen, required double monthlyUse, required double tariff, double? exportRate}) {
  final self = monthlyGen < monthlyUse ? monthlyGen : monthlyUse;
  final exp = monthlyGen > monthlyUse ? monthlyGen - monthlyUse : 0.0;
  final imp = monthlyUse > monthlyGen ? monthlyUse - monthlyGen : 0.0;
  final value = self * tariff + exp * (exportRate ?? 0);
  return EnergyFlow(self, exp, imp, value, value * 12);
}

class InverterInfo {
  final String name, series;
  final double eff;
  const InverterInfo(this.name, this.series, this.eff);
}

/// Typical peak efficiencies from public datasheets. Shown as starting points only.
List<InverterInfo> inverterBrandInfo(SysType t) => switch (t) {
      SysType.onGrid => const [
          InverterInfo('Sungrow', 'SG RT/RS High-Current String', 98.5),
          InverterInfo('Growatt', 'MIN / MID TL3-X Open Series', 98.4),
          InverterInfo('GoodWe', 'DNS / SDT G3 Wide-MPPT', 98.3),
          InverterInfo('Polycab', 'PSIS On-Grid 16A MPPT', 98.2),
          InverterInfo('Deye', 'SUN-SG04LP3 High-Current', 97.8),
          InverterInfo('Havells', 'Hybrid-BiDir Pro (DISCOM)', 97.6),
          InverterInfo('Solis', 'S6 Pro Bidirectional HV/LV', 97.5),
          InverterInfo('Loom Solar', 'Fusion Bi-Directional MPPT', 97.2),
        ],
      SysType.hybrid => const [
          InverterInfo('Deye', 'SUN-SG Hybrid LV/HV', 97.6),
          InverterInfo('Growatt', 'SPH / SPF Hybrid', 97.6),
          InverterInfo('Solis', 'S6-EH1P Hybrid', 97.5),
          InverterInfo('Sungrow', 'SH-RS Hybrid', 98.4),
          InverterInfo('Luminous', 'NXT+ Solar Hybrid', 96.5),
          InverterInfo('Microtek', 'Hybrid Solar PCU', 96.0),
        ],
      SysType.offGrid => const [
          InverterInfo('Luminous', 'NXG / Solar PCU', 94.0),
          InverterInfo('Microtek', 'Solar PCU Pro', 94.0),
          InverterInfo('Su-Kam', 'Falcon Solar PCU', 93.5),
          InverterInfo('Growatt', 'SPF Off-Grid', 93.0),
          InverterInfo('Victron', 'MultiPlus-II', 96.0),
          InverterInfo('Voltronic', 'Axpert MKS', 93.0),
        ],
    };

/// Common inverter ratings near the array size, 4 closest around it.
List<double> standardInverterSizes(double kwp) {
  const all = [1.0, 1.5, 2.0, 3.0, 3.3, 3.6, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0, 60.0, 80.0, 100.0];
  final target = kwp * .95;
  final sorted = [...all]..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
  return (sorted.take(4).toList())..sort();
}

String dcAcAdvice(double kwp, double invKw) {
  if (invKw <= 0) return '';
  final r = kwp / invKw;
  final t = r.toStringAsFixed(2);
  if (r > 1.3) return 'DC/AC ratio $t is high. The inverter will clip at noon.';
  if (r < .85) return 'DC/AC ratio $t leaves headroom for adding panels later or heavy surge loads.';
  return 'Optimal DC/AC ratio ($t). ${invKw.toStringAsFixed(invKw == invKw.roundToDouble() ? 0 : 1)} kW AC pairs cleanly with ${kwp.toStringAsFixed(2)} kWp of panels for balanced peak harvesting and minimal clipping.';
}
