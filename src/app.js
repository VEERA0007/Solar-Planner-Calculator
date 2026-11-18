import { DEFAULTS, calculate, inr, normalizeUsc, isValidUsc } from './calc.js';
import { jpegPagesToPdf, dataUrlToBytes, bytesToBase64 } from './pdf.js';

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/* ---------- storage (safe wrappers) ---------- */
const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* ignore */ } },
};

let records = store.get('sp.records', []);
let brand = { company: 'Gensolar', phone: '', note: 'Estimate only. Final design, cost and subsidy subject to site survey and DISCOM approval.', ...store.get('sp.brand', {}) };
let current = null;      // last calculation result
let currentInput = null; // inputs used

const NUM_FIELDS = ['monthlyUnits', 'monthlyBill', 'tariff', 'coverage', 'yieldPerKwDay', 'panelWp', 'costPerKw', 'areaPerKw', 'degradation', 'escalation'];
let mode = 'units';

/* ---------- helpers ---------- */
let toastT;
function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 2600);
}
function setTab(name) {
  document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('on', b.dataset.tab === name));
  document.querySelectorAll('.panel').forEach((p) => p.classList.toggle('on', p.id === name));
  window.scrollTo({ top: 0 });
  if (name === 'saved') renderList();
}
function openLink(url) { window.open(url, '_blank'); }

/* ---------- form <-> state ---------- */
function fillDefaults() {
  NUM_FIELDS.forEach((f) => { $(f).value = DEFAULTS[f]; });
  $('category').value = DEFAULTS.category;
  $('subsidy').value = DEFAULTS.subsidy ? '1' : '0';
}
function readInput() {
  const o = { mode };
  NUM_FIELDS.forEach((f) => { o[f] = parseFloat($(f).value); });
  o.category = $('category').value;
  o.subsidy = $('subsidy').value === '1';
  return o;
}
function readCustomer() {
  return {
    usc: normalizeUsc($('usc').value),
    name: $('name').value.trim(),
    phone: $('phone').value.trim(),
    address: $('address').value.trim(),
  };
}
function writeForm(rec) {
  $('usc').value = rec.customer.usc || '';
  $('name').value = rec.customer.name || '';
  $('phone').value = rec.customer.phone || '';
  $('address').value = rec.customer.address || '';
  mode = rec.input.mode || 'units';
  NUM_FIELDS.forEach((f) => { if (rec.input[f] != null && !Number.isNaN(rec.input[f])) $(f).value = rec.input[f]; });
  $('category').value = rec.input.category;
  $('subsidy').value = rec.input.subsidy ? '1' : '0';
  applyMode();
}
function applyMode() {
  document.querySelectorAll('#modeSeg button').forEach((b) => b.classList.toggle('on', b.dataset.mode === mode));
  $('unitsWrap').hidden = mode !== 'units';
  $('billWrap').hidden = mode !== 'bill';
}

/* ---------- USC search ---------- */
function setUscMsg(text, kind = '') { const m = $('uscMsg'); m.textContent = text; m.className = 'hint ' + kind; }

function uscValidate() {
  const v = normalizeUsc($('usc').value);
  if (!v) return setUscMsg('');
  if (isValidUsc(v)) setUscMsg('Valid 9-digit USC format.', 'ok');
  else setUscMsg('USC numbers are normally 9 digits. You can still search.', 'warn');
}

function uscSearch() {
  const v = normalizeUsc($('usc').value);
  if (!v) { setUscMsg('Enter a USC number to search.', 'warn'); return; }
  const exact = records.filter((r) => normalizeUsc(r.customer.usc) === v);
  if (exact.length) {
    const r = exact.sort((a, b) => b.savedAt - a.savedAt)[0];
    writeForm(r);
    setUscMsg(`Found saved estimate for ${r.customer.name || 'this USC'} (${exact.length} saved). Details filled in.`, 'ok');
    toast('USC found - details loaded');
    return;
  }
  const partial = records.filter((r) => normalizeUsc(r.customer.usc).includes(v));
  if (partial.length) {
    $('search').value = v; setTab('saved');
    toast(`${partial.length} partial match(es)`);
    return;
  }
  setUscMsg('No saved estimate for this USC yet. Enter units from the bill below, or open the DISCOM site to check the bill.', 'warn');
}

/* ---------- calculate + render ---------- */
function validate(inp) {
  const use = inp.mode === 'bill' ? inp.monthlyBill : inp.monthlyUnits;
  if (!(use > 0)) { toast('Enter monthly units or bill'); return false; }
  if (!(inp.tariff > 0)) { toast('Enter the tariff (Rs./unit)'); return false; }
  return true;
}
function run() {
  const inp = readInput();
  if (!validate(inp)) return;
  currentInput = inp;
  current = calculate(inp);
  render(current);
  setTab('res');
}
const fmt1 = (n) => (Math.round(n * 10) / 10).toLocaleString('en-IN');

function render(r) {
  $('resEmpty').hidden = true; $('resBody').hidden = false;
  $('rKw').textContent = `${fmt1(r.kw)} kW`;
  $('rPanels').textContent = `${r.panels} x ${r.panelWp} Wp panels`;
  $('rRoof').textContent = `${Math.round(r.roofSqft)} sq ft (${Math.round(r.roofSqm)} sq m)`;
  $('rGen').textContent = `${Math.round(r.gen1).toLocaleString('en-IN')} kWh`;
  $('rCost').textContent = inr(r.cost);
  $('rSub').textContent = r.subsidy ? inr(r.subsidy) : 'None';
  $('rNet').textContent = inr(r.netCost);
  $('rPay').textContent = r.paybackYears ? `${fmt1(r.paybackYears)} years` : 'Over ' + r.years + ' yrs';
  $('rS1').textContent = inr(r.year1Saving);
  $('rSm').textContent = inr(r.monthlySaving);
  $('rProfit').textContent = inr(r.lifetimeProfit);
  $('rCo2').textContent = `${fmt1(r.co2Tonnes)} t`;
  $('chart').innerHTML = chartSvg(r.series);
  $('actMsg').textContent = '';
}

function chartSvg(series) {
  const W = 640, H = 260, L = 8, R = 8, T = 14, B = 26;
  const vals = series.map((s) => s.net);
  const max = Math.max(1, ...vals), min = Math.min(0, ...vals);
  const y = (v) => T + (1 - (v - min) / (max - min)) * (H - T - B);
  const bw = (W - L - R) / series.length;
  const zero = y(0);
  let bars = '';
  series.forEach((s, i) => {
    const top = y(Math.max(0, s.net)), bot = y(Math.min(0, s.net));
    const col = s.net >= 0 ? '#34D399' : '#F87171';
    bars += `<rect x="${(L + i * bw + 1).toFixed(1)}" y="${top.toFixed(1)}" width="${(bw - 2).toFixed(1)}" height="${Math.max(1, bot - top).toFixed(1)}" rx="2" fill="${col}"><title>Year ${s.year}: ${inr(s.net)}</title></rect>`;
  });
  const labels = [1, Math.ceil(series.length / 2), series.length]
    .map((n) => `<text x="${(L + (n - 0.5) * bw).toFixed(1)}" y="${H - 8}" fill="#94A3B8" font-size="12" text-anchor="middle">Yr ${n}</text>`).join('');
  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Cumulative net savings by year">
    <line x1="${L}" x2="${W - R}" y1="${zero.toFixed(1)}" y2="${zero.toFixed(1)}" stroke="#475569"/>${bars}${labels}</svg>`;
}

/* ---------- save / list ---------- */
function saveCurrent() {
  if (!current) return;
  const customer = readCustomer();
  if (!customer.usc && !customer.name) { toast('Add a USC number or customer name first'); setTab('est'); return; }
  const existing = customer.usc ? records.findIndex((r) => normalizeUsc(r.customer.usc) === customer.usc && r.customer.name === customer.name) : -1;
  const rec = {
    id: existing >= 0 ? records[existing].id : String(Date.now()),
    savedAt: Date.now(), customer, input: currentInput,
    summary: { kw: current.kw, panels: current.panels, net: current.netCost, payback: current.paybackYears },
  };
  if (existing >= 0) records[existing] = rec; else records.unshift(rec);
  store.set('sp.records', records);
  $('savedCount').textContent = records.length;
  $('actMsg').textContent = existing >= 0 ? 'Estimate updated.' : 'Estimate saved.';
  toast('Saved');
}

function hl(text, q) {
  const s = esc(text);
  if (!q) return s;
  const i = String(text).toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return s;
  const t = String(text);
  return esc(t.slice(0, i)) + '<mark>' + esc(t.slice(i, i + q.length)) + '</mark>' + esc(t.slice(i + q.length));
}

function renderList() {
  const q = $('search').value.trim();
  const qn = normalizeUsc(q);
  const rows = !q ? records : records.filter((r) => {
    const c = r.customer;
    return normalizeUsc(c.usc).includes(qn) || [c.name, c.phone, c.address].some((x) => (x || '').toLowerCase().includes(q.toLowerCase()));
  });
  $('savedCount').textContent = records.length;
  if (!rows.length) { $('list').innerHTML = `<div class="card center">${records.length ? 'No match.' : 'No saved estimates yet.'}</div>`; return; }
  $('list').innerHTML = rows.map((r) => {
    const c = r.customer, s = r.summary;
    return `<div class="item" data-id="${esc(r.id)}">
      <h3>${hl(c.name || 'Unnamed customer', q)}</h3>
      <div class="meta">USC ${hl(c.usc || '-', q)} &middot; ${hl(c.phone || 'no phone', q)}<br>${hl(c.address || '', q)}</div>
      <div class="nums"><b>${fmt1(s.kw)} kW</b> &middot; ${s.panels} panels &middot; Net ${inr(s.net)} &middot; Payback ${s.payback ? fmt1(s.payback) + ' yrs' : '-'}</div>
      <div class="acts"><button class="btn sm" data-act="open">Open</button><button class="btn sm ghost" data-act="pdf">Quote</button><button class="btn sm ghost" data-act="del">Delete</button></div>
    </div>`;
  }).join('');
}

function listClick(e) {
  const btn = e.target.closest('button[data-act]'); if (!btn) return;
  const id = btn.closest('.item').dataset.id;
  const r = records.find((x) => x.id === id); if (!r) return;
  if (btn.dataset.act === 'open') {
    writeForm(r); currentInput = r.input; current = calculate(r.input); render(current); setTab('res');
  } else if (btn.dataset.act === 'pdf') {
    makeQuote(r.customer, calculate(r.input));
  } else if (btn.dataset.act === 'del') {
    if (confirm('Delete this saved estimate?')) {
      records = records.filter((x) => x.id !== id); store.set('sp.records', records); renderList();
    }
  }
}

function exportCsv() {
  if (!records.length) { toast('Nothing to export'); return; }
  const head = ['USC', 'Name', 'Phone', 'Address', 'kW', 'Panels', 'Net cost (Rs)', 'Payback (yrs)', 'Saved on'];
  const q = (v) => '"' + String(v ?? '').replace(/"/g, '""') + '"';
  const lines = [head.map(q).join(',')].concat(records.map((r) => [
    r.customer.usc, r.customer.name, r.customer.phone, r.customer.address, r.summary.kw.toFixed(2), r.summary.panels,
    Math.round(r.summary.net), r.summary.payback ? r.summary.payback.toFixed(1) : '', new Date(r.savedAt).toLocaleDateString('en-IN'),
  ].map(q).join(',')));
  deliver('solar-estimates.csv', new TextEncoder().encode('﻿' + lines.join('\n')), 'text/csv');
}

/* ---------- file delivery (native share on Android, download in a browser) ---------- */
async function deliver(filename, bytes, mime) {
  const cap = window.Capacitor;
  const P = cap && cap.Plugins;
  try {
    if (cap && cap.isNativePlatform && cap.isNativePlatform() && P && P.Filesystem && P.Share) {
      const w = await P.Filesystem.writeFile({ path: filename, data: bytesToBase64(bytes), directory: 'CACHE' });
      await P.Share.share({ title: filename, url: w.uri, dialogTitle: 'Share' });
      return;
    }
  } catch (err) {
    if (err && /cancel/i.test(String(err.message || err))) return;
  }
  const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
  const a = document.createElement('a'); a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
  toast('Downloaded ' + filename);
}

/* ---------- quote PDF ---------- */
function makeQuote(customer, r) {
  const W = 1240, H = 1754, M = 80;
  const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
  const g = cv.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, W, H);
  const font = (px, w = 400) => { g.font = `${w} ${px}px Helvetica, Arial, sans-serif`; };
  // header
  const grad = g.createLinearGradient(0, 0, W, 0); grad.addColorStop(0, '#F59E0B'); grad.addColorStop(1, '#FBBF24');
  g.fillStyle = grad; g.fillRect(0, 0, W, 190);
  g.fillStyle = '#1c1300'; font(60, 800); g.fillText(brand.company || 'Solar Quote', M, 95);
  font(28, 500); g.fillText('Rooftop Solar Estimate', M, 140);
  g.textAlign = 'right'; font(26, 500);
  g.fillText(new Date().toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }), W - M, 95);
  if (brand.phone) g.fillText(brand.phone, W - M, 140);
  g.textAlign = 'left';

  let y = 260;
  const section = (t) => { g.fillStyle = '#B45309'; font(30, 700); g.fillText(t.toUpperCase(), M, y); y += 14; g.fillStyle = '#E5E7EB'; g.fillRect(M, y, W - 2 * M, 3); y += 44; };
  const kv = (k, v) => { g.fillStyle = '#6B7280'; font(28); g.fillText(k, M, y); g.fillStyle = '#111827'; font(30, 600); g.textAlign = 'right'; g.fillText(v, W - M, y); g.textAlign = 'left'; y += 52; };

  section('Customer');
  kv('Name', customer.name || '-');
  kv('USC number', customer.usc || '-');
  kv('Phone', customer.phone || '-');
  kv('Location', (customer.address || '-').slice(0, 48));
  y += 20;
  section('Proposed system');
  kv('System size', `${fmt1(r.kw)} kW`);
  kv('Solar panels', `${r.panels} x ${r.panelWp} Wp`);
  kv('Roof area needed', `${Math.round(r.roofSqft)} sq ft`);
  kv('Expected generation', `${Math.round(r.gen1).toLocaleString('en-IN')} kWh / year`);
  y += 20;
  section('Investment');
  kv('Project cost', inr(r.cost));
  kv('Government subsidy', r.subsidy ? '- ' + inr(r.subsidy) : 'Not applicable');
  g.fillStyle = '#FEF3C7'; g.fillRect(M - 16, y - 40, W - 2 * M + 32, 64);
  g.fillStyle = '#92400E'; font(30, 700); g.fillText('Net investment', M, y); g.textAlign = 'right'; g.fillText(inr(r.netCost), W - M, y); g.textAlign = 'left'; y += 80;
  section('Returns');
  kv('Saving in year 1', inr(r.year1Saving));
  kv('Average saving per month', inr(r.monthlySaving));
  kv('Payback period', r.paybackYears ? `${fmt1(r.paybackYears)} years` : '-');
  kv(`Total profit over ${r.years} years`, inr(r.lifetimeProfit));
  kv('CO2 avoided per year', `${fmt1(r.co2Tonnes)} tonnes`);

  // footer
  g.fillStyle = '#6B7280'; font(22);
  const words = (brand.note || '').split(' '); let line = ''; let fy = H - 110;
  for (const w of words) { const t = line ? line + ' ' + w : w; if (g.measureText(t).width > W - 2 * M) { g.fillText(line, M, fy); fy += 30; line = w; } else line = t; }
  if (line) g.fillText(line, M, fy);

  const bytes = dataUrlToBytes(cv.toDataURL('image/jpeg', 0.92));
  const pdf = jpegPagesToPdf([{ bytes, w: W, h: H }]);
  const safe = (customer.usc || customer.name || 'quote').replace(/[^A-Za-z0-9_-]+/g, '_');
  deliver(`Solar-Quote-${safe}.pdf`, pdf, 'application/pdf');
}

/* ---------- settings ---------- */
function openSettings() {
  $('setCompany').value = brand.company; $('setPhone').value = brand.phone; $('setNote').value = brand.note;
  $('settings').showModal();
}

/* ---------- init ---------- */
function init() {
  fillDefaults(); applyMode();
  $('savedCount').textContent = records.length;
  $('brandLine').textContent = (brand.company ? brand.company + ' - ' : '') + 'Rooftop solar estimator';

  document.querySelectorAll('.tab').forEach((b) => b.addEventListener('click', () => setTab(b.dataset.tab)));
  document.querySelectorAll('#modeSeg button').forEach((b) => b.addEventListener('click', () => { mode = b.dataset.mode; applyMode(); }));
  $('calcBtn').addEventListener('click', run);
  $('usc').addEventListener('input', uscValidate);
  $('usc').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); uscSearch(); } });
  $('uscFind').addEventListener('click', uscSearch);
  $('uscTs').addEventListener('click', () => openLink('https://tgsouthernpower.org'));
  $('uscTn').addEventListener('click', () => openLink('https://tgnpdcl.com'));
  $('resetAdv').addEventListener('click', fillDefaults);
  $('saveBtn').addEventListener('click', saveCurrent);
  $('pdfBtn').addEventListener('click', () => current && makeQuote(readCustomer(), current));
  $('search').addEventListener('input', renderList);
  $('list').addEventListener('click', listClick);
  $('exportBtn').addEventListener('click', exportCsv);
  $('settingsBtn').addEventListener('click', openSettings);
  $('settings').addEventListener('close', () => {
    if ($('settings').returnValue === 'ok') {
      brand = { company: $('setCompany').value.trim(), phone: $('setPhone').value.trim(), note: $('setNote').value.trim() };
      store.set('sp.brand', brand);
      $('brandLine').textContent = (brand.company ? brand.company + ' - ' : '') + 'Rooftop solar estimator';
      toast('Branding saved');
    }
  });
  renderList();
}
init();
