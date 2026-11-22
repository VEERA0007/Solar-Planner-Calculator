import 'dart:convert';
import 'dart:math' as math;

/// Appliance Analysis engine: load profiles, system sizing, option pricing and
/// the bill of materials. Pure Dart so it can be unit-tested.

enum LoadProfile { residential, commercial, industrial, agricultural }

extension LoadProfileX on LoadProfile {
  String get label => const ['Residential', 'Commercial', 'Industrial', 'Agricultural'][index];
  String get sub => const ['Home Load', 'Business · +12%', 'Plant · +15%', 'Farm / Pump'][index];
  String get loadWord => '$label Load';
  double get factor => const [1.0, 1.12, 1.15, 1.15][index];
}

enum SysType { onGrid, hybrid, offGrid }

extension SysTypeX on SysType {
  String get label => const ['On-Grid', 'Hybrid', 'Off-Grid'][index];
  String get sub => const ['Grid Export', 'Grid + Backup', 'Battery Bank'][index];
  String get status => const ['Grid Net-Metered', 'Grid + Backup', 'Standalone Battery'][index];
  bool get hasBattery => this != SysType.onGrid;
}

/// Working configuration of the Appliance Analysis tab (saved with the app).
class ApplCfg {
  LoadProfile profile;
  SysType sys;
  bool dcr;
  String backupHours; // text so the field can stay empty
  double sanctionedKw; // 0 = not entered
  double roofSqft; // 0 = not entered
  double cutHours; // average power-cut hours per day
  int phase; // 0 auto, 1 single, 2 three
  double shadePct;
  ApplCfg({
    this.profile = LoadProfile.residential,
    this.sys = SysType.onGrid,
    this.dcr = true,
    this.backupHours = '',
    this.sanctionedKw = 0,
    this.roofSqft = 0,
    this.cutHours = 0,
    this.phase = 0,
    this.shadePct = 0,
  });

  double get hours => double.tryParse(backupHours.trim()) ?? 0;

  ApplCfg copy() => ApplCfg.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'profile': profile.index,
        'sys': sys.index,
        'dcr': dcr,
        'backup': backupHours,
        'sanc': sanctionedKw,
        'roof': roofSqft,
        'cut': cutHours,
        'phase': phase,
        'shade': shadePct,
      };
  factory ApplCfg.fromJson(Map<String, dynamic> j) {
    final p = (j['profile'] as num?)?.toInt() ?? 0, s = (j['sys'] as num?)?.toInt() ?? 0;
    return ApplCfg(
      profile: LoadProfile.values[p.clamp(0, 3)],
      sys: SysType.values[s.clamp(0, 2)],
      dcr: (j['dcr'] as bool?) ?? true,
      backupHours: (j['backup'] as String?) ?? '',
      sanctionedKw: (j['sanc'] as num?)?.toDouble() ?? 0,
      roofSqft: (j['roof'] as num?)?.toDouble() ?? 0,
      cutHours: (j['cut'] as num?)?.toDouble() ?? 0,
      phase: ((j['phase'] as num?)?.toInt() ?? 0).clamp(0, 2),
      shadePct: (j['shade'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Price list used for every quote. Editable in the app so quotes follow the
/// company's real rates.
class Rates {
  final double dcr, nonDcr, hybridExtra, offExtra, battery;
  final int updated; // epoch ms
  const Rates({this.dcr = 54000, this.nonDcr = 46000, this.hybridExtra = 9015, this.offExtra = 5769, this.battery = 24000, this.updated = 0});
  Map<String, dynamic> toJson() => {'dcr': dcr, 'non': nonDcr, 'hy': hybridExtra, 'off': offExtra, 'bat': battery, 'at': updated};
  factory Rates.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return Rates(dcr: d('dcr', 54000), nonDcr: d('non', 46000), hybridExtra: d('hy', 9015), offExtra: d('off', 5769), battery: d('bat', 24000), updated: (j['at'] as num?)?.toInt() ?? 0);
  }
}

/// A ready-made appliance. [variants] are size/rating choices that change the
/// wattage; [hours] is the typical daily use and [start] the usual start hour.
class Preset {
  final String name, cat;
  final double watts, hours;
  final int start;
  final List<(String, double)> variants;
  const Preset(this.name, this.cat, this.watts, this.hours, {this.start = 18, this.variants = const []});
}

const List<String> kPresetCats = [
  'All', 'Lighting', 'Cooling', 'Kitchen', 'Heating', 'Laundry', 'Entertainment', 'Office & IT',
  'Water & Pumps', 'Latest & EV', 'Commercial', 'Industrial',
];

const List<Preset> kPresets = [
  // ---- lighting
  Preset('LED Bulb (9W)', 'Lighting', 9, 6, variants: [('5W', 5), ('9W', 9), ('12W', 12), ('15W', 15)]),
  Preset('LED Tube Light (20W)', 'Lighting', 20, 6),
  Preset('LED Panel Light (18W)', 'Lighting', 18, 8, start: 9),
  Preset('Decorative / Strip Lights', 'Lighting', 12, 4),
  Preset('Outdoor Flood Light (30W)', 'Lighting', 30, 10, start: 18),
  Preset('Solar-ready Street Light (40W)', 'Lighting', 40, 11, start: 18),
  // ---- cooling
  Preset('BLDC Ceiling Fan', 'Cooling', 32, 12, variants: [('BLDC 28W', 28), ('BLDC 32W', 32), ('Regular 75W', 75)]),
  Preset('Table / Pedestal Fan', 'Cooling', 50, 6),
  Preset('Exhaust Fan', 'Cooling', 40, 3, start: 7),
  Preset('Air Cooler', 'Cooling', 200, 8, start: 12, variants: [('Personal 100W', 100), ('Room 200W', 200), ('Desert 300W', 300)]),
  Preset('1.5 Ton 5-Star Inverter AC', 'Cooling', 1150, 8, start: 22, variants: [('1 Ton', 800), ('1.5 Ton', 1150), ('2 Ton', 1700), ('2 Ton non-inverter', 2200)]),
  Preset('Window AC 1.5 Ton', 'Cooling', 1650, 8, start: 22),
  Preset('Ducted / Cassette AC 3 Ton', 'Cooling', 3000, 9, start: 9),
  Preset('Dehumidifier', 'Cooling', 300, 4),
  // ---- kitchen
  Preset('Double Door Refrigerator', 'Kitchen', 110, 24, start: 0, variants: [('Single door 90W', 90), ('Double door 110W', 110), ('Side-by-side 190W', 190)]),
  Preset('Frost-Free Refrigerator', 'Kitchen', 120, 24, start: 0),
  Preset('Deep Freezer', 'Kitchen', 150, 24, start: 0),
  Preset('Mixer Grinder', 'Kitchen', 500, 0.5, start: 7),
  Preset('Wet Grinder', 'Kitchen', 250, 0.5, start: 7),
  Preset('RO Water Purifier', 'Kitchen', 40, 3, start: 6),
  Preset('Kitchen Chimney', 'Kitchen', 180, 1.5, start: 7),
  Preset('Dishwasher', 'Kitchen', 1800, 1, start: 21),
  Preset('Air Fryer', 'Kitchen', 1500, 0.5, start: 19),
  Preset('Rice Cooker', 'Kitchen', 700, 0.7, start: 7),
  Preset('Microwave Oven', 'Kitchen', 1200, 0.4, start: 8),
  Preset('Induction Cooktop', 'Kitchen', 1800, 1.5, start: 7, variants: [('1200W', 1200), ('1800W', 1800), ('2100W', 2100)]),
  Preset('Electric Kettle', 'Kitchen', 1500, 0.3, start: 7),
  Preset('Toaster', 'Kitchen', 800, 0.2, start: 7),
  // ---- heating
  Preset('Water Geyser (15L)', 'Heating', 2000, 1.2, start: 6, variants: [('6L', 1500), ('15L', 2000), ('25L', 2000), ('Instant 3000W', 3000)]),
  Preset('Heat-pump Water Heater', 'Heating', 1000, 3, start: 6),
  Preset('Room Heater', 'Heating', 1500, 3, start: 5),
  Preset('Iron Box', 'Heating', 1000, 0.5, start: 7),
  // ---- laundry
  Preset('Washing Machine (Top-load)', 'Laundry', 500, 1, start: 9),
  Preset('Washing Machine (Front-load)', 'Laundry', 1000, 1, start: 9),
  Preset('Clothes Dryer', 'Laundry', 2500, 1, start: 11),
  // ---- entertainment
  Preset('Smart TV (50")', 'Entertainment', 95, 4, start: 19, variants: [('32"', 55), ('43"', 75), ('50"', 95), ('65"', 140), ('75"', 200)]),
  Preset('Set-top Box', 'Entertainment', 15, 6, start: 17),
  Preset('Sound Bar / Home Theatre', 'Entertainment', 80, 2, start: 20),
  Preset('Gaming Console', 'Entertainment', 150, 2, start: 20),
  // ---- office & IT
  Preset('Laptop', 'Office & IT', 65, 8, start: 9),
  Preset('Desktop PC + Monitor', 'Office & IT', 230, 8, start: 9),
  Preset('Wi-Fi Router', 'Office & IT', 12, 24, start: 0),
  Preset('Printer / Copier', 'Office & IT', 400, 1, start: 10),
  Preset('CCTV Set (8 cameras + NVR)', 'Office & IT', 70, 24, start: 0),
  Preset('Inverter / UPS Charging', 'Office & IT', 150, 8, start: 0),
  // ---- water & pumps
  Preset('Water Pump 0.5 HP', 'Water & Pumps', 375, 1, start: 7),
  Preset('Water Pump 1 HP', 'Water & Pumps', 750, 1, start: 7),
  Preset('Water Pump 2 HP', 'Water & Pumps', 1500, 2, start: 7),
  Preset('Borewell Pump 5 HP', 'Water & Pumps', 3750, 4, start: 9),
  Preset('Submersible Pump 7.5 HP', 'Water & Pumps', 5600, 4, start: 9),
  Preset('Irrigation Pump 10 HP', 'Water & Pumps', 7500, 5, start: 8),
  Preset('Drip Irrigation Controller', 'Water & Pumps', 120, 6, start: 6),
  // ---- latest & EV
  Preset('EV Car Home Charger', 'Latest & EV', 3300, 3, start: 21, variants: [('3.3 kW AC', 3300), ('7.4 kW AC', 7400)]),
  Preset('Scooter Charger', 'Latest & EV', 800, 3, start: 22),
  Preset('E-Bike Charger', 'Latest & EV', 250, 4, start: 22),
  Preset('Smart AC (Wi-Fi Inverter)', 'Latest & EV', 1000, 8, start: 22),
  Preset('Air Purifier (HEPA)', 'Latest & EV', 55, 10, start: 20),
  Preset('Robot Vacuum Cleaner', 'Latest & EV', 45, 1, start: 11),
  Preset('Smart Home Hub + Sensors', 'Latest & EV', 15, 24, start: 0),
  Preset('Satellite Internet Terminal', 'Latest & EV', 75, 24, start: 0),
  Preset('Home Battery Charger (LFP)', 'Latest & EV', 600, 4, start: 10),
  // ---- commercial
  Preset('Display Refrigerator (Shop)', 'Commercial', 300, 24, start: 0),
  Preset('Billing Counter PC + POS', 'Commercial', 150, 10, start: 9),
  Preset('Shop Lighting (LED set)', 'Commercial', 400, 10, start: 9),
  Preset('Commercial Ice-cream Freezer', 'Commercial', 350, 24, start: 0),
  Preset('Elevator (Passenger)', 'Commercial', 5500, 3, start: 8),
  Preset('Server Rack + Cooling', 'Commercial', 2500, 24, start: 0),
  // ---- industrial
  Preset('Air Compressor 5 HP', 'Industrial', 3750, 6, start: 9),
  Preset('Lathe / Drill Machine', 'Industrial', 3000, 8, start: 9),
  Preset('CNC Machine', 'Industrial', 7500, 8, start: 9),
  Preset('Welding Machine', 'Industrial', 5000, 4, start: 9),
  Preset('Industrial Motor 15 HP', 'Industrial', 11000, 8, start: 8),
  Preset('Chiller / Cold Room', 'Industrial', 6000, 20, start: 0),
  Preset('Thresher / Grain Cleaner', 'Industrial', 3700, 4, start: 9),
];

/// Matches a saved appliance back to its preset (for rating suggestions).
Preset? presetFor(String name) {
  for (final p in kPresets) {
    if (p.name.toLowerCase() == name.trim().toLowerCase()) return p;
  }
  return null;
}

double ampsFor(double watts, int qty) => watts * qty / (230 * 0.9);

/// Loads with a large starting (surge) current.
bool isMotorLoad(String name) {
  final n = name.toLowerCase();
  const keys = ['ac', 'pump', 'refrigerator', 'freezer', 'compressor', 'motor', 'washing', 'cooler', 'mixer', 'grinder', 'lathe', 'cnc', 'chiller', 'thresher', 'elevator', 'chimney'];
  for (final k in keys) {
    if (k == 'ac') {
      if (RegExp(r'\bac\b').hasMatch(n) || n.contains(' ton')) return true;
    } else if (n.contains(k)) {
      return true;
    }
  }
  return false;
}

/// One appliance as the engine sees it (no dependency on the app state).
class LoadItem {
  final String name;
  final double watts, hours;
  final int qty, start;
  final bool backup;
  const LoadItem(this.name, this.watts, this.qty, this.hours, this.start, {this.backup = false});
  double get kw => watts * qty / 1000;
  double get kwhDay => kw * hours;
}

/// Everything derived from the appliance list.
class LoadStats {
  final double connectedKw, criticalKw, surgeKw, dayKwh, nightKwh, peakKw, dailyKwh;
  final int peakHour;
  final List<double> hourly; // kW per hour of day, profile factor applied
  const LoadStats(this.connectedKw, this.criticalKw, this.surgeKw, this.dayKwh, this.nightKwh, this.peakKw, this.peakHour, this.dailyKwh, this.hourly);
  double get dayShare => (dayKwh + nightKwh) > 0 ? dayKwh / (dayKwh + nightKwh) : 0;
}

LoadStats analyzeLoad(List<LoadItem> items, double factor) {
  final hourly = List<double>.filled(24, 0);
  var connected = 0.0, critical = 0.0, maxMotor = 0.0;
  for (final a in items) {
    connected += a.kw;
    if (a.backup) critical += a.kw;
    if (isMotorLoad(a.name)) maxMotor = math.max(maxMotor, a.kw);
    var left = a.hours.clamp(0, 24).toDouble();
    var i = 0;
    while (left > 0 && i < 24) {
      hourly[(a.start + i) % 24] += a.kw * math.min(1.0, left) * factor;
      left -= 1;
      i++;
    }
  }
  var day = 0.0, night = 0.0, peak = 0.0, peakH = 0;
  for (var h = 0; h < 24; h++) {
    if (h >= 6 && h < 18) {
      day += hourly[h];
    } else {
      night += hourly[h];
    }
    if (hourly[h] > peak) {
      peak = hourly[h];
      peakH = h;
    }
  }
  final surge = connected + 2 * maxMotor; // largest motor starts at ~3x its rating
  return LoadStats(connected, critical, surge, day, night, peak, peakH, day + night, hourly);
}

/// Hourly solar generation (kW) for an array: a half-sine between 06:00 and 18:00
/// scaled so the day total equals [kwh].
List<double> solarCurve(double kwh) {
  final raw = [for (var h = 0; h < 24; h++) (h + .5 >= 6 && h + .5 <= 18) ? math.sin(math.pi * (h + .5 - 6) / 12) : 0.0];
  final sum = raw.fold(0.0, (a, b) => a + b);
  return [for (final v in raw) sum > 0 ? v / sum * kwh : 0.0];
}

/// One of the three system options shown to the customer.
class SysOption {
  final SysType type;
  final int panels;
  final double kwp, invKw, batteryKwh, gross, subsidy, savePerMonth, payback, footprintM2, genYear;
  final bool threePhase;
  final String invLabel;
  const SysOption({
    required this.type,
    required this.panels,
    required this.kwp,
    required this.invKw,
    required this.batteryKwh,
    required this.gross,
    required this.subsidy,
    required this.savePerMonth,
    required this.payback,
    required this.footprintM2,
    required this.threePhase,
    required this.invLabel,
    this.genYear = 0,
  });
  double get net => gross - subsidy;
}

double _round(double v, double step) => (v / step).round() * step;

/// PM Surya Ghar style central subsidy: Rs 30,000/kW up to 2 kW, Rs 18,000 for the
/// third kW, capped at Rs 78,000. Residential, grid-connected, DCR modules only.
double centralSubsidy(double kwp) => kwp >= 3 ? 78000 : (kwp > 2 ? 60000 + 18000 * (kwp - 2) : 30000 * kwp);

SysOption buildOption({
  required SysType type,
  required double dailyKwh,
  required double connectedKw,
  required double yieldPerKwp,
  required double tariff,
  required bool dcr,
  required LoadProfile profile,
  required double backupHours,
  double panelWp = 550,
  double criticalKw = 0,
  double surgeKw = 0,
  int phase = 0,
  Rates rates = const Rates(),
}) {
  final y = yieldPerKwp > 0.5 ? yieldPerKwp : 3.5;
  final f = const [1.0, 1.05, 1.15][type.index];
  final raw = dailyKwh / y * f;
  final panels = math.max(1, (raw * 1000 / panelWp).ceil());
  final kwp = panels * panelWp / 1000;
  var inv = switch (type) {
    SysType.onGrid => _round(kwp * 0.9, 0.5),
    SysType.hybrid => _round(kwp * 1.04, 0.5),
    SysType.offGrid => math.max(_round(kwp * 1.03, 0.5), _round(connectedKw * 1.5, 0.5)),
  };
  if (type.hasBattery && surgeKw > 0) inv = math.max(inv, _round(surgeKw / 2, 0.5)); // motor starting current
  inv = math.max(1, inv);
  final backupKw = criticalKw > 0 ? criticalKw : math.min(inv, math.max(connectedKw, 0.5)) * 0.6;
  final battery = type.hasBattery && backupHours > 0 ? _round(backupHours * backupKw / 0.9, 0.1) : 0.0;
  var gross = kwp * (dcr ? rates.dcr : rates.nonDcr);
  if (type == SysType.hybrid) gross += kwp * rates.hybridExtra;
  if (type == SysType.offGrid) gross += kwp * rates.offExtra;
  gross += battery * rates.battery;
  gross = _round(gross, 50);
  final eligible = type != SysType.offGrid && dcr && profile == LoadProfile.residential;
  final monthly = dailyKwh * 30;
  final gen = kwp * y * 30;
  final loss = const [0.98, 0.999, 1.0][type.index];
  final save = math.min(gen, monthly) * tariff * loss;
  final sub = eligible ? centralSubsidy(kwp) : 0.0;
  final net = gross - sub;
  final threePhase = phase == 2 || (phase == 0 && (inv > 5 || connectedKw > 5));
  String fmtKw(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return SysOption(
    type: type,
    panels: panels,
    kwp: kwp,
    invKw: inv,
    batteryKwh: battery,
    gross: gross,
    subsidy: sub,
    savePerMonth: save,
    payback: save > 0 ? net / (save * 12) : 0,
    footprintM2: panels * 2.278 * 1.134,
    threePhase: threePhase,
    genYear: gen * 12,
    invLabel: switch (type) {
      SysType.onGrid => '${fmtKw(inv)} kW Grid-Tie',
      SysType.hybrid => '${fmtKw(inv)} kW Hybrid',
      SysType.offGrid => '${fmtKw(inv)} kW PCU',
    },
  );
}

/// Complete analysis for one appliance list + configuration.
class Analysis {
  final LoadStats stats;
  final double monthly, daily, yieldEff;
  final Map<SysType, SysOption> options;
  final ApplCfg cfg;
  final Rates rates;
  const Analysis(this.stats, this.monthly, this.daily, this.yieldEff, this.options, this.cfg, this.rates);
  SysOption get selected => options[cfg.sys]!;
  SysOption of(SysType t) => options[t]!;
}

Analysis analyze({
  required List<LoadItem> items,
  required ApplCfg cfg,
  required Rates rates,
  required double yieldPerKwp,
  required double tariff,
}) {
  final st = analyzeLoad(items, cfg.profile.factor);
  final base = items.fold(0.0, (a, e) => a + e.kwhDay);
  final daily = base * cfg.profile.factor;
  final y = (yieldPerKwp > 0.5 ? yieldPerKwp : 3.5) * (1 - cfg.shadePct.clamp(0, 60) / 100);
  final opts = {
    for (final t in SysType.values)
      t: buildOption(
        type: t,
        dailyKwh: daily,
        connectedKw: st.connectedKw,
        yieldPerKwp: y,
        tariff: tariff,
        dcr: cfg.dcr,
        profile: cfg.profile,
        backupHours: cfg.hours,
        criticalKw: st.criticalKw,
        surgeKw: st.surgeKw,
        phase: cfg.phase,
        rates: rates,
      ),
  };
  return Analysis(st, daily * 30, daily, y, opts, cfg, rates);
}

/// Which system fits the customer best (the "Best Match" tag).
SysType recommend(LoadProfile profile, double dailyKwh, {double cutHours = 0}) {
  switch (profile) {
    case LoadProfile.agricultural:
      return SysType.offGrid;
    case LoadProfile.industrial:
    case LoadProfile.commercial:
      return SysType.onGrid;
    case LoadProfile.residential:
      return (dailyKwh >= 10 || cutHours >= 2) ? SysType.hybrid : SysType.onGrid;
  }
}

String recommendText(SysOption o, LoadProfile p, double dailyKwh, double connectedKw, {double cutHours = 0}) {
  final kw = connectedKw.toStringAsFixed(2);
  String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return switch (o.type) {
    SysType.onGrid => '${p.label} daytime load ($kw kW peak) matches solar generation: On-Grid net metering gives the lowest Capex and fastest payback.',
    SysType.hybrid => cutHours >= 2 && dailyKwh < 10
        ? '${n(cutHours)} h/day of power cuts: a ${n(o.invKw)} kW Hybrid Inverter with ${n(o.batteryKwh)} kWh backup keeps essentials running.'
        : 'High ${dailyKwh.toStringAsFixed(1)} kWh/day demand ($kw kW peak) pairs best with a ${n(o.invKw)} kW Hybrid Inverter & ${n(o.batteryKwh)} kWh backup.',
    SysType.offGrid => 'Heavy ${p.label.toLowerCase()} load ($kw kW) suits Off-Grid PCU + ${n(o.batteryKwh)} kWh storage for daytime/rural autonomy.',
  };
}

String subsidyNote(LoadProfile p, bool dcr, SysType t) {
  switch (p) {
    case LoadProfile.residential:
      if (t == SysType.offGrid) return 'Off-grid systems are outside PM Surya Ghar, so no central subsidy is applied.';
      if (!dcr) return 'Non-DCR modules are not eligible for the central subsidy. Switch to DCR to claim up to ₹78,000.';
      return 'PM Surya Ghar central subsidy applied: ₹30,000/kW up to 2 kW, ₹18,000 for the 3rd kW, maximum ₹78,000. A state top-up may also apply.';
    case LoadProfile.commercial:
    case LoadProfile.industrial:
      return 'No central capital subsidy for commercial / industrial rooftops. Depreciation and tax benefits may apply, so confirm with the customer\'s CA.';
    case LoadProfile.agricultural:
      return 'Farm pumps may qualify under PM-KUSUM. Check eligibility with the DISCOM or state agency, as no subsidy is applied here.';
  }
}

/// Site limits that make a system impractical.
List<String> limitWarnings(SysOption o, ApplCfg c) {
  final w = <String>[];
  String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  if (c.sanctionedKw > 0 && o.kwp > c.sanctionedKw + 0.001 && o.type != SysType.offGrid) {
    w.add('${o.kwp.toStringAsFixed(2)} kWp is above the sanctioned load of ${n(c.sanctionedKw)} kW. Apply for a load extension or limit the plant to ${n(c.sanctionedKw)} kWp.');
  }
  if (c.roofSqft > 0) {
    final fit = (c.roofSqft / 50).floor(); // ~50 sq ft per 550 W panel with row spacing
    if (o.panels > fit) w.add('Roof area of ${n(c.roofSqft)} sq ft fits about $fit panels (${(fit * .55).toStringAsFixed(2)} kWp). This option needs ${o.panels} panels.');
  }
  if (c.phase == 1 && o.invKw > 5) w.add('Single-phase supply usually supports up to 5 kW. A ${n(o.invKw)} kW inverter needs a three-phase connection.');
  return w;
}

/// Money story for one option.
class Econ {
  final double billBefore, billAfter, saveYear, save25, co2Year;
  const Econ(this.billBefore, this.billAfter, this.saveYear, this.save25, this.co2Year);
}

Econ economics(SysOption o, double monthlyKwh) {
  final saveYear = o.savePerMonth * 12;
  var total = 0.0;
  for (var y = 0; y < 25; y++) {
    total += saveYear * math.pow(1.03, y) * math.pow(0.995, y);
  }
  final tariff = monthlyKwh > 0 ? o.savePerMonth / math.max(1, math.min(o.genYear / 12, monthlyKwh)) : 0.0;
  final before = monthlyKwh * 12 * tariff;
  return Econ(before, math.max(0, before - saveYear), saveYear, total, o.genYear * 0.71);
}

/// A weighed suggestion that lowers the load (and so the system size).
class EffTip {
  final String text;
  final double kwhMonth;
  const EffTip(this.text, this.kwhMonth);
}

List<EffTip> efficiencyTips(List<LoadItem> items, double factor) {
  final tips = <EffTip>[];
  for (final a in items) {
    final n = a.name.toLowerCase();
    final mo = a.kwhDay * 30 * factor;
    if (n.contains('fan') && !n.contains('bldc') && !n.contains('exhaust') && a.watts >= 55) {
      tips.add(EffTip('Swap ${a.qty} × ${a.name} for BLDC fans (32 W)', mo * (1 - 32 / a.watts)));
    } else if ((n.contains('window ac') || n.contains('non-inverter')) && a.watts >= 1400) {
      tips.add(EffTip('Replace ${a.name} with a 5-star inverter AC', mo * .35));
    } else if (n.contains('geyser') && a.watts >= 1800) {
      tips.add(EffTip('Heat-pump or solar water heater instead of ${a.name}', mo * .6));
    } else if (n.contains('tube') && a.watts > 20) {
      tips.add(EffTip('Use LED tubes for ${a.name}', mo * .4));
    }
  }
  tips.sort((a, b) => b.kwhMonth.compareTo(a.kwhMonth));
  return tips.where((t) => t.kwhMonth >= 3).take(4).toList();
}

class BomItem {
  final String title, spec, why, group, qty;
  final int tab; // 0 PV/inverter/battery, 1 BOS & structure, 2 metering & compliance
  double price;
  BomItem(this.title, this.spec, this.why, this.group, this.qty, this.tab, {this.price = 0});
}

class Bom {
  final List<BomItem> items;
  final List<String> removed;
  const Bom(this.items, this.removed);
  double get total => items.fold(0.0, (a, e) => a + e.price);
}

Bom buildBom(SysOption o, {required bool dcr, required LoadProfile profile, Rates rates = const Rates()}) {
  final t = o.type;
  final phase = o.threePhase ? '3-Phase 415V' : '1-Phase 230V';
  final agri = profile == LoadProfile.agricultural || profile == LoadProfile.industrial;
  final items = <BomItem>[];
  final removed = <String>[];
  final w = <BomItem, double>{}; // price weight of each non-battery line
  final batt = <BomItem, double>{}; // share of the battery cost
  String kw(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  BomItem add(BomItem i, {double weight = 0, double battery = 0}) {
    items.add(i);
    if (weight > 0) w[i] = weight;
    if (battery > 0) batt[i] = battery;
    return i;
  }

  add(
      BomItem(
        dcr ? '550W DCR Solar Modules (Tata Power Solar)' : '550W Non-DCR Tier-1 Modules (Tata Power Solar)',
        dcr ? 'Mono PERC M10 Half-Cut · ALMM Made-in-India Cells · 2278 × 1134 mm' : 'Mono PERC M10 Half-Cut · Open Supply · 2278 × 1134 mm',
        dcr
            ? (t == SysType.offGrid ? 'Filtered DCR ALMM domestic modules selected (Note: Off-Grid excludes grid DBT subsidy).' : 'Filtered DCR domestic modules required for PM Surya Ghar Govt DBT subsidy.')
            : 'Filtered Non-DCR Tier-1 modules selected for lower upfront cost.',
        'PV MODULES',
        '${o.panels} Nos (${o.kwp.toStringAsFixed(2)} kWp)',
        0,
      ),
      weight: dcr ? .52 : .46);
  add(
      BomItem(
        switch (t) {
          SysType.onGrid => '${kw(o.invKw)} kW Grid-Tied String MPPT Inverter',
          SysType.hybrid => '${kw(o.invKw)} kW Bidirectional Hybrid MPPT (<10ms UPS)',
          SysType.offGrid => '${kw(o.invKw)} kW Off-Grid Pure Sine MPPT PCU',
        },
        switch (t) {
          SysType.onGrid => '$phase · Dual MPPT (≥16A) · IEEE 1547 Anti-Islanding',
          SysType.hybrid => '$phase · <10ms UPS Switchover · Grid + BMS Battery Port',
          SysType.offGrid => '$phase · Integrated MPPT Charger · High Inductive Surge Capacity',
        },
        switch (t) {
          SysType.onGrid => 'Filtered DCR/BIS-listed grid-tie inverter with zero battery conversion hardware.',
          SysType.hybrid => 'Filtered DCR-compatible hybrid inverter managing PV, LiFePO₄ BMS & critical loads.',
          SysType.offGrid => 'Filtered DCR/MNRE off-grid PCU sized for ${(o.invKw / 2.4).toStringAsFixed(2)} kW ${agri ? 'farm / industrial' : profile.label.toLowerCase()} surge load.',
        },
        'INVERTER / PCU',
        '1 Unit',
        0,
      ),
      weight: const [.16, .19, .18][t.index]);
  if (t.hasBattery) {
    final pending = o.batteryKwh <= 0;
    add(
        BomItem(
          'LiFePO₄ Backup Battery Bank (Auto-Added)',
          pending ? 'Enter battery backup hours to size the bank' : '${o.batteryKwh.toStringAsFixed(1)} kWh LiFePO₄ · 90% DoD · 6000+ cycles',
          'Sized from the backup appliances, backup hours and 90% depth of discharge.',
          'BATTERY BANK',
          pending ? 'Pending user input' : '${o.batteryKwh.toStringAsFixed(1)} kWh',
          0,
        ),
        battery: .85);
    add(BomItem('Battery BMS Harness & DC Breaker (MCCB)', 'Pre-wired harness · 2-pole DC MCCB · communication cable', 'Protects the battery bank and links it to the inverter.', 'BATTERY BANK', '1 Set', 0), battery: .09);
    add(BomItem('Battery Mounting Rack', 'Powder-coated floor rack · seismic clamps', 'Safe, ventilated mounting for the battery pack.', 'STRUCTURE & CABLING', '1 Rack', 1), battery: .06);
  } else {
    removed.addAll(['Battery Storage Bank (0 kWh)', 'Battery BMS Harness & DC Breaker (MCCB)', 'Battery Mounting Rack']);
  }
  add(
      BomItem(
        '${agri ? 'Heavy-Duty Ground / Elevated' : 'Roof / Elevated'} HDG Structure',
        'Wind-rated 150 km/h · Corrosion-resistant Clamps · ${o.footprintM2.toStringAsFixed(1)} m² Array Footprint',
        'Tailored to the site wind-load and ${o.footprintM2.toStringAsFixed(1)} m² array geometry.',
        'STRUCTURE & CABLING',
        '1 Set (${o.panels}-Panel Bay)',
        1,
      ),
      weight: .11);
  add(
      BomItem(
        t == SysType.offGrid ? 'DCDB + Off-Grid ACDB ($phase)' : 'DCDB + Grid-Tie ACDB ($phase)',
        '1000V DC SPD Type-II + DC Fuse + ${o.threePhase ? '4-Pole' : '2-Pole'} AC MCB/MCCB + AC SPD',
        'Protects ${o.threePhase ? '3-Phase 415V' : 'single-phase'} feeders against surges & faults.',
        'BOS & PROTECTION',
        '1 Combined Kit',
        1,
      ),
      weight: .05);
  add(
      BomItem(
        'Solar DC & Armoured AC Cabling + MC4',
        '4/6 sq.mm TUV EN50618 UV DC Cable + ${o.threePhase ? '4-Core' : '2-Core'} 10 sq.mm Armoured + IP68 MC4',
        'Minimizes I²R voltage drop between array, inverter/PCU, and distribution board.',
        'STRUCTURE & CABLING',
        '${(o.kwp * 6.4).round()}m DC + ${(o.kwp * 4).round()}m AC',
        1,
      ),
      weight: .07);
  if (t == SysType.offGrid) {
    removed.add('Bi-Directional DISCOM Net Meter');
    add(BomItem('Standalone DC/AC Energy Shunt Monitor', 'Real-Time State-of-Charge & Load kWh Logger (No DISCOM Net Meter)', 'Tracks off-grid generation and battery bank state without utility net metering.', 'METERING & COMPLIANCE', '1 Unit', 2), weight: .03);
  } else {
    add(BomItem('Bi-Directional Net Meter + Solar Gen Meter', '$phase DISCOM-Approved Smart Meter Set', 'Mandatory for DISCOM net-metering billing credits & grid synchronization.', 'METERING & COMPLIANCE', '1 Meter Pair', 2), weight: .03);
  }
  add(
      BomItem(
        'Chemical Copper Earthing + Lightning Arrester',
        '${o.kwp >= 5 ? 3 : 2} × Maintenance-Free Earth Pits + GI Strip + ESE/Spike LA',
        'Dedicated DC, AC & LA grounding${o.kwp >= 5 ? ' for ≥5 kW' : ''}${agri ? ' / farm and plant safety' : ''}.',
        'BOS & PROTECTION',
        '${o.kwp >= 5 ? 3 : 2} Sets',
        1,
      ),
      weight: .03);
  add(
      BomItem(
        dcr ? 'DCR / ALMM & Subsidy Compliance Dossier' : 'Quality & Warranty Dossier',
        dcr
            ? (t == SysType.offGrid ? 'MNRE ALMM Certificate + Domestic Cell Origin Invoice + Safety Test Sheet' : 'DCR Undertaking, ALMM Serial Barcode List, DISCOM Feasibility & DBT File')
            : 'Module datasheets · IEC/BIS test reports · Invoice & warranty cards',
        dcr ? 'Required proof that solar cells & modules are domestically manufactured (DCR).' : 'Warranty documents for the customer (no subsidy file required).',
        'METERING & COMPLIANCE',
        '1 Complete Pack',
        2,
      ),
      weight: .03);

  // Indicative split of the system price so the lines add up to the total.
  final batteryCost = o.batteryKwh * rates.battery;
  final pool = math.max(0.0, o.gross - batteryCost);
  final wsum = w.values.fold(0.0, (a, b) => a + b);
  var used = 0.0;
  for (final i in items) {
    if (w.containsKey(i)) {
      i.price = _round(pool * w[i]! / wsum, 50);
    } else if (batt.containsKey(i)) {
      i.price = _round(batteryCost * batt[i]!, 50);
    }
    used += i.price;
  }
  items.first.price += o.gross - used; // rounding remainder
  return Bom(items, removed);
}

String rupee(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}₹$b';
}

/// A calculation saved to history. Appliances are kept as JSON snapshots.
class ApplRecord {
  String id, label, note;
  int at;
  ApplCfg cfg;
  List<Map<String, dynamic>> items;
  // headline numbers at the time of saving
  double monthly, kwp, invKw, batteryKwh, gross, subsidy, savePerMonth, payback;
  ApplRecord({
    required this.id,
    required this.at,
    required this.label,
    required this.cfg,
    required this.items,
    this.note = '',
    this.monthly = 0,
    this.kwp = 0,
    this.invKw = 0,
    this.batteryKwh = 0,
    this.gross = 0,
    this.subsidy = 0,
    this.savePerMonth = 0,
    this.payback = 0,
  });
  double get net => gross - subsidy;

  /// Same inputs and same result: used to avoid saving duplicates.
  String get signature => '${jsonEncode(cfg.toJson())}|${jsonEncode(items)}|${gross.round()}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at,
        'label': label,
        'note': note,
        'cfg': cfg.toJson(),
        'items': items,
        'm': monthly,
        'kwp': kwp,
        'inv': invKw,
        'bat': batteryKwh,
        'gross': gross,
        'sub': subsidy,
        'save': savePerMonth,
        'pb': payback,
      };
  factory ApplRecord.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return ApplRecord(
      id: (j['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
      at: (j['at'] as num?)?.toInt() ?? 0,
      label: (j['label'] as String?) ?? 'Calculation',
      note: (j['note'] as String?) ?? '',
      cfg: ApplCfg.fromJson(((j['cfg'] as Map?) ?? {}).cast<String, dynamic>()),
      items: ((j['items'] as List?) ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
      monthly: d('m'),
      kwp: d('kwp'),
      invKw: d('inv'),
      batteryKwh: d('bat'),
      gross: d('gross'),
      subsidy: d('sub'),
      savePerMonth: d('save'),
      payback: d('pb'),
    );
  }
}
