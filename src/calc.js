// Pure calculation engine for Solar Planner & Calculator (no DOM access, unit-testable).

export const DEFAULTS = {
  mode: 'units',          // 'units' | 'bill'
  monthlyUnits: 400,      // kWh per month
  monthlyBill: 3000,      // Rs per month (used when mode === 'bill')
  tariff: 7.5,            // Rs per kWh (average)
  coverage: 100,          // % of consumption to offset
  yieldPerKwDay: 4.0,     // kWh generated per kW per day (net of losses)
  panelWp: 540,           // watt-peak per panel
  areaPerKw: 10,          // square metres of shadow-free roof per kW
  costPerKw: 60000,       // Rs per kW, installed
  category: 'residential',// 'residential' | 'commercial'
  subsidy: true,          // apply PM Surya Ghar subsidy (residential only)
  degradation: 0.5,       // % panel output loss per year
  escalation: 3,          // % yearly tariff increase
  years: 25,
  co2PerKwh: 0.82,        // kg CO2 per kWh of grid power
};

const num = (v, d = 0) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : d;
};

/** PM Surya Ghar Muft Bijli Yojana central subsidy (residential rooftop). */
export function subsidyFor(kw) {
  const k = Math.max(0, kw);
  return 30000 * Math.min(k, 2) + 18000 * Math.max(0, Math.min(k, 3) - 2);
}

/** USC (Unique Service Connection) number helpers. */
export function normalizeUsc(v) {
  return String(v ?? '').replace(/[\s-]/g, '').toUpperCase();
}
export function isValidUsc(v) {
  return /^\d{9}$/.test(normalizeUsc(v));
}

export function calculate(input) {
  const i = { ...DEFAULTS, ...input };
  const tariff = Math.max(0.01, num(i.tariff, DEFAULTS.tariff));
  const monthlyUnits = i.mode === 'bill'
    ? num(i.monthlyBill) / tariff
    : num(i.monthlyUnits);
  const annualUse = Math.max(0, monthlyUnits) * 12;
  const coverage = Math.min(100, Math.max(0, num(i.coverage, 100))) / 100;
  const perKwYear = Math.max(0.1, num(i.yieldPerKwDay, 4)) * 365;
  const panelWp = Math.max(50, num(i.panelWp, 540));

  const neededKw = (annualUse * coverage) / perKwYear;
  const panels = neededKw > 0 ? Math.max(1, Math.ceil((neededKw * 1000) / panelWp)) : 0;
  const kw = (panels * panelWp) / 1000;
  const roofSqm = kw * num(i.areaPerKw, 10);
  const roofSqft = roofSqm * 10.7639;

  const cost = kw * num(i.costPerKw, 60000);
  const subsidy = i.subsidy && i.category === 'residential' ? subsidyFor(kw) : 0;
  const netCost = Math.max(0, cost - subsidy);

  const gen1 = kw * perKwYear;
  const deg = num(i.degradation) / 100;
  const esc = num(i.escalation) / 100;
  const years = Math.max(1, Math.min(40, Math.round(num(i.years, 25))));

  const series = [];
  let cum = 0;
  let paybackYears = null;
  for (let y = 1; y <= years; y++) {
    const gen = gen1 * Math.pow(1 - deg, y - 1);
    const t = tariff * Math.pow(1 + esc, y - 1);
    const saving = Math.min(gen, annualUse) * t;
    const prev = cum;
    cum += saving;
    if (paybackYears === null && cum >= netCost && netCost > 0) {
      paybackYears = y - 1 + (netCost - prev) / saving;
    }
    series.push({ year: y, generation: gen, saving, cumulative: cum, net: cum - netCost });
  }

  const year1Saving = series[0]?.saving ?? 0;
  return {
    monthlyUnits, annualUse, neededKw, panels, panelWp, kw, roofSqm, roofSqft,
    cost, subsidy, netCost,
    gen1, monthlyGen: gen1 / 12,
    year1Saving, monthlySaving: year1Saving / 12,
    paybackYears,
    lifetimeSaving: cum, lifetimeProfit: cum - netCost,
    roi: netCost > 0 ? ((cum - netCost) / netCost) * 100 : 0,
    co2Tonnes: (gen1 * num(i.co2PerKwh, 0.82)) / 1000,
    series, years,
  };
}

export const inr = (n) =>
  'Rs. ' + Math.round(num(n)).toLocaleString('en-IN');
