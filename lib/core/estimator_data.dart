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
String inverterAdvice(SysOption o) {
  final ratio = o.invKw > 0 ? o.kwp / o.invKw : 0;
  final r = ratio.toStringAsFixed(2);
  if (ratio > 1.3) return 'DC/AC ratio $r is high. Panels may clip at noon, so consider a larger inverter.';
  if (ratio < 0.85) return 'DC/AC ratio $r leaves headroom for adding panels later or heavy starting loads.';
  return 'DC/AC ratio $r is in the normal 0.9 to 1.3 range.';
}

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

/// The last 13 months (oldest first), ending with last month.
List<String> last13Months(DateTime now) {
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return [
    for (var k = 13; k >= 1; k--)
      () {
        final d = DateTime(now.year, now.month - k, 1);
        return '${mo[d.month - 1]} ${d.year % 100}';
      }()
  ];
}

/// Units typed in from the customer's bills, kept per USC number.
class UscHistory {
  List<double?> units; // 13 entries, null = not entered
  int at;
  UscHistory({List<double?>? units, this.at = 0}) : units = units ?? List<double?>.filled(13, null);
  List<double> get entered => [for (final u in units) if (u != null && u > 0) u];
  double get average => entered.isEmpty ? 0 : entered.reduce((a, b) => a + b) / entered.length;
  Map<String, dynamic> toJson() => {'u': units, 'at': at};
  factory UscHistory.fromJson(Map<String, dynamic> j) {
    final raw = (j['u'] as List?) ?? const [];
    return UscHistory(
      units: [for (var i = 0; i < 13; i++) i < raw.length && raw[i] is num ? (raw[i] as num).toDouble() : null],
      at: (j['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A USC (service connection) number is 8 to 12 digits depending on the DISCOM.
bool plausibleUsc(String v) => RegExp(r'^\d{8,12}$').hasMatch(v);
