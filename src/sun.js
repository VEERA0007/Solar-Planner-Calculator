// Sun position, day timings and irradiance (live from Open-Meteo, clear-sky model as offline fallback).

const RAD = Math.PI / 180;

export function solarPosition(date, lat, lon) {
  const n = date.getTime() / 86400000 + 2440587.5 - 2451545.0;
  const L = (280.46 + 0.9856474 * n) % 360;
  const g = ((357.528 + 0.9856003 * n) % 360) * RAD;
  const lam = (L + 1.915 * Math.sin(g) + 0.02 * Math.sin(2 * g)) * RAD;
  const eps = (23.439 - 0.0000004 * n) * RAD;
  const dec = Math.asin(Math.sin(eps) * Math.sin(lam));
  const ra = Math.atan2(Math.cos(eps) * Math.sin(lam), Math.cos(lam));
  const gmst = (((280.46061837 + 360.98564736629 * n) % 360) + 360) % 360;
  const ha = (((gmst + lon) % 360) * RAD) - ra;
  const phi = lat * RAD;
  const alt = Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(ha));
  const az = Math.atan2(Math.sin(ha), Math.cos(ha) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi)) + Math.PI;
  return { alt: alt / RAD, az: ((az / RAD) % 360 + 360) % 360 };
}

export function compass(az) {
  const names = ['North', 'North-East', 'East', 'South-East', 'South', 'South-West', 'West', 'North-West'];
  return names[Math.round(az / 45) % 8];
}

/** Sunrise, solar noon and sunset (Date objects) for the local calendar day of `date`. */
export function dayInfo(date, lat, lon) {
  const start = new Date(date); start.setHours(0, 0, 0, 0);
  let rise = null, set = null, noon = null, best = -90;
  for (let m = 0; m < 1440; m++) {
    const t = new Date(start.getTime() + m * 60000);
    const a = solarPosition(t, lat, lon).alt;
    if (a > best) { best = a; noon = t; }
    if (a > 0) { if (!rise) rise = t; set = t; }
  }
  return { rise, set, noon, maxAlt: best };
}

/** Clear-sky GHI / DNI in W/m2 (Meinel + Kasten-Young airmass, with a haze factor for Indian skies). */
export function clearSky(alt) {
  if (alt <= 0) return { ghi: 0, dni: 0 };
  const s = Math.sin(alt * RAD);
  const am = 1 / (s + 0.50572 * Math.pow(alt + 6.07995, -1.6364));
  const dni = 1353 * Math.pow(0.7, Math.pow(am, 0.678)) * 0.8;
  return { ghi: dni * s + 0.1 * dni * s + 20 * s, dni };
}

export function modelHourly(date, lat, lon) {
  const day = new Date(date); day.setHours(0, 0, 0, 0);
  const out = [];
  for (let h = 0; h < 24; h++) {
    // average over the hour at its midpoint
    const t = new Date(day.getTime() + (h + 0.5) * 3600000);
    out.push(clearSky(solarPosition(t, lat, lon).alt).ghi);
  }
  return out;
}

/**
 * Fetch today's irradiance. Returns { hourly[24] W/m2, ghi, dni, cloud, source }.
 * Falls back to the clear-sky model when offline.
 */
export async function fetchIrradiance(lat, lon, now = new Date()) {
  const model = () => {
    const hourly = modelHourly(now, lat, lon);
    const c = clearSky(solarPosition(now, lat, lon).alt);
    return { hourly, ghi: c.ghi, dni: c.dni, cloud: 0, source: 'model' };
  };
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
      '&current=shortwave_radiation,direct_normal_irradiance,cloud_cover' +
      '&hourly=shortwave_radiation&forecast_days=1&timezone=auto';
    const ctl = new AbortController();
    const to = setTimeout(() => ctl.abort(), 8000);
    const r = await fetch(url, { signal: ctl.signal });
    clearTimeout(to);
    if (!r.ok) throw new Error('http ' + r.status);
    const j = await r.json();
    const hourly = (j.hourly && j.hourly.shortwave_radiation) || [];
    if (hourly.length < 24 || !j.current) throw new Error('bad payload');
    return {
      hourly: hourly.slice(0, 24).map((v) => Number(v) || 0),
      ghi: Number(j.current.shortwave_radiation) || 0,
      dni: Number(j.current.direct_normal_irradiance) || 0,
      cloud: Number(j.current.cloud_cover) || 0,
      source: 'live',
    };
  } catch {
    return model();
  }
}

export const sky = (cloud) => (cloud < 20 ? 'Clear sky / Optimal' : cloud < 60 ? 'Partly cloudy' : 'Overcast');
