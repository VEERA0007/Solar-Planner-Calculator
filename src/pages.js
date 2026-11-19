import { solarPosition, compass, dayInfo, fetchIrradiance, sky } from './sun.js';

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const PR = 0.84;          // performance ratio of the plant
const CO2 = 0.82;         // kg CO2 per kWh grid power
const MONTH_PSH = [5.4, 6.1, 6.6, 6.7, 6.4, 5.0, 4.3, 4.2, 4.6, 5.1, 4.9, 5.0]; // typical kWh/m2/day, Hyderabad
const MONTHS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* ignore */ } },
};

let site = { city: 'Hyderabad', label: 'Telangana, India', lat: 17.385, lon: 78.4867, kwp: 3.74, tariff: 7.2, auto: true, ...store.get('sp.site', {}) };
let appliances = store.get('sp.appliances', [
  { name: 'Refrigerator', watts: 120, qty: 1, hours: 24, start: 0 },
  { name: 'Air conditioner', watts: 1500, qty: 1, hours: 6, start: 22 },
  { name: 'Ceiling fans', watts: 60, qty: 4, hours: 10, start: 18 },
  { name: 'LED lights', watts: 9, qty: 8, hours: 6, start: 18 },
  { name: 'Television', watts: 100, qty: 1, hours: 4, start: 19 },
  { name: 'Water pump', watts: 750, qty: 1, hours: 1, start: 7 },
]);
let irr = null;        // latest irradiance fetch
let lastSync = store.get('sp.lastSync', 0);

/* ---------- appliance maths ---------- */
function loadHourly() {
  const out = new Array(24).fill(0);
  for (const a of appliances) {
    const kw = (a.watts * a.qty) / 1000;
    const hrs = Math.min(24, Math.max(0, a.hours));
    for (let k = 0; k < 24; k++) {
      const h = (Math.floor(a.start) + k) % 24;
      const on = Math.min(1, Math.max(0, hrs - k));
      out[h] += kw * on;
    }
  }
  return out;
}
const dailyLoad = () => loadHourly().reduce((s, v) => s + v, 0);
const activeNow = (now = new Date()) => {
  let kw = 0, n = 0;
  const h = now.getHours();
  for (const a of appliances) {
    const off = (h - Math.floor(a.start) + 24) % 24;
    if (off < Math.ceil(Math.min(24, a.hours))) { kw += (a.watts * a.qty) / 1000; n++; }
  }
  return { kw, n };
};
const solarHourlyKw = () => (irr ? irr.hourly : new Array(24).fill(0)).map((g) => (site.kwp * g / 1000) * PR);

/* ---------- charts ---------- */
function bars(series, { w = 640, h = 180, labels = null, marker = -1 } = {}) {
  const L = 6, R = 6, T = 10, B = 22;
  const n = series[0].data.length;
  const max = Math.max(0.001, ...series.flatMap((s) => s.data));
  const gw = (w - L - R) / n, bw = gw / series.length - 2;
  let svg = '';
  for (let i = 0; i < n; i++) {
    series.forEach((s, j) => {
      const v = s.data[i], bh = (v / max) * (h - T - B);
      svg += `<rect x="${(L + i * gw + j * (bw + 1) + 1).toFixed(1)}" y="${(h - B - bh).toFixed(1)}" width="${Math.max(1, bw).toFixed(1)}" height="${Math.max(0, bh).toFixed(1)}" rx="2" fill="${s.color}" opacity="${marker === i || marker < 0 ? 1 : 0.55}"><title>${esc(s.name)} ${v.toFixed(2)}</title></rect>`;
    });
    if (labels && labels[i] != null) svg += `<text x="${(L + (i + 0.5) * gw).toFixed(1)}" y="${h - 6}" fill="#7C8AA8" font-size="11" text-anchor="middle">${labels[i]}</text>`;
  }
  return `<svg viewBox="0 0 ${w} ${h}" role="img">${svg}</svg>`;
}
const hourLabels = Array.from({ length: 24 }, (_, i) => (i % 3 === 0 ? i : null));

/* ---------- HOME ---------- */
const fmt = (n, d = 1) => (Math.round(n * 10 ** d) / 10 ** d).toLocaleString('en-IN');
const clock = (d) => d.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true });

function sunArc(now, info) {
  const f = info.rise && info.set ? Math.min(1, Math.max(0, (now - info.rise) / (info.set - info.rise))) : 0;
  const day = now >= info.rise && now <= info.set;
  const cx = 160, cy = 170, r = 140;
  const x = cx - r * Math.cos(Math.PI * f), y = cy - r * Math.sin(Math.PI * f);
  return `<svg viewBox="0 0 320 190"><path d="M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}" fill="none" stroke="#fff" stroke-width="3" stroke-dasharray="7 9" opacity=".9"/>
    <circle cx="${cx + r}" cy="${cy}" r="12" fill="#3a2a22"/>
    <circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="26" fill="#F59E0B" opacity="${day ? 0.18 : 0}"/>
    <circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="11" fill="${day ? '#F97316' : '#475569'}"/>
    <circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="5" fill="#0b1220"/><circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="3" fill="${day ? '#FDBA74' : '#94A3B8'}"/></svg>`;
}

function renderHome() {
  const now = new Date();
  const info = dayInfo(now, site.lat, site.lon);
  const pos = solarPosition(now, site.lat, site.lon);
  const hourly = irr ? irr.hourly : [];
  const psh = hourly.reduce((s, v) => s + v, 0) / 1000;
  const potential = site.kwp * psh * PR;
  const hNow = now.getHours() + now.getMinutes() / 60;
  const soFar = hourly.reduce((s, v, h) => s + (h + 1 <= hNow ? v : h <= hNow ? v * (hNow - h) : 0), 0) / 1000 * site.kwp * PR;
  const live = irr ? (site.kwp * irr.ghi / 1000) * PR : 0;
  const load = dailyLoad();
  const act = activeNow(now);
  const net = potential - load;
  const used = Math.min(potential, load);

  $('hCity').textContent = site.city;
  $('hLabel').textContent = site.label;
  $('hDate').textContent = now.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
  $('hAlt').textContent = (pos.alt >= 0 ? '+' : '') + pos.alt.toFixed(2) + '°';
  $('hDir').textContent = pos.alt > 0 ? compass(pos.az) : 'Below horizon';
  $('hPeak').textContent = info.noon ? clock(info.noon).toUpperCase() : '-';
  $('hArc').innerHTML = sunArc(now, info);
  $('hCo2Top').textContent = fmt(soFar * CO2) + ' kg CO₂ avoided';
  $('hSky').textContent = irr ? sky(irr.cloud) : 'Waiting for sync';
  $('hPsh').textContent = psh ? psh.toFixed(1) : '-';
  $('hGain').textContent = fmt(potential, potential < 100 ? 1 : 0).replace(/\.0$/, '');
  $('hPlant').textContent = `Yield from ${site.kwp} kWp plant`;
  $('hLive').textContent = `${live.toFixed(2)} kW live`;
  $('hGhi').textContent = `${Math.round(irr ? irr.ghi : 0)} W/m²`;
  $('hUse').textContent = fmt(load);
  $('hActive').textContent = `${act.kw.toFixed(2)} kW active`;
  $('hAppN').textContent = `${appliances.length} appliances`;
  $('hDef').textContent = (net >= 0 ? '+' : '-') + fmt(Math.abs(net));
  $('hDefLbl').textContent = net >= 0 ? 'Surplus exported to grid' : 'Deficit drawn from grid';
  $('hOffset').textContent = `Offset: ${load ? Math.min(100, Math.round((potential / load) * 100)) : 0}%`;
  $('hReliance').textContent = net >= 0 ? 'Self-sufficient' : 'Grid Reliance';
  $('hMoney').textContent = '₹' + Math.round(used * site.tariff).toLocaleString('en-IN');
  $('hTariff').textContent = `@ ₹${site.tariff}/kWh tariff`;
  $('hCo2').textContent = `${fmt(potential * CO2)} kg CO₂`;
  $('hBalSolar').textContent = fmt(potential);
  $('hBalLoad').textContent = fmt(load);
  const tot = Math.max(0.001, potential + load);
  $('hBarS').style.flex = String(potential / tot);
  $('hBarL').style.flex = String(load / tot);
  $('hIrr').textContent = irr ? `${Math.round(irr.dni)} DNI · ${Math.round(irr.ghi)} GHI` : '-';
  $('hNet').textContent = `${net >= 0 ? '+' : '-'}${fmt(Math.abs(net))} kWh Net ${net >= 0 ? 'Export' : 'Import'}`;
  $('hLive2').textContent = irr ? (irr.source === 'live' ? 'LIVE' : 'MODEL') : '';
  $('hUpd').textContent = lastSync ? `Updated: ${new Date(lastSync).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: false })}` : 'Not synced';
}

function tickClock() {
  const d = new Date();
  $('hClock').textContent = d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: true });
}

async function sync(manual = false) {
  const btn = $('syncNow');
  btn.classList.add('spin');
  irr = await fetchIrradiance(site.lat, site.lon);
  lastSync = Date.now(); store.set('sp.lastSync', lastSync);
  btn.classList.remove('spin');
  renderAll();
  if (manual) toast(irr.source === 'live' ? 'Synced with live weather data' : 'Offline: using clear-sky model');
}

/* ---------- SOLAR ANALYSIS ---------- */
function renderSolar() {
  const hk = solarHourlyKw();
  const psh = irr ? irr.hourly.reduce((s, v) => s + v, 0) / 1000 : 0;
  const daily = hk.reduce((s, v) => s + v, 0);
  const monthly = MONTH_PSH.map((p, i) => site.kwp * p * PR * new Date(2026, i + 1, 0).getDate());
  const annual = monthly.reduce((s, v) => s + v, 0);
  $('sPlant').textContent = `${site.kwp} kWp`;
  $('sToday').textContent = `${fmt(daily)} kWh`;
  $('sPsh').textContent = `${psh ? psh.toFixed(1) : '-'} h`;
  $('sPeakKw').textContent = `${fmt(Math.max(0, ...hk), 2)} kW`;
  $('sAnnual').textContent = `${Math.round(annual).toLocaleString('en-IN')} kWh`;
  $('sSpec').textContent = `${Math.round(annual / Math.max(0.1, site.kwp))} kWh/kWp`;
  $('sMoney').textContent = '₹' + Math.round(annual * site.tariff).toLocaleString('en-IN');
  $('sCo2').textContent = `${fmt((annual * CO2) / 1000)} t`;
  $('sHourChart').innerHTML = bars([{ name: 'kW', data: hk, color: '#F59E0B' }], { labels: hourLabels, marker: new Date().getHours() });
  $('sMonthChart').innerHTML = bars([{ name: 'kWh', data: monthly, color: '#38BDF8' }], { labels: MONTHS, marker: new Date().getMonth() });
}

/* ---------- APPLIANCES ---------- */
function renderApps() {
  const lh = loadHourly(), sh = solarHourlyKw();
  const day = lh.reduce((s, v) => s + v, 0);
  const act = activeNow();
  const peak = Math.max(0, ...lh);
  const solarUsed = lh.reduce((s, v, i) => s + Math.min(v, sh[i]), 0);
  $('aDaily').textContent = `${fmt(day)} kWh`;
  $('aActive').textContent = `${act.kw.toFixed(2)} kW (${act.n})`;
  $('aPeak').textContent = `${fmt(peak, 2)} kW`;
  $('aSelf').textContent = `${day ? Math.round((solarUsed / day) * 100) : 0}% from solar`;
  $('aChart').innerHTML = bars([{ name: 'Solar', data: sh, color: '#F59E0B' }, { name: 'Load', data: lh, color: '#0A9BFF' }], { labels: hourLabels, marker: new Date().getHours() });
  $('aList').innerHTML = appliances.map((a, i) => `
    <div class="app" data-i="${i}">
      <input data-f="name" value="${esc(a.name)}" aria-label="Appliance name">
      <div class="g4">
        <label>Watts<input data-f="watts" type="number" inputmode="decimal" min="0" value="${a.watts}"></label>
        <label>Qty<input data-f="qty" type="number" inputmode="numeric" min="1" value="${a.qty}"></label>
        <label>Hours/day<input data-f="hours" type="number" inputmode="decimal" min="0" max="24" step="0.5" value="${a.hours}"></label>
        <label>Start hr<input data-f="start" type="number" inputmode="numeric" min="0" max="23" value="${a.start}"></label>
      </div>
      <div class="appf"><span>${fmt((a.watts * a.qty * Math.min(24, a.hours)) / 1000, 2)} kWh/day</span><button type="button" class="link" data-del="1">Remove</button></div>
    </div>`).join('') || '<div class="card center">No appliances. Add one below.</div>';
}

function appEdit(e) {
  const row = e.target.closest('.app'); if (!row) return;
  const a = appliances[Number(row.dataset.i)], f = e.target.dataset.f; if (!a || !f) return;
  a[f] = f === 'name' ? e.target.value : Math.max(0, parseFloat(e.target.value) || 0);
  if (f === 'qty') a.qty = Math.max(1, Math.round(a.qty));
  if (f === 'start') a.start = Math.min(23, Math.floor(a.start));
  store.set('sp.appliances', appliances); renderAll();
}

/* ---------- shell ---------- */
let toastT;
function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 2600);
}
function go(page) {
  document.querySelectorAll('.page').forEach((p) => p.classList.toggle('on', p.id === 'pg-' + page));
  document.querySelectorAll('.navbtn').forEach((b) => b.classList.toggle('on', b.dataset.page === page));
  window.scrollTo({ top: 0 });
  renderAll();
}
function renderAll() { renderHome(); renderSolar(); renderApps(); }

/* ---------- settings (location, plant, tariff) ---------- */
function loadSettingsForm() {
  $('setCity').value = site.city; $('setLabel').value = site.label;
  $('setLat').value = site.lat; $('setLon').value = site.lon;
  $('setKwp').value = site.kwp; $('setTariff').value = site.tariff;
}
function saveSettingsForm() {
  const n = (id, d) => { const v = parseFloat($(id).value); return Number.isFinite(v) ? v : d; };
  site = { ...site, city: $('setCity').value.trim() || site.city, label: $('setLabel').value.trim(),
    lat: n('setLat', site.lat), lon: n('setLon', site.lon), kwp: Math.max(0.1, n('setKwp', site.kwp)), tariff: Math.max(0.1, n('setTariff', site.tariff)) };
  store.set('sp.site', site);
}

function init() {
  document.querySelectorAll('.navbtn').forEach((b) => b.addEventListener('click', () => go(b.dataset.page)));
  document.querySelectorAll('[data-goto]').forEach((el) => el.addEventListener('click', () => go(el.dataset.goto)));
  $('syncNow').addEventListener('click', () => sync(true));
  $('autoSync').checked = !!site.auto;
  $('autoSync').addEventListener('change', (e) => { site.auto = e.target.checked; store.set('sp.site', site); });
  $('gearBtn').addEventListener('click', loadSettingsForm); // dialog itself is opened by app.js
  $('settings').addEventListener('close', () => { if ($('settings').returnValue === 'ok') { saveSettingsForm(); renderAll(); sync(); } });
  $('gpsBtn').addEventListener('click', () => {
    if (!navigator.geolocation) { toast('GPS not available'); return; }
    navigator.geolocation.getCurrentPosition(
      (p) => { $('setLat').value = p.coords.latitude.toFixed(4); $('setLon').value = p.coords.longitude.toFixed(4); toast('Location captured. Press Save.'); },
      () => toast('Could not get location'), { timeout: 10000 });
  });
  $('aList').addEventListener('change', appEdit);
  $('aList').addEventListener('click', (e) => {
    if (!e.target.dataset.del) return;
    appliances.splice(Number(e.target.closest('.app').dataset.i), 1);
    store.set('sp.appliances', appliances); renderAll();
  });
  $('aAdd').addEventListener('click', () => {
    appliances.push({ name: 'New appliance', watts: 100, qty: 1, hours: 4, start: 18 });
    store.set('sp.appliances', appliances); renderAll();
  });
  // Estimator publishes its result so Home uses the designed plant size and tariff
  window.addEventListener('sp:site', (e) => {
    site = { ...site, ...e.detail }; store.set('sp.site', site); renderAll();
  });

  tickClock(); setInterval(tickClock, 1000);
  setInterval(() => { renderHome(); if (site.auto && Date.now() - lastSync > 3600000) sync(); }, 30000);
  renderAll();
  sync();
}
init();
