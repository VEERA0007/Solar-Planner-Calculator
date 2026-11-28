import 'dart:math' as math;

/// Calculation engine for the estimator (pure Dart, unit-tested).
class EstimateInput {
  String mode; // 'units' | 'bill'
  double monthlyUnits;
  double monthlyBill;
  double tariff;
  double coverage;
  double yieldPerKwDay;
  double panelWp;
  double areaPerKw;
  double costPerKw;
  String category; // 'residential' | 'commercial'
  bool subsidy;
  double degradation;
  double escalation;
  int years;
  double co2PerKwh;
  double omPct; // yearly maintenance as % of system cost (0 = ignored)
  int? panelsOverride; // panel count decided by the system sizing, null = size here
  bool dcr;
  int sys; // 0 on-grid, 1 hybrid, 2 off-grid
  double backupHours;

  EstimateInput({
    this.mode = 'units',
    this.monthlyUnits = 400,
    this.monthlyBill = 3000,
    this.tariff = 7.5,
    this.coverage = 100,
    this.yieldPerKwDay = 4.0,
    this.panelWp = 540,
    this.areaPerKw = 10,
    this.costPerKw = 60000,
    this.category = 'residential',
    this.subsidy = true,
    this.degradation = 0.5,
    this.escalation = 3,
    this.years = 25,
    this.co2PerKwh = 0.82,
    this.omPct = 0,
    this.panelsOverride,
    this.dcr = true,
    this.sys = 0,
    this.backupHours = 0,
  });

  EstimateInput copy() => EstimateInput.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'monthlyUnits': monthlyUnits,
        'monthlyBill': monthlyBill,
        'tariff': tariff,
        'coverage': coverage,
        'yieldPerKwDay': yieldPerKwDay,
        'panelWp': panelWp,
        'areaPerKw': areaPerKw,
        'costPerKw': costPerKw,
        'category': category,
        'subsidy': subsidy,
        'degradation': degradation,
        'escalation': escalation,
        'years': years,
        'co2PerKwh': co2PerKwh,
        'omPct': omPct,
        'panelsOverride': panelsOverride,
        'dcr': dcr,
        'sys': sys,
        'backupHours': backupHours,
      };

  factory EstimateInput.fromJson(Map<String, dynamic> j) {
    final d = EstimateInput();
    double n(String k, double def) => (j[k] is num) ? (j[k] as num).toDouble() : def;
    return EstimateInput(
      mode: (j['mode'] as String?) ?? d.mode,
      monthlyUnits: n('monthlyUnits', d.monthlyUnits),
      monthlyBill: n('monthlyBill', d.monthlyBill),
      tariff: n('tariff', d.tariff),
      coverage: n('coverage', d.coverage),
      yieldPerKwDay: n('yieldPerKwDay', d.yieldPerKwDay),
      panelWp: n('panelWp', d.panelWp),
      areaPerKw: n('areaPerKw', d.areaPerKw),
      costPerKw: n('costPerKw', d.costPerKw),
      category: (j['category'] as String?) ?? d.category,
      subsidy: (j['subsidy'] as bool?) ?? d.subsidy,
      degradation: n('degradation', d.degradation),
      escalation: n('escalation', d.escalation),
      years: (j['years'] is num) ? (j['years'] as num).toInt() : d.years,
      co2PerKwh: n('co2PerKwh', d.co2PerKwh),
      omPct: n('omPct', d.omPct),
      panelsOverride: (j['panelsOverride'] is num) ? (j['panelsOverride'] as num).toInt() : null,
      dcr: (j['dcr'] as bool?) ?? d.dcr,
      sys: (j['sys'] is num) ? (j['sys'] as num).toInt().clamp(0, 2) : d.sys,
      backupHours: n('backupHours', d.backupHours),
    );
  }
}

class YearRow {
  final int year;
  final double generation;
  final double saving;
  final double cumulative;
  final double net;
  const YearRow(this.year, this.generation, this.saving, this.cumulative, this.net);
}

class EstimateResult {
  final double monthlyUnits, annualUse, neededKw, kw, roofSqm, roofSqft;
  final int panels;
  final double panelWp;
  final double cost, subsidy, netCost;
  final double gen1, monthlyGen, year1Saving, monthlySaving;
  final double? paybackYears;
  final double lifetimeSaving, lifetimeProfit, roi, co2Tonnes;
  final List<YearRow> series;
  final int years;

  const EstimateResult({
    required this.monthlyUnits,
    required this.annualUse,
    required this.neededKw,
    required this.panels,
    required this.panelWp,
    required this.kw,
    required this.roofSqm,
    required this.roofSqft,
    required this.cost,
    required this.subsidy,
    required this.netCost,
    required this.gen1,
    required this.monthlyGen,
    required this.year1Saving,
    required this.monthlySaving,
    required this.paybackYears,
    required this.lifetimeSaving,
    required this.lifetimeProfit,
    required this.roi,
    required this.co2Tonnes,
    required this.series,
    required this.years,
  });
}

/// PM Surya Ghar central subsidy (residential rooftop).
double subsidyFor(double kw) {
  final k = math.max(0.0, kw);
  return 30000 * math.min(k, 2.0) + 18000 * math.max(0.0, math.min(k, 3.0) - 2.0);
}

String normalizeUsc(String v) => v.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
bool isValidUsc(String v) => RegExp(r'^\d{9}$').hasMatch(normalizeUsc(v));

double _fin(double v, double def) => v.isFinite ? v : def;

EstimateResult calculate(EstimateInput i) {
  final tariff = math.max(0.01, _fin(i.tariff, 7.5));
  final monthlyUnits = i.mode == 'bill' ? _fin(i.monthlyBill, 0) / tariff : _fin(i.monthlyUnits, 0);
  final annualUse = math.max(0.0, monthlyUnits) * 12;
  final coverage = math.min(100.0, math.max(0.0, _fin(i.coverage, 100))) / 100;
  final perKwYear = math.max(0.1, _fin(i.yieldPerKwDay, 4)) * 365;
  final panelWp = math.max(50.0, _fin(i.panelWp, 540));

  final neededKw = (annualUse * coverage) / perKwYear;
  final panels = i.panelsOverride != null && i.panelsOverride! > 0
      ? i.panelsOverride!
      : (neededKw > 0 ? math.max(1, ((neededKw * 1000) / panelWp).ceil()) : 0);
  final kw = (panels * panelWp) / 1000;
  final roofSqm = kw * _fin(i.areaPerKw, 10);
  final roofSqft = roofSqm * 10.7639;

  final cost = kw * _fin(i.costPerKw, 60000);
  final subsidy = (i.subsidy && i.category == 'residential') ? subsidyFor(kw) : 0.0;
  final netCost = math.max(0.0, cost - subsidy);

  final gen1 = kw * perKwYear;
  final deg = _fin(i.degradation, 0) / 100;
  final esc = _fin(i.escalation, 0) / 100;
  final years = math.max(1, math.min(40, i.years));

  final series = <YearRow>[];
  double cum = 0;
  double? payback;
  for (var y = 1; y <= years; y++) {
    final gen = gen1 * math.pow(1 - deg, y - 1);
    final t = tariff * math.pow(1 + esc, y - 1);
    final saving = math.min(gen, annualUse) * t - cost * _fin(i.omPct, 0) / 100;
    final prev = cum;
    cum += saving;
    if (payback == null && netCost > 0 && cum >= netCost && saving > 0) {
      payback = y - 1 + (netCost - prev) / saving;
    }
    series.add(YearRow(y, gen, saving, cum, cum - netCost));
  }
  final year1 = series.isEmpty ? 0.0 : series.first.saving;
  return EstimateResult(
    monthlyUnits: monthlyUnits,
    annualUse: annualUse,
    neededKw: neededKw,
    panels: panels,
    panelWp: panelWp,
    kw: kw,
    roofSqm: roofSqm,
    roofSqft: roofSqft,
    cost: cost,
    subsidy: subsidy,
    netCost: netCost,
    gen1: gen1,
    monthlyGen: gen1 / 12,
    year1Saving: year1,
    monthlySaving: year1 / 12,
    paybackYears: payback,
    lifetimeSaving: cum,
    lifetimeProfit: cum - netCost,
    roi: netCost > 0 ? ((cum - netCost) / netCost) * 100 : 0,
    co2Tonnes: (gen1 * _fin(i.co2PerKwh, 0.82)) / 1000,
    series: series,
    years: years,
  );
}

/// Indian digit grouping: 1234567 -> 12,34,567
String groupIndian(num n) {
  final neg = n < 0;
  var s = n.abs().round().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return neg ? '-$s' : s;
}

String inr(num n) => 'Rs. ${groupIndian(n)}';

String fmt1(num n) {
  final v = (n * 10).round() / 10;
  final whole = v.truncate();
  final frac = ((v - whole).abs() * 10).round();
  return frac == 0 ? groupIndian(v) : '${groupIndian(whole)}.$frac';
}

/// Power as W below 1 kW, otherwise kW (2 decimals).
String fmtPowerKw(double kw) => kw.abs() < 1 ? '${groupIndian((kw * 1000).round())} W' : '${kw.toStringAsFixed(2)} kW';

/// Energy as kWh below 1,000 kWh, otherwise MWh (2 decimals).
String fmtEnergyKwh(double kwh) => kwh.abs() < 1000 ? '${kwh.toStringAsFixed(2)} kWh' : '${(kwh / 1000).toStringAsFixed(2)} MWh';
