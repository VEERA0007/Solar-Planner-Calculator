import assert from 'node:assert/strict';
import { calculate, subsidyFor, isValidUsc, normalizeUsc, DEFAULTS } from '../src/calc.js';
import { jpegPagesToPdf } from '../src/pdf.js';

// subsidy slabs (PM Surya Ghar)
assert.equal(subsidyFor(1), 30000);
assert.equal(subsidyFor(2), 60000);
assert.equal(subsidyFor(3), 78000);
assert.equal(subsidyFor(10), 78000);
assert.equal(subsidyFor(0), 0);

// USC helpers
assert.equal(normalizeUsc(' 123-456 789 '), '123456789');
assert.ok(isValidUsc('123456789'));
assert.ok(!isValidUsc('12345'));

// 400 units/month, 4 kWh/kW/day -> 3.29 kW needed -> 7 x 540 Wp = 3.78 kW
const r = calculate({ monthlyUnits: 400 });
assert.equal(r.panels, 7);
assert.ok(Math.abs(r.kw - 3.78) < 1e-9);
assert.equal(r.subsidy, 78000);
assert.equal(r.cost, 3.78 * 60000);
assert.equal(r.netCost, r.cost - 78000);
assert.ok(r.paybackYears > 2 && r.paybackYears < 8, 'payback ' + r.paybackYears);
assert.equal(r.series.length, 25);
assert.ok(r.series[24].cumulative > r.series[0].cumulative);
// savings never exceed consumption value
assert.ok(r.series[0].saving <= 400 * 12 * 7.5 + 1e-6);

// commercial gets no subsidy
assert.equal(calculate({ monthlyUnits: 400, category: 'commercial' }).subsidy, 0);
// subsidy toggle off
assert.equal(calculate({ monthlyUnits: 400, subsidy: false }).subsidy, 0);

// bill mode converts to units via tariff
const b = calculate({ mode: 'bill', monthlyBill: 3000, tariff: 7.5 });
assert.equal(Math.round(b.monthlyUnits), 400);

// zero / junk input does not crash
const z = calculate({ monthlyUnits: 0 });
assert.equal(z.panels, 0);
assert.ok(Number.isFinite(calculate({ monthlyUnits: 'abc' }).kw));

// PDF writer produces a structurally valid file
const fake = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
const pdf = jpegPagesToPdf([{ bytes: fake, w: 1, h: 1 }]);
const txt = Buffer.from(pdf).toString('latin1');
assert.ok(txt.startsWith('%PDF-1.4') && txt.trimEnd().endsWith('%%EOF'));
const xrefPos = Number(/startxref\n(\d+)/.exec(txt)[1]);
assert.equal(txt.slice(xrefPos, xrefPos + 4), 'xref');
for (const m of txt.matchAll(/(\d{10}) 00000 n /g)) {
  assert.match(txt.slice(Number(m[1]), Number(m[1]) + 12), /^\d+ 0 obj/);
}

console.log('All tests passed. Sample 400 units/mo ->', r.kw.toFixed(2), 'kW,', 'net Rs', Math.round(r.netCost), ', payback', r.paybackYears.toFixed(1), 'yrs');
