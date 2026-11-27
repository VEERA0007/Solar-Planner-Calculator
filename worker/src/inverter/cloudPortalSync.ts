import crypto from 'node:crypto';
import type {
  CloudInverterSyncResponse,
  DiscoveredCloudPlant,
  InverterBrandId,
  InverterExtendedTelemetry,
  InverterPvStringReading,
} from '../types/inverter';

// Set by the Worker entry point for each request (Worker secrets and variables).
let workerEnv: Record<string, string | undefined> = {};
export function setInverterEnv(env: Record<string, string | undefined>) {
  workerEnv = env || {};
}
function envVar(name: string): string | undefined {
  return workerEnv[name];
}

type CloudPortalBrand = 'soliscloud' | 'solarman' | 'growatt' | 'sungrow' | 'goodwe';

const CLOUD_PORTAL_BRANDS: CloudPortalBrand[] = [
  'soliscloud',
  'solarman',
  'growatt',
  'sungrow',
  'goodwe',
];

const BROWSER_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

// Strict outbound HTTPS allowlist for official manufacturer cloud monitoring portals (prevents SSRF)
const ALLOWED_PORTAL_HOST_SUFFIXES = [
  'semsportal.com',
  'growatt.com',
  'smten.com',
  'solarmanpv.com',
  'isolarcloud.com',
  'isolarcloud.eu',
  'isolarcloud.com.hk',
  'isolarcloud.com.cn',
  'soliscloud.com',
  'ginlong.com',
];

function assertAllowedPortalUrl(rawUrl: string): string {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new Error('Blocked malformed cloud portal URL.');
  }
  if (parsed.protocol !== 'https:') {
    throw new Error('Cloud portal requests must strictly use HTTPS.');
  }
  const host = parsed.hostname.toLowerCase();
  const allowed = ALLOWED_PORTAL_HOST_SUFFIXES.some(
    (suffix) => host === suffix || host.endsWith(`.${suffix}`)
  );
  if (!allowed) {
    throw new Error(`Blocked unverified portal host "${host}".`);
  }
  if (parsed.username || parsed.password) {
    throw new Error('Credentials must not be embedded in URLs.');
  }
  return parsed.toString();
}

async function portalFetch(
  rawUrl: string,
  init: RequestInit = {},
  timeoutMs = 10_000
): Promise<Response> {
  const safeUrl = assertAllowedPortalUrl(rawUrl);
  return fetch(safeUrl, {
    ...init,
    redirect: 'manual',
    signal: AbortSignal.timeout(timeoutMs),
    headers: {
      'User-Agent': BROWSER_UA,
      Accept: 'application/json, text/plain, */*',
      ...(init.headers || {}),
    },
  });
}

function extractSetCookies(resp: Response): string {
  const hdrs = resp.headers as unknown as { getSetCookie?: () => string[] };
  if (typeof hdrs.getSetCookie === 'function') {
    return hdrs
      .getSetCookie()
      .map((c) => c.split(';')[0].trim())
      .filter(Boolean)
      .join('; ');
  }
  const single = resp.headers.get('set-cookie');
  if (!single) return '';
  return single
    .split(/,(?=\s*[A-Za-z0-9_\-]+=)/)
    .map((c) => c.split(';')[0].trim())
    .filter(Boolean)
    .join('; ');
}

function mergeCookieHeader(existing: string, incoming: string): string {
  const map = new Map<string, string>();
  for (const part of `${existing}; ${incoming}`.split(';')) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const eq = trimmed.indexOf('=');
    if (eq > 0) {
      map.set(trimmed.slice(0, eq).trim(), trimmed.slice(eq + 1).trim());
    }
  }
  return Array.from(map.entries())
    .map(([k, v]) => `${k}=${v}`)
    .join('; ');
}

function toIstStamp(now: Date = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
  const parts = fmt.formatToParts(now);
  const pick = (t: string) => parts.find((p) => p.type === t)?.value || '';
  const dateKey = `${pick('year')}-${pick('month')}-${pick('day')}`;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const mIdx = Math.max(0, Math.min(11, Number(pick('month')) - 1));
  const ist = `${pick('day')} ${months[mIdx]} ${pick('year')}, ${pick('hour')}:${pick('minute')} ${pick('dayPeriod').toUpperCase()} IST`;
  return { dateKey, iso: now.toISOString(), ist };
}

function numVal(v: unknown): number | undefined {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const cleaned = v.replace(/,/g, '').replace(/[^0-9.\-+]/g, '').trim();
    if (!cleaned || cleaned === '-' || cleaned === '.') return undefined;
    const n = Number(cleaned);
    if (Number.isFinite(n)) return n;
  }
  return undefined;
}

function pickNum(obj: Record<string, unknown> | null | undefined, keys: string[]): number | undefined {
  if (!obj) return undefined;
  for (const k of keys) {
    if (k in obj) {
      const n = numVal(obj[k]);
      if (n !== undefined) return n;
    }
  }
  return undefined;
}

function pickStr(obj: Record<string, unknown> | null | undefined, keys: string[]): string | undefined {
  if (!obj) return undefined;
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
    if (typeof v === 'number' && Number.isFinite(v)) return String(v);
  }
  return undefined;
}

function normSerial(raw: string | undefined): string {
  return (raw || '').replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
}

function serialsMatch(expected: string | undefined, actual: string | undefined): boolean {
  const a = normSerial(expected);
  const b = normSerial(actual);
  if (!a || !b) return false;
  return a === b || a.includes(b) || b.includes(a);
}

function round2(n: number): number {
  return Number(n.toFixed(2));
}

function toKwSmart(val: number | undefined, unitHint?: string): number | undefined {
  if (val === undefined) return undefined;
  const u = (unitHint || '').trim().toLowerCase();
  if (u === 'kw' || u === 'kwp') return round2(val);
  if (u === 'mw') return round2(val * 1000);
  if (u === 'w' || u === 'va') return round2(val / 1000);
  // Heuristic when unit is absent: residential/commercial inverter power > 45 is typically Watts
  return Math.abs(val) > 45 ? round2(val / 1000) : round2(val);
}

function sanitizeDateKey(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const trimmed = raw.trim();
  const iso = trimmed.match(/^(20\d{2})[-/](\d{1,2})[-/](\d{1,2})/);
  if (iso) {
    return `${iso[1]}-${iso[2].padStart(2, '0')}-${iso[3].padStart(2, '0')}`;
  }
  return undefined;
}

function compactExtendedTelemetry(ext: InverterExtendedTelemetry): InverterExtendedTelemetry | undefined {
  const out: InverterExtendedTelemetry = {};
  if (ext.inverterStatus) out.inverterStatus = ext.inverterStatus;
  if (ext.inverterStatusText) out.inverterStatusText = ext.inverterStatusText.slice(0, 60);
  if (ext.inverterModel) out.inverterModel = ext.inverterModel.slice(0, 80);
  if (ext.firmwareVersion) out.firmwareVersion = ext.firmwareVersion.slice(0, 60);
  if (ext.loggerStatus) out.loggerStatus = ext.loggerStatus;
  if (typeof ext.loggerSignalPct === 'number' && Number.isFinite(ext.loggerSignalPct)) {
    out.loggerSignalPct = Math.max(0, Math.min(100, Math.round(ext.loggerSignalPct)));
  }
  if (typeof ext.serialMatchVerified === 'boolean') out.serialMatchVerified = ext.serialMatchVerified;
  if (ext.matchedInverterSerial) out.matchedInverterSerial = ext.matchedInverterSerial.slice(0, 80);
  if (ext.matchedLoggerSerial) out.matchedLoggerSerial = ext.matchedLoggerSerial.slice(0, 80);
  if (typeof ext.inverterTempC === 'number' && Number.isFinite(ext.inverterTempC) && ext.inverterTempC >= -40 && ext.inverterTempC <= 150) {
    out.inverterTempC = Number(ext.inverterTempC.toFixed(1));
  }
  if (typeof ext.gridVoltageV === 'number' && Number.isFinite(ext.gridVoltageV) && ext.gridVoltageV >= 0 && ext.gridVoltageV <= 1000) {
    out.gridVoltageV = Number(ext.gridVoltageV.toFixed(1));
  }
  if (typeof ext.gridVoltageR === 'number' && Number.isFinite(ext.gridVoltageR) && ext.gridVoltageR >= 0 && ext.gridVoltageR <= 1000) {
    out.gridVoltageR = Number(ext.gridVoltageR.toFixed(1));
  }
  if (typeof ext.gridVoltageS === 'number' && Number.isFinite(ext.gridVoltageS) && ext.gridVoltageS >= 0 && ext.gridVoltageS <= 1000) {
    out.gridVoltageS = Number(ext.gridVoltageS.toFixed(1));
  }
  if (typeof ext.gridVoltageT === 'number' && Number.isFinite(ext.gridVoltageT) && ext.gridVoltageT >= 0 && ext.gridVoltageT <= 1000) {
    out.gridVoltageT = Number(ext.gridVoltageT.toFixed(1));
  }
  if (typeof ext.acCurrentA === 'number' && Number.isFinite(ext.acCurrentA) && ext.acCurrentA >= 0 && ext.acCurrentA <= 500) {
    out.acCurrentA = Number(ext.acCurrentA.toFixed(2));
  }
  if (typeof ext.gridFrequencyHz === 'number' && Number.isFinite(ext.gridFrequencyHz) && ext.gridFrequencyHz >= 0 && ext.gridFrequencyHz <= 100) {
    out.gridFrequencyHz = Number(ext.gridFrequencyHz.toFixed(2));
  }
  if (typeof ext.powerFactor === 'number' && Number.isFinite(ext.powerFactor) && ext.powerFactor >= -1 && ext.powerFactor <= 1) {
    out.powerFactor = Number(ext.powerFactor.toFixed(3));
  }
  if (typeof ext.monthGenKwh === 'number' && Number.isFinite(ext.monthGenKwh) && ext.monthGenKwh >= 0) {
    out.monthGenKwh = round2(Math.min(1_000_000, ext.monthGenKwh));
  }
  if (typeof ext.yearGenKwh === 'number' && Number.isFinite(ext.yearGenKwh) && ext.yearGenKwh >= 0) {
    out.yearGenKwh = round2(Math.min(10_000_000, ext.yearGenKwh));
  }
  if (typeof ext.peakPowerKw === 'number' && Number.isFinite(ext.peakPowerKw) && ext.peakPowerKw >= 0) {
    out.peakPowerKw = round2(Math.min(10_000, ext.peakPowerKw));
  }
  if (typeof ext.batterySocPct === 'number' && Number.isFinite(ext.batterySocPct) && ext.batterySocPct >= 0 && ext.batterySocPct <= 100) {
    out.batterySocPct = Math.round(ext.batterySocPct);
  }
  if (typeof ext.batteryPowerKw === 'number' && Number.isFinite(ext.batteryPowerKw) && Math.abs(ext.batteryPowerKw) <= 5000) {
    out.batteryPowerKw = round2(ext.batteryPowerKw);
  }
  if (typeof ext.batteryVoltageV === 'number' && Number.isFinite(ext.batteryVoltageV) && ext.batteryVoltageV >= 0 && ext.batteryVoltageV <= 1200) {
    out.batteryVoltageV = Number(ext.batteryVoltageV.toFixed(1));
  }
  if (typeof ext.batteryTempC === 'number' && Number.isFinite(ext.batteryTempC) && ext.batteryTempC >= -40 && ext.batteryTempC <= 120) {
    out.batteryTempC = Number(ext.batteryTempC.toFixed(1));
  }
  if (typeof ext.todayBatteryChargeKwh === 'number' && Number.isFinite(ext.todayBatteryChargeKwh) && ext.todayBatteryChargeKwh >= 0) {
    out.todayBatteryChargeKwh = round2(Math.min(100_000, ext.todayBatteryChargeKwh));
  }
  if (typeof ext.todayBatteryDischargeKwh === 'number' && Number.isFinite(ext.todayBatteryDischargeKwh) && ext.todayBatteryDischargeKwh >= 0) {
    out.todayBatteryDischargeKwh = round2(Math.min(100_000, ext.todayBatteryDischargeKwh));
  }
  if (Array.isArray(ext.pvStrings) && ext.pvStrings.length > 0) {
    const cleanStrings = ext.pvStrings
      .slice(0, 8)
      .filter((s) => (s.voltageV ?? 0) > 0 || (s.currentA ?? 0) > 0 || (s.powerW ?? 0) > 0)
      .map((s) => ({
        id: String(s.id).slice(0, 12),
        ...(typeof s.voltageV === 'number' && Number.isFinite(s.voltageV)
          ? { voltageV: Number(s.voltageV.toFixed(1)) }
          : {}),
        ...(typeof s.currentA === 'number' && Number.isFinite(s.currentA)
          ? { currentA: Number(s.currentA.toFixed(2)) }
          : {}),
        ...(typeof s.powerW === 'number' && Number.isFinite(s.powerW)
          ? { powerW: Math.round(s.powerW) }
          : {}),
      }));
    if (cleanStrings.length > 0) out.pvStrings = cleanStrings;
  }
  if (ext.faultCode) out.faultCode = ext.faultCode.slice(0, 40);
  if (ext.faultMessage) out.faultMessage = ext.faultMessage.slice(0, 160);
  if (ext.portalRegion) out.portalRegion = ext.portalRegion.slice(0, 40);

  return Object.keys(out).length > 0 ? out : undefined;
}

interface PortalSyncParams {
  authMode?: 'website' | 'api';
  username: string;
  password: string;
  apiKey?: string;
  apiSecret?: string;
  inverterSerial?: string;
  loggerSerial?: string;
  stationId?: string;
  region?: string;
}

// ============================================================================
// 1. GOODWE SEMS PORTAL (Direct Email + Password via CrossLogin)
// ============================================================================
async function syncGoodWeSemsPortal(params: PortalSyncParams): Promise<CloudInverterSyncResponse> {
  const initToken = Buffer.from(
    JSON.stringify({
      uid: '',
      timestamp: 0,
      token: '',
      client: 'web',
      version: '',
      language: 'en',
    })
  ).toString('base64');

  const loginUrls = [
    'https://www.semsportal.com/api/v2/Common/CrossLogin',
    'https://eu.semsportal.com/api/v2/Common/CrossLogin',
    'https://au.semsportal.com/api/v2/Common/CrossLogin',
  ];

  let authTokenHeader = '';
  let apiBase = 'https://www.semsportal.com/api/';
  let lastAuthErr = 'GoodWe SEMS login failed. Check your SEMS Portal email and password.';

  for (const loginUrl of loginUrls) {
    try {
      const resp = await portalFetch(loginUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Token: initToken,
        },
        body: JSON.stringify({
          account: params.username,
          pwd: params.password,
        }),
      });
      const json = (await resp.json().catch(() => null)) as {
        hasError?: boolean;
        code?: number;
        msg?: string;
        api?: string;
        data?: Record<string, unknown>;
      } | null;

      if (resp.ok && json && !json.hasError && json.data && json.data.token) {
        authTokenHeader = Buffer.from(JSON.stringify(json.data)).toString('base64');
        if (typeof json.api === 'string' && json.api.startsWith('https://')) {
          const normalized = json.api.endsWith('/') ? json.api : `${json.api}/`;
          assertAllowedPortalUrl(normalized);
          apiBase = normalized;
        }
        break;
      }
      if (json?.msg) lastAuthErr = `GoodWe SEMS: ${json.msg}`;
    } catch {
      // Try next regional endpoint
    }
  }

  if (!authTokenHeader) {
    return { ok: false, brand: 'goodwe', providerName: 'GoodWe SEMS', error: lastAuthErr };
  }

  // Fetch stations linked to this GoodWe SEMS account
  let stationList: Array<{ id: string; name: string; capacity?: number; status?: string }> = [];

  const listCandidates: Array<{ path: string; body: Record<string, unknown> }> = [
    { path: 'v2/HistoryData/QueryPowerStationByHistory', body: {} },
    { path: 'v3/PowerStation/GetPowerStationList', body: { page_index: 1, page_size: 20 } },
    { path: 'v1/PowerStation/GetPowerStationList', body: { page_index: 1, page_size: 20 } },
  ];

  for (const cand of listCandidates) {
    try {
      const r = await portalFetch(`${apiBase}${cand.path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Token: authTokenHeader,
        },
        body: JSON.stringify(cand.body),
      });
      const j = (await r.json().catch(() => null)) as {
        data?:
          | Array<Record<string, unknown>>
          | { list?: Array<Record<string, unknown>>; data?: Array<Record<string, unknown>> };
      } | null;
      const rawArr = Array.isArray(j?.data)
        ? j.data
        : Array.isArray(j?.data?.list)
          ? j.data.list
          : Array.isArray(j?.data?.data)
            ? j.data.data
            : [];
      if (rawArr.length > 0) {
        stationList = rawArr
          .map((item) => ({
            id: pickStr(item, ['id', 'powerstation_id', 'stationId']) || '',
            name: pickStr(item, ['stationname', 'name', 'powerstation_name']) || 'GoodWe Solar Plant',
            capacity: pickNum(item, ['capacity', 'capacity_kw']),
            status: pickStr(item, ['status_str', 'status']),
          }))
          .filter((s) => Boolean(s.id));
        if (stationList.length > 0) break;
      }
    } catch {
      // Try next station list path
    }
  }

  const targetStationIds = params.stationId
    ? [params.stationId]
    : stationList.map((s) => s.id).slice(0, 8);

  if (targetStationIds.length === 0) {
    return {
      ok: false,
      brand: 'goodwe',
      providerName: 'GoodWe SEMS',
      error: 'Signed in to GoodWe SEMS, but no power stations were found under this account.',
    };
  }

  const fetchDetail = async (psId: string) => {
    const r = await portalFetch(`${apiBase}v2/PowerStation/GetMonitorDetailByPowerstationId`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Token: authTokenHeader,
      },
      body: JSON.stringify({ powerStationId: psId }),
    });
    const j = (await r.json().catch(() => null)) as {
      hasError?: boolean;
      data?: Record<string, unknown>;
    } | null;
    if (!r.ok || !j?.data || j.hasError) return null;
    return j.data;
  };

  let chosenPsId = targetStationIds[0];
  let chosenDetail: Record<string, unknown> | null = null;
  let matchedInvSn: string | undefined;
  let matchedLogSn: string | undefined;
  let serialMatchVerified = false;
  const discovered: DiscoveredCloudPlant[] = [];

  for (const psId of targetStationIds) {
    const detail = await fetchDetail(psId);
    if (!detail) continue;

    const info = (detail.info as Record<string, unknown>) || {};
    const inverters = Array.isArray(detail.inverter)
      ? (detail.inverter as Array<Record<string, unknown>>)
      : [];

    let stationInvSn: string | undefined;
    let stationLogSn: string | undefined;
    let matchedHere = false;

    for (const inv of inverters) {
      const d = (inv.d as Record<string, unknown>) || {};
      const full = (inv.invert_full as Record<string, unknown>) || {};
      const sn = pickStr(inv, ['sn']) || pickStr(full, ['sn']) || pickStr(d, ['sn']);
      const logSn =
        pickStr(full, ['check_code', 'wifi_sn', 'collector_sn', 'datalogger_sn']) ||
        pickStr(inv, ['wifi_sn', 'collector_sn']) ||
        pickStr(d, ['wifi_sn', 'collector_sn']);

      if (!stationInvSn && sn) stationInvSn = sn;
      if (!stationLogSn && logSn) stationLogSn = logSn;

      const invMatch = params.inverterSerial ? serialsMatch(params.inverterSerial, sn) : false;
      const logMatch = params.loggerSerial
        ? serialsMatch(params.loggerSerial, logSn) || serialsMatch(params.loggerSerial, sn)
        : false;

      if (invMatch || logMatch) {
        matchedHere = true;
        matchedInvSn = sn;
        matchedLogSn = logSn || params.loggerSerial;
        serialMatchVerified =
          (!params.inverterSerial || invMatch) && (!params.loggerSerial || logMatch);
        break;
      }
    }

    discovered.push({
      stationId: psId,
      plantName:
        pickStr(info, ['stationname', 'name']) ||
        stationList.find((s) => s.id === psId)?.name ||
        'GoodWe Solar Plant',
      capacityKwp: pickNum(info, ['capacity']) ?? stationList.find((s) => s.id === psId)?.capacity,
      inverterSerial: stationInvSn,
      loggerSerial: stationLogSn,
      status: pickStr(info, ['status']),
    });

    if (matchedHere) {
      chosenPsId = psId;
      chosenDetail = detail;
      break;
    }
    if (!chosenDetail) {
      chosenPsId = psId;
      chosenDetail = detail;
      matchedInvSn = stationInvSn;
      matchedLogSn = stationLogSn;
    }
  }

  // If multiple stations exist and user did not specify stationId or matching serials, offer clean plant picker
  if (
    !params.stationId &&
    !serialMatchVerified &&
    discovered.length > 1 &&
    !params.inverterSerial &&
    !params.loggerSerial
  ) {
    return {
      ok: false,
      brand: 'goodwe',
      detectedBrand: 'goodwe',
      providerName: 'GoodWe SEMS',
      requiresPlantSelection: true,
      discoveredPlants: discovered,
      message: `Found ${discovered.length} GoodWe SEMS plants on your account. Select the plant you want to sync.`,
    };
  }

  if (!chosenDetail) {
    return {
      ok: false,
      brand: 'goodwe',
      providerName: 'GoodWe SEMS',
      error: 'Signed in to GoodWe SEMS, but could not load plant monitor telemetry.',
    };
  }

  const stamp = toIstStamp();
  const info = (chosenDetail.info as Record<string, unknown>) || {};
  const kpi = (chosenDetail.kpi as Record<string, unknown>) || {};
  const pf = (chosenDetail.powerflow as Record<string, unknown>) || {};
  const energe = (chosenDetail.energeStatisticsTotals as Record<string, unknown>) || {};
  const inverters = Array.isArray(chosenDetail.inverter)
    ? (chosenDetail.inverter as Array<Record<string, unknown>>)
    : [];

  // Pick matching inverter record if available
  const activeInv =
    inverters.find((inv) => {
      const full = (inv.invert_full as Record<string, unknown>) || {};
      const sn = pickStr(inv, ['sn']) || pickStr(full, ['sn']);
      return params.inverterSerial ? serialsMatch(params.inverterSerial, sn) : false;
    }) || inverters[0];

  const invD = ((activeInv?.d as Record<string, unknown>) || {}) as Record<string, unknown>;
  const invFull = ((activeInv?.invert_full as Record<string, unknown>) || {}) as Record<
    string,
    unknown
  >;

  const livePowerKw =
    toKwSmart(pickNum(kpi, ['pac']), 'w') ??
    toKwSmart(pickNum(pf, ['pv']), 'w') ??
    toKwSmart(pickNum(invFull, ['pac', 'output_power']), 'w') ??
    0;
  const todayGenKwh =
    pickNum(kpi, ['power']) ??
    pickNum(energe, ['etoday', 'generation']) ??
    pickNum(invFull, ['eday']) ??
    0;
  const monthGenKwh = pickNum(kpi, ['month_generation']) ?? pickNum(invFull, ['emonth']);
  const lifetimeKwh =
    pickNum(kpi, ['total_power']) ??
    pickNum(energe, ['etotal']) ??
    pickNum(invFull, ['etotal']);
  const todayUsageKwh = pickNum(energe, ['consumptionOfLoad', 'load', 'use_energy']);
  const todayExportKwh = pickNum(energe, ['sell', 'export', 'grid_sell']);
  const todayImportKwh = pickNum(energe, ['buy', 'import', 'grid_buy']);
  const hasSmartMeter =
    todayUsageKwh !== undefined || todayExportKwh !== undefined || todayImportKwh !== undefined;

  // Build PV strings (PV1..PV4)
  const pvStrings: InverterPvStringReading[] = [];
  for (let i = 1; i <= 4; i++) {
    const v = pickNum(invFull, [`vpv${i}`]) ?? pickNum(invD, [`vpv${i}`]);
    const a = pickNum(invFull, [`ipv${i}`]) ?? pickNum(invD, [`ipv${i}`]);
    const w = v !== undefined && a !== undefined ? Math.round(v * a) : undefined;
    if ((v ?? 0) > 0 || (a ?? 0) > 0) {
      pvStrings.push({ id: `PV${i}`, voltageV: v, currentA: a, powerW: w });
    }
  }

  const rawStatus = pickNum(invFull, ['status']) ?? pickNum(activeInv, ['status']);
  const inverterStatus: InverterExtendedTelemetry['inverterStatus'] =
    rawStatus === 1
      ? 'online'
      : rawStatus === 0
        ? 'standby'
        : rawStatus === 2
          ? 'fault'
          : rawStatus === -1
            ? 'offline'
            : livePowerKw > 0
              ? 'online'
              : 'unknown';

  const soc = pickNum(pf, ['soc']) ?? pickNum(invFull, ['cbattery1', 'battery_soc']);
  const batPowerKw = toKwSmart(pickNum(pf, ['bettery', 'battery']), 'w');

  const extendedTelemetry = compactExtendedTelemetry({
    inverterStatus,
    inverterStatusText:
      inverterStatus === 'online'
        ? 'Generating'
        : inverterStatus === 'standby'
          ? 'Standby'
          : inverterStatus === 'fault'
            ? 'Fault / Alarm'
            : inverterStatus === 'offline'
              ? 'Offline'
              : 'Synced',
    inverterModel: pickStr(invFull, ['model_type', 'name']) || pickStr(activeInv, ['name']),
    firmwareVersion: pickStr(invFull, ['firmwareversion', 'arm_version']),
    loggerStatus: inverterStatus === 'offline' ? 'offline' : 'online',
    serialMatchVerified,
    matchedInverterSerial: matchedInvSn || pickStr(invFull, ['sn']),
    matchedLoggerSerial: matchedLogSn,
    inverterTempC: pickNum(invFull, ['tempperature', 'temperature']),
    gridVoltageV: pickNum(invFull, ['vac1', 'vgrid1']),
    gridVoltageR: pickNum(invFull, ['vac1']),
    gridVoltageS: pickNum(invFull, ['vac2']),
    gridVoltageT: pickNum(invFull, ['vac3']),
    acCurrentA: pickNum(invFull, ['iac1', 'igrid1']),
    gridFrequencyHz: pickNum(invFull, ['fac1', 'fgrid1']),
    monthGenKwh,
    batterySocPct: soc,
    batteryPowerKw: batPowerKw,
    batteryVoltageV: pickNum(invFull, ['vbattery1']),
    pvStrings,
    faultMessage: pickStr(invFull, ['err_msg', 'warning_msg']),
    portalRegion: new URL(apiBase).hostname,
  });

  // Attempt recent 14-day daily generation history from GoodWe
  const historicalDailyLogs: CloudInverterSyncResponse['historicalDailyLogs'] = [];
  try {
    const chartResp = await portalFetch(`${apiBase}v2/Charts/GetChartByPlant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Token: authTokenHeader,
      },
      body: JSON.stringify({
        id: chosenPsId,
        date: stamp.dateKey,
        range: 2, // month view (daily bars)
        chartIndexId: '3',
        isDetailFull: false,
      }),
    });
    const chartJson = (await chartResp.json().catch(() => null)) as {
      data?: { lines?: Array<{ xy?: Array<{ x?: string; y?: number | string }> }> };
    } | null;
    const xy = chartJson?.data?.lines?.[0]?.xy || [];
    for (const pt of xy) {
      const dk = sanitizeDateKey(pt.x);
      const val = numVal(pt.y);
      if (dk && val !== undefined && val >= 0) {
        historicalDailyLogs.push({ dateKey: dk, generationKwh: round2(val) });
      }
    }
  } catch {
    // Optional history fetch
  }

  return {
    ok: true,
    brand: 'goodwe',
    detectedBrand: 'goodwe',
    providerName: 'GoodWe SEMS Portal',
    detectedFormat: 'goodwe_sems_cloud',
    detectedStationId: chosenPsId,
    detectedPlantName: pickStr(info, ['stationname', 'name']) || 'GoodWe Solar Plant',
    detectedInverterSerial: matchedInvSn || pickStr(invFull, ['sn']),
    detectedLoggerSerial: matchedLogSn,
    serialMatchVerified,
    detectedModelName: pickStr(invFull, ['model_type', 'name']),
    detectedCapacityKwp: pickNum(info, ['capacity']),
    message: `Synced live GoodWe SEMS telemetry${serialMatchVerified ? ' (Inverter & Logger verified)' : ''}`,
    telemetry: {
      dateKey: stamp.dateKey,
      todayGenKwh: round2(Math.max(0, todayGenKwh)),
      livePowerKw: round2(Math.max(0, livePowerKw)),
      ...(todayUsageKwh !== undefined ? { todayUsageKwh: round2(Math.max(0, todayUsageKwh)) } : {}),
      ...(todayExportKwh !== undefined ? { todayExportKwh: round2(Math.max(0, todayExportKwh)) } : {}),
      ...(todayImportKwh !== undefined ? { todayImportKwh: round2(Math.max(0, todayImportKwh)) } : {}),
      ...(lifetimeKwh !== undefined ? { lifetimeKwh: Number(Math.max(0, lifetimeKwh).toFixed(1)) } : {}),
      hasSmartMeter,
      syncedAtIso: stamp.iso,
      syncedAtIst: stamp.ist,
      statusNote: `GoodWe SEMS Cloud · ${matchedInvSn || chosenPsId}`,
    },
    extendedTelemetry,
    historicalDailyLogs: historicalDailyLogs.length > 0 ? historicalDailyLogs.slice(-30) : undefined,
  };
}

// ============================================================================
// 2. GROWATT SHINESERVER (Direct Username/Email + MD5 Password Login + OpenAPI)
// ============================================================================
function growattMd5Hash(password: string, modified: boolean): string {
  const digest = crypto.createHash('md5').update(password, 'utf8').digest('hex');
  if (!modified) return digest;
  // Growatt's historical MD5 quirk replaces leading '0' in each hex byte pair with 'c'
  let out = '';
  for (let i = 0; i < digest.length; i += 2) {
    out += (digest[i] === '0' ? 'c' : digest[i]) + digest[i + 1];
  }
  return out;
}

async function syncGrowattPortal(params: PortalSyncParams): Promise<CloudInverterSyncResponse> {
  const bases = ['https://server.growatt.com', 'https://server-us.growatt.com'];
  let activeBase = bases[0];
  let cookieJar = '';
  let loggedIn = false;
  let plantItems: Array<{ id: string; name: string }> = [];
  let lastError = 'Growatt ShineServer login failed. Check your ShinePhone/ShineServer username and password.';

  for (const base of bases) {
    for (const useModifiedMd5 of [true, false]) {
      try {
        const form = new URLSearchParams({
          userName: params.username,
          password: growattMd5Hash(params.password, useModifiedMd5),
        });
        const resp = await portalFetch(`${base}/newTwoLoginAPI.do`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: form.toString(),
        });
        const cookies = extractSetCookies(resp);
        const json = (await resp.json().catch(() => null)) as {
          back?: {
            success?: boolean;
            msg?: string;
            data?: Array<Record<string, unknown>>;
          };
        } | null;

        if (resp.ok && json?.back?.success) {
          activeBase = base;
          cookieJar = cookies;
          loggedIn = true;
          const rawPlants = Array.isArray(json.back.data) ? json.back.data : [];
          plantItems = rawPlants
            .map((p) => ({
              id: pickStr(p, ['plantId', 'id']) || '',
              name: pickStr(p, ['plantName', 'name']) || 'Growatt Solar Plant',
            }))
            .filter((p) => Boolean(p.id));
          break;
        }
        if (json?.back?.msg) {
          lastError = `Growatt ShineServer: ${json.back.msg}`;
        }
      } catch {
        // Try next region/hash variant
      }
    }
    if (loggedIn) break;
  }

  if (!loggedIn) {
    return { ok: false, brand: 'growatt', providerName: 'Growatt ShineServer', error: lastError };
  }

  // Fetch plant list if login response did not inline it
  if (plantItems.length === 0) {
    try {
      const plResp = await portalFetch(`${activeBase}/PlantListAPI.do`, {
        method: 'GET',
        headers: { Cookie: cookieJar },
      });
      cookieJar = mergeCookieHeader(cookieJar, extractSetCookies(plResp));
      const plJson = (await plResp.json().catch(() => null)) as {
        back?: { data?: Array<Record<string, unknown>> };
      } | null;
      const arr = Array.isArray(plJson?.back?.data) ? plJson.back.data : [];
      plantItems = arr
        .map((p) => ({
          id: pickStr(p, ['plantId', 'id']) || '',
          name: pickStr(p, ['plantName', 'name']) || 'Growatt Solar Plant',
        }))
        .filter((p) => Boolean(p.id));
    } catch {
      // Ignore
    }
  }

  const candidateIds = params.stationId
    ? [params.stationId]
    : plantItems.map((p) => p.id).slice(0, 8);

  if (candidateIds.length === 0) {
    return {
      ok: false,
      brand: 'growatt',
      providerName: 'Growatt ShineServer',
      error: 'Signed in to Growatt ShineServer, but no plants were found under this account.',
    };
  }

  let chosenPlantId = candidateIds[0];
  let chosenDevice: Record<string, unknown> | null = null;
  let chosenPlantData: Record<string, unknown> | null = null;
  let matchedInvSn: string | undefined;
  let matchedLogSn: string | undefined;
  let serialMatchVerified = false;
  const discovered: DiscoveredCloudPlant[] = [];

  for (const pid of candidateIds) {
    let devices: Array<Record<string, unknown>> = [];
    let plantSummary: Record<string, unknown> | null = null;
    try {
      const devResp = await portalFetch(
        `${activeBase}/newPlantAPI.do?op=getAllDeviceList&plantId=${encodeURIComponent(pid)}&pageNum=1&pageSize=20`,
        { method: 'GET', headers: { Cookie: cookieJar } }
      );
      const devJson = (await devResp.json().catch(() => null)) as {
        deviceList?: Array<Record<string, unknown>>;
        plantData?: Record<string, unknown>;
      } | null;
      devices = Array.isArray(devJson?.deviceList) ? devJson.deviceList : [];
      plantSummary = devJson?.plantData || null;
    } catch {
      // Continue
    }

    let stationInvSn: string | undefined;
    let stationLogSn: string | undefined;
    let matchedHere = false;

    for (const dev of devices) {
      const sn = pickStr(dev, ['deviceSn', 'sn', 'alias']);
      const logSn = pickStr(dev, ['datalogSn', 'datalog_sn', 'loggerSn']);
      if (!stationInvSn && sn) stationInvSn = sn;
      if (!stationLogSn && logSn) stationLogSn = logSn;

      const invMatch = params.inverterSerial ? serialsMatch(params.inverterSerial, sn) : false;
      const logMatch = params.loggerSerial ? serialsMatch(params.loggerSerial, logSn) : false;

      if (invMatch || logMatch) {
        matchedHere = true;
        chosenPlantId = pid;
        chosenDevice = dev;
        chosenPlantData = plantSummary;
        matchedInvSn = sn;
        matchedLogSn = logSn;
        serialMatchVerified =
          (!params.inverterSerial || invMatch) && (!params.loggerSerial || logMatch);
        break;
      }
    }

    discovered.push({
      stationId: pid,
      plantName:
        plantItems.find((p) => p.id === pid)?.name ||
        pickStr(plantSummary, ['plantName']) ||
        `Growatt Plant ${pid}`,
      capacityKwp: toKwSmart(pickNum(plantSummary, ['nominalPower']), 'w'),
      inverterSerial: stationInvSn,
      loggerSerial: stationLogSn,
    });

    if (matchedHere) break;
    if (!chosenDevice && devices.length > 0) {
      chosenPlantId = pid;
      chosenDevice = devices[0];
      chosenPlantData = plantSummary;
      matchedInvSn = stationInvSn;
      matchedLogSn = stationLogSn;
    }
  }

  if (
    !params.stationId &&
    !serialMatchVerified &&
    discovered.length > 1 &&
    !params.inverterSerial &&
    !params.loggerSerial
  ) {
    return {
      ok: false,
      brand: 'growatt',
      detectedBrand: 'growatt',
      providerName: 'Growatt ShineServer',
      requiresPlantSelection: true,
      discoveredPlants: discovered,
      message: `Found ${discovered.length} Growatt plants on your account. Select the plant to sync.`,
    };
  }

  // Pull detailed inverter telemetry if we have deviceSn
  let invDetail: Record<string, unknown> = {};
  const deviceSn = matchedInvSn || params.inverterSerial;
  if (deviceSn) {
    try {
      const dResp = await portalFetch(
        `${activeBase}/newInverterAPI.do?op=getInverterData&id=${encodeURIComponent(deviceSn)}`,
        { method: 'GET', headers: { Cookie: cookieJar } }
      );
      const dJson = (await dResp.json().catch(() => null)) as Record<string, unknown> | null;
      if (dJson && typeof dJson === 'object') {
        invDetail = (dJson.obj as Record<string, unknown>) || dJson;
      }
    } catch {
      // Fall back to device summary
    }
  }

  const stamp = toIstStamp();
  const merged = { ...(chosenPlantData || {}), ...(chosenDevice || {}), ...invDetail };
  const livePowerKw =
    toKwSmart(pickNum(merged, ['pac', 'power', 'currentPower', 'ppv'])) ?? 0;
  const todayGenKwh =
    pickNum(merged, ['eToday', 'energyToday', 'todayEnergy', 'e_today']) ?? 0;
  const monthGenKwh = pickNum(merged, ['eMonth', 'energyMonth']);
  const lifetimeKwh = pickNum(merged, ['eTotal', 'energyTotal', 'totalEnergy']);
  const todayUsageKwh = pickNum(merged, ['elocalLoadToday', 'loadToday', 'eLoadToday']);
  const todayExportKwh = pickNum(merged, ['etoGridToday', 'eToGridToday', 'gridSellToday']);
  const todayImportKwh = pickNum(merged, ['etoUserToday', 'eToUserToday', 'gridBuyToday']);
  const hasSmartMeter =
    todayUsageKwh !== undefined || todayExportKwh !== undefined || todayImportKwh !== undefined;

  const pvStrings: InverterPvStringReading[] = [];
  for (let i = 1; i <= 4; i++) {
    const v = pickNum(merged, [`vpv${i}`]);
    const a = pickNum(merged, [`ipv${i}`]);
    const w = pickNum(merged, [`ppv${i}`]) ?? (v !== undefined && a !== undefined ? Math.round(v * a) : undefined);
    if ((v ?? 0) > 0 || (a ?? 0) > 0 || (w ?? 0) > 0) {
      pvStrings.push({ id: `PV${i}`, voltageV: v, currentA: a, powerW: w });
    }
  }

  const isLost = merged.lost === true || merged.lost === 'true' || String(merged.deviceStatus) === '-1';
  const inverterStatus: InverterExtendedTelemetry['inverterStatus'] = isLost
    ? 'offline'
    : String(merged.deviceStatus) === '3'
      ? 'fault'
      : livePowerKw > 0
        ? 'online'
        : 'standby';

  const extendedTelemetry = compactExtendedTelemetry({
    inverterStatus,
    inverterStatusText:
      inverterStatus === 'online'
        ? 'Normal'
        : inverterStatus === 'standby'
          ? 'Waiting / Standby'
          : inverterStatus === 'fault'
            ? 'Fault'
            : 'Offline',
    inverterModel: pickStr(merged, ['deviceModel', 'model', 'deviceTypeName']),
    firmwareVersion: pickStr(merged, ['fwVersion']),
    loggerStatus: isLost ? 'offline' : 'online',
    serialMatchVerified,
    matchedInverterSerial: matchedInvSn,
    matchedLoggerSerial: matchedLogSn,
    inverterTempC: pickNum(merged, ['temperature', 'temp1', 'invTemperature']),
    gridVoltageV: pickNum(merged, ['vacr', 'vac1', 'vGrid']),
    gridVoltageR: pickNum(merged, ['vacr', 'vac1']),
    gridVoltageS: pickNum(merged, ['vacs', 'vac2']),
    gridVoltageT: pickNum(merged, ['vact', 'vac3']),
    acCurrentA: pickNum(merged, ['iacr', 'iac1']),
    gridFrequencyHz: pickNum(merged, ['fac', 'gridFrequency']),
    monthGenKwh,
    batterySocPct: pickNum(merged, ['soc', 'batterySoc']),
    batteryVoltageV: pickNum(merged, ['vBat', 'batteryVoltage']),
    pvStrings,
    portalRegion: new URL(activeBase).hostname,
  });

  return {
    ok: true,
    brand: 'growatt',
    detectedBrand: 'growatt',
    providerName: 'Growatt ShineServer',
    detectedFormat: 'growatt_cloud_login',
    detectedStationId: chosenPlantId,
    detectedPlantName:
      plantItems.find((p) => p.id === chosenPlantId)?.name ||
      pickStr(merged, ['plantName']) ||
      'Growatt Solar Plant',
    detectedInverterSerial: matchedInvSn,
    detectedLoggerSerial: matchedLogSn,
    serialMatchVerified,
    detectedModelName: pickStr(merged, ['deviceModel', 'model']),
    detectedCapacityKwp: toKwSmart(pickNum(merged, ['nominalPower', 'nominal_Power']), 'w'),
    message: `Synced live Growatt ShineServer telemetry${serialMatchVerified ? ' (Inverter & Logger verified)' : ''}`,
    telemetry: {
      dateKey: stamp.dateKey,
      todayGenKwh: round2(Math.max(0, todayGenKwh)),
      livePowerKw: round2(Math.max(0, livePowerKw)),
      ...(todayUsageKwh !== undefined ? { todayUsageKwh: round2(Math.max(0, todayUsageKwh)) } : {}),
      ...(todayExportKwh !== undefined ? { todayExportKwh: round2(Math.max(0, todayExportKwh)) } : {}),
      ...(todayImportKwh !== undefined ? { todayImportKwh: round2(Math.max(0, todayImportKwh)) } : {}),
      ...(lifetimeKwh !== undefined ? { lifetimeKwh: Number(Math.max(0, lifetimeKwh).toFixed(1)) } : {}),
      hasSmartMeter,
      syncedAtIso: stamp.iso,
      syncedAtIst: stamp.ist,
      statusNote: `Growatt Cloud · ${matchedInvSn || chosenPlantId}`,
    },
    extendedTelemetry,
  };
}

// ============================================================================
// 3. SOLISCLOUD (Direct Web Portal Login at www.soliscloud.com + Official API)
// ============================================================================
interface SolisWebClientConfig {
  prefix: string;
  webKey: string;
  version: string;
  fetchedAtMs: number;
}

let solisWebConfigCache: SolisWebClientConfig | null = null;
const SOLIS_WEB_CONFIG_TTL_MS = 12 * 60 * 60 * 1000;

async function getSolisWebClientConfig(forceRefresh = false): Promise<SolisWebClientConfig> {
  if (
    !forceRefresh &&
    solisWebConfigCache &&
    Date.now() - solisWebConfigCache.fetchedAtMs < SOLIS_WEB_CONFIG_TTL_MS
  ) {
    return solisWebConfigCache;
  }

  const loginHtmlResp = await portalFetch('https://www.soliscloud.com/login', {
    method: 'GET',
    headers: { Accept: 'text/html,application/xhtml+xml,*/*' },
  });
  const html = await loginHtmlResp.text();
  const jsMatch = html.match(/https:\/\/ui-cdn\.soliscloud\.com[^"'<>]*?\/index-[A-Za-z0-9_-]+\.js/);
  if (!jsMatch || !jsMatch[0]) {
    throw new Error('Could not load SolisCloud web portal bundle.');
  }

  // Strictly validated via portalFetch -> assertAllowedPortalUrl (soliscloud.com HTTPS only)
  const bundleResp = await portalFetch(jsMatch[0], { method: 'GET' }, 12_000);
  const bundleTxt = await bundleResp.text();

  const prefixMatch = bundleTxt.match(/"(WEB \d+:)"\+/);
  const kyIdx = bundleTxt.search(/"WEB \d+:"\+/);
  const keyWindow = kyIdx > 0 ? bundleTxt.slice(Math.max(0, kyIdx - 6000), kyIdx + 120) : '';
  const keyArrMatches = [
    ...keyWindow.matchAll(/=\[("[A-Za-z0-9+/=]{16,}"(?:,"[A-Za-z0-9+/=]{16,}")+)\]/g),
  ];
  const verMatch = bundleTxt.match(/Version:"([0-9.]+)"/);

  if (!prefixMatch || keyArrMatches.length === 0) {
    throw new Error('Could not initialize SolisCloud web portal handshake.');
  }

  let webKey = '';
  for (let i = keyArrMatches.length - 1; i >= 0; i--) {
    try {
      const rawChunks = JSON.parse(`[${keyArrMatches[i][1]}]`) as string[];
      const decoded = rawChunks.map((chunk) => Buffer.from(chunk, 'base64').toString('utf8')).join('');
      if (/^[0-9a-fA-F]{24,64}$/.test(decoded)) {
        webKey = decoded;
        break;
      }
    } catch {
      // Try next candidate
    }
  }

  if (!webKey) {
    throw new Error('Invalid SolisCloud web portal handshake parameters.');
  }

  solisWebConfigCache = {
    prefix: prefixMatch[1],
    webKey,
    version: verMatch?.[1] || '5.3.121',
    fetchedAtMs: Date.now(),
  };
  return solisWebConfigCache;
}

interface SolisWebSession {
  config: SolisWebClientConfig;
  deviceId: string;
  cookieJar: string;
  csrfToken?: string;
}

function extractCookieValue(cookieJar: string, names: string[]): string | undefined {
  for (const part of cookieJar.split(';')) {
    const trimmed = part.trim();
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const k = trimmed.slice(0, eq).trim();
    const v = trimmed.slice(eq + 1).trim();
    if (v && names.some((n) => n.toLowerCase() === k.toLowerCase())) {
      return v;
    }
  }
  return undefined;
}

async function solisWebPost(
  session: SolisWebSession,
  apiPath: string,
  bodyObj: Record<string, unknown>
): Promise<{ ok: boolean; status: number; json: Record<string, unknown> | null; rawText: string }> {
  const cleanPayload: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(bodyObj)) {
    if (v !== undefined && v !== null && v !== '') cleanPayload[k] = v;
  }
  cleanPayload.localTime = Date.now();
  cleanPayload.localTimeZone = 5.5;
  cleanPayload.language = '2';

  const bodyStr = JSON.stringify(cleanPayload);
  const contentMd5 = crypto.createHash('md5').update(bodyStr).digest('base64');
  const gmtDate = new Date().toUTCString();
  const canonical = `POST\n${contentMd5}\napplication/json\n${gmtDate}\n${apiPath}`;
  const signature = crypto
    .createHmac('sha1', session.config.webKey)
    .update(canonical)
    .digest('base64');

  const headers: Record<string, string> = {
    'Content-Type': 'application/json;charset=UTF-8',
    'Content-MD5': contentMd5,
    Authorization: `${session.config.prefix}${signature}`,
    Time: gmtDate,
    'X-Cloud-Platform': 'GLY',
    language: '2',
    'Device-Id': session.deviceId,
    Version: session.config.version,
    platform: 'Web',
    Origin: 'https://www.soliscloud.com',
    Referer: 'https://www.soliscloud.com/overview/plantStation',
  };
  if (session.cookieJar) {
    headers.Cookie = session.cookieJar;
  }
  if (session.csrfToken) {
    headers.token = session.csrfToken;
  }

  const resp = await portalFetch(`https://www.soliscloud.com/api${apiPath}`, {
    method: 'POST',
    headers,
    body: bodyStr,
  });

  const headerToken =
    resp.headers.get('token') ||
    resp.headers.get('csrfToken') ||
    resp.headers.get('x-token') ||
    '';
  if (headerToken.trim() && !session.csrfToken) {
    session.csrfToken = headerToken.trim();
  }

  const setCookies = extractSetCookies(resp);
  if (setCookies) {
    session.cookieJar = mergeCookieHeader(session.cookieJar, setCookies);
    if (!session.csrfToken) {
      const cookieToken = extractCookieValue(session.cookieJar, ['token', 'csrfToken', 'X-Token']);
      if (cookieToken) {
        session.csrfToken = cookieToken;
      }
    }
  }

  const rawText = await resp.text();
  let json: Record<string, unknown> | null = null;
  try {
    json = JSON.parse(rawText) as Record<string, unknown>;
  } catch {
    json = null;
  }
  return { ok: resp.ok, status: resp.status, json, rawText };
}

async function solisSignedPost(
  apiBase: string,
  apiPath: string,
  bodyObj: Record<string, unknown>,
  keyId: string,
  keySecret: string
): Promise<{ ok: boolean; status: number; json: Record<string, unknown> | null }> {
  const reqBodyStr = JSON.stringify(bodyObj);
  const contentMd5 = crypto.createHash('md5').update(reqBodyStr).digest('base64');
  const gmtDate = new Date().toUTCString();
  const canonical = `POST\n${contentMd5}\napplication/json\n${gmtDate}\n${apiPath}`;
  const signature = crypto.createHmac('sha1', keySecret).update(canonical).digest('base64');

  const resp = await portalFetch(`${apiBase}${apiPath}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json;charset=UTF-8',
      'Content-MD5': contentMd5,
      Date: gmtDate,
      Authorization: `API ${keyId}:${signature}`,
    },
    body: reqBodyStr,
  });
  const json = (await resp.json().catch(() => null)) as Record<string, unknown> | null;
  return { ok: resp.ok, status: resp.status, json };
}

function looksLikeSolisKeyId(val: string): boolean {
  return /^\d{15,24}$/.test(val.trim());
}

function extractSolisRecords(payload: unknown): Array<Record<string, unknown>> {
  if (!payload || typeof payload !== 'object') return [];
  if (Array.isArray(payload)) return payload as Array<Record<string, unknown>>;
  const root = payload as Record<string, unknown>;
  if (Array.isArray(root.records)) return root.records as Array<Record<string, unknown>>;
  if (Array.isArray(root.list)) return root.list as Array<Record<string, unknown>>;
  const page = root.page as Record<string, unknown> | undefined;
  if (page && Array.isArray(page.records)) return page.records as Array<Record<string, unknown>>;
  if (page && Array.isArray(page.list)) return page.list as Array<Record<string, unknown>>;
  const invPage = root.inverterPage as Record<string, unknown> | undefined;
  if (invPage && Array.isArray(invPage.records)) {
    return invPage.records as Array<Record<string, unknown>>;
  }
  const stationPage = root.stationPage as Record<string, unknown> | undefined;
  if (stationPage && Array.isArray(stationPage.records)) {
    return stationPage.records as Array<Record<string, unknown>>;
  }
  return [];
}

function buildSolisTelemetryResponse(opts: {
  inverterData: Record<string, unknown>;
  matchedInvSn?: string;
  matchedLogSn?: string;
  chosenStationId?: string;
  serialMatchVerified: boolean;
  loggerSignalPct?: number;
  loggerOnline?: boolean;
  historicalDailyLogs: NonNullable<CloudInverterSyncResponse['historicalDailyLogs']>;
  detectedFormat: string;
}): CloudInverterSyncResponse {
  const {
    inverterData: d,
    matchedInvSn,
    matchedLogSn,
    chosenStationId,
    serialMatchVerified,
    loggerSignalPct,
    loggerOnline,
    historicalDailyLogs,
    detectedFormat,
  } = opts;

  const stamp = toIstStamp();
  const pacRaw = pickNum(d, ['pac', 'power', 'currentPower']) ?? 0;
  const pacUnit = pickStr(d, ['pacStr', 'powerStr']);
  const livePowerKw = toKwSmart(pacRaw, pacUnit || 'kw') ?? 0;
  const todayGenKwh = pickNum(d, ['eToday', 'dayEnergy', 'dayEnergy1']) ?? 0;
  const monthGenKwh = pickNum(d, ['eMonth', 'monthEnergy', 'monthEnergy1']);
  const yearGenKwh = pickNum(d, ['eYear', 'yearEnergy', 'yearEnergy1']);
  const lifetimeKwh = pickNum(d, ['eTotal', 'allEnergy', 'allEnergy1']);
  const todayUsageKwh = pickNum(d, ['homeLoadTodayEnergy', 'familyLoadPowerToday', 'homeLoadEnergy']);
  const todayExportKwh = pickNum(d, ['gridSellTodayEnergy', 'gridSellEnergy']);
  const todayImportKwh = pickNum(d, ['gridPurchasedTodayEnergy', 'gridPurchasedEnergy']);
  const hasSmartMeter =
    todayUsageKwh !== undefined || todayExportKwh !== undefined || todayImportKwh !== undefined;

  const pvStrings: InverterPvStringReading[] = [];
  for (let i = 1; i <= 4; i++) {
    const v = pickNum(d, [`uPv${i}`]);
    const a = pickNum(d, [`iPv${i}`]);
    const w =
      pickNum(d, [`pow${i}`]) ?? (v !== undefined && a !== undefined ? Math.round(v * a) : undefined);
    if ((v ?? 0) > 0 || (a ?? 0) > 0) {
      pvStrings.push({ id: `PV${i}`, voltageV: v, currentA: a, powerW: w });
    }
  }

  const stateNum = pickNum(d, ['state', 'inverterState']);
  const inverterStatus: InverterExtendedTelemetry['inverterStatus'] =
    stateNum === 1
      ? 'online'
      : stateNum === 2
        ? 'offline'
        : stateNum === 3
          ? 'fault'
          : stateNum === 4
            ? 'standby'
            : livePowerKw > 0
              ? 'online'
              : 'offline';

  const inverterStatusText =
    inverterStatus === 'online'
      ? 'Online'
      : inverterStatus === 'offline'
        ? loggerOnline === true
          ? 'Offline (No Sun / Standby) · Logger Online'
          : 'Offline / Standby'
        : inverterStatus === 'standby'
          ? 'Standby'
          : inverterStatus === 'fault'
            ? 'Alarm / Fault'
            : 'Synced';

  const extendedTelemetry = compactExtendedTelemetry({
    inverterStatus,
    inverterStatusText,
    inverterModel: pickStr(d, ['model', 'productModel', 'machine', 'inverterType']),
    firmwareVersion: pickStr(d, ['version', 'firmwareVersion', 'inverterSoftwareVersion']),
    loggerStatus:
      loggerOnline === true
        ? 'online'
        : loggerOnline === false
          ? 'offline'
          : inverterStatus === 'online'
            ? 'online'
            : 'unknown',
    loggerSignalPct,
    serialMatchVerified,
    matchedInverterSerial: matchedInvSn,
    matchedLoggerSerial: matchedLogSn,
    inverterTempC: pickNum(d, ['inverterTemperature', 'temperature']),
    gridVoltageV: pickNum(d, ['uAc1']),
    gridVoltageR: pickNum(d, ['uAc1']),
    gridVoltageS: pickNum(d, ['uAc2']),
    gridVoltageT: pickNum(d, ['uAc3']),
    acCurrentA: pickNum(d, ['iAc1']),
    gridFrequencyHz: pickNum(d, ['fac']),
    powerFactor: pickNum(d, ['powerFactor']),
    monthGenKwh,
    yearGenKwh,
    batterySocPct: pickNum(d, ['batteryCapacitySoc']),
    batteryPowerKw: toKwSmart(
      pickNum(d, ['batteryPower']),
      pickStr(d, ['batteryPowerStr']) || 'kw'
    ),
    batteryVoltageV: pickNum(d, ['batteryVoltage']),
    todayBatteryChargeKwh: pickNum(d, ['batteryTodayChargeEnergy']),
    todayBatteryDischargeKwh: pickNum(d, ['batteryTodayDischargeEnergy']),
    pvStrings,
    faultMessage: stateNum === 3 ? pickStr(d, ['alarmMsg', 'currentState']) : undefined,
    portalRegion: 'www.soliscloud.com',
  });

  const capacityRaw = pickNum(d, ['capacity', 'power', 'dcInputPower']);
  const capacityUnit = pickStr(d, ['capacityStr', 'powerStr']);
  const detectedCapacityKwp =
    capacityRaw !== undefined
      ? toKwSmart(capacityRaw, capacityUnit || (capacityRaw > 500 ? 'w' : 'kw'))
      : undefined;

  const statusTag =
    inverterStatus === 'offline' && loggerOnline === true
      ? 'Plant Offline (No Sun) · Logger Online'
      : inverterStatus === 'offline'
        ? 'Plant Offline / Standby'
        : 'Live';

  return {
    ok: true,
    brand: 'soliscloud',
    detectedBrand: 'soliscloud',
    providerName: 'SolisCloud',
    detectedFormat,
    detectedStationId: chosenStationId,
    detectedPlantName: pickStr(d, ['stationName', 'sno']) || 'SolisCloud Plant',
    detectedInverterSerial: matchedInvSn,
    detectedLoggerSerial: matchedLogSn,
    serialMatchVerified,
    detectedModelName: pickStr(d, ['model', 'productModel', 'machine']),
    detectedCapacityKwp,
    message: `Synced SolisCloud (${statusTag})${serialMatchVerified ? ' · Inverter & Logger verified' : ''}`,
    telemetry: {
      dateKey: stamp.dateKey,
      todayGenKwh: round2(Math.max(0, todayGenKwh)),
      livePowerKw: round2(Math.max(0, livePowerKw)),
      ...(todayUsageKwh !== undefined ? { todayUsageKwh: round2(Math.max(0, todayUsageKwh)) } : {}),
      ...(todayExportKwh !== undefined
        ? { todayExportKwh: round2(Math.max(0, todayExportKwh)) }
        : {}),
      ...(todayImportKwh !== undefined
        ? { todayImportKwh: round2(Math.max(0, todayImportKwh)) }
        : {}),
      ...(lifetimeKwh !== undefined
        ? { lifetimeKwh: Number(Math.max(0, lifetimeKwh).toFixed(1)) }
        : {}),
      hasSmartMeter,
      syncedAtIso: stamp.iso,
      syncedAtIst: stamp.ist,
      statusNote: `SolisCloud ${statusTag} · ${matchedInvSn || matchedLogSn || chosenStationId || 'Synced'}`,
    },
    extendedTelemetry,
    historicalDailyLogs: historicalDailyLogs.length > 0 ? historicalDailyLogs.slice(-30) : undefined,
  };
}

async function syncSolisCloudWebLogin(params: PortalSyncParams): Promise<CloudInverterSyncResponse> {
  const config = await getSolisWebClientConfig();
  const session: SolisWebSession = {
    config,
    deviceId: crypto.randomBytes(32).toString('hex'),
    cookieJar: '',
  };

  const md5Pwd = crypto.createHash('md5').update(params.password.trim(), 'utf8').digest('hex');

  let loginRes = await solisWebPost(session, '/user/login2', {
    userInfo: params.username.trim(),
    passWord: md5Pwd,
    yingZhenType: 1,
  });

  // If SolisCloud rotated its web signing key, refresh once and retry
  if (loginRes.status === 401 || loginRes.status === 403 || !loginRes.json) {
    session.config = await getSolisWebClientConfig(true);
    loginRes = await solisWebPost(session, '/user/login2', {
      userInfo: params.username.trim(),
      passWord: md5Pwd,
      yingZhenType: 1,
    });
  }

  const loginCode = String(loginRes.json?.code ?? '');
  if (!loginRes.ok || loginCode !== '0') {
    const serverMsg = String(loginRes.json?.msg || '').trim();
    if (loginCode === '3' || loginCode === '4' || loginCode === '5') {
      return {
        ok: false,
        brand: 'soliscloud',
        providerName: 'SolisCloud',
        requiresApiCredentialsHint: true,
        error: `SolisCloud requested an account verification code (${serverMsg || '2-step verification'}). Sign in once on www.soliscloud.com to trust your account, or switch to API Integration and enter your KeyID & KeySecret.`,
      };
    }
    return {
      ok: false,
      brand: 'soliscloud',
      providerName: 'SolisCloud',
      error: serverMsg
        ? `SolisCloud login failed: ${serverMsg}`
        : `SolisCloud login failed (HTTP ${loginRes.status}). Verify your www.soliscloud.com username/email and password.`,
    };
  }

  const loginData = (loginRes.json?.data as Record<string, unknown>) || {};
  const csrfToken =
    pickStr(loginRes.json, ['csrfToken', 'token']) ||
    pickStr(loginData, ['csrfToken', 'token', 'accessToken']) ||
    extractCookieValue(session.cookieJar, ['token', 'csrfToken', 'X-Token']);
  if (csrfToken) {
    session.csrfToken = csrfToken;
  }

  // Step 2: Query ALL stations, inverters, and data loggers (stationType: '0' includes offline/nighttime plants!)
  const [stationRes, invListRes, collectorListRes] = await Promise.all([
    solisWebPost(session, '/station/list', {
      pageNo: 1,
      pageSize: 30,
      stationType: '0',
    }).catch(() => ({ ok: false, status: 0, json: null, rawText: '' })),
    solisWebPost(session, '/inverter/listV2', {
      pageNo: 1,
      pageSize: 30,
      stationType: '0',
      ...(params.stationId ? { stationId: params.stationId } : {}),
    }).catch(() => ({ ok: false, status: 0, json: null, rawText: '' })),
    solisWebPost(session, '/collector/listV2', {
      pageNo: 1,
      pageSize: 30,
      ...(params.stationId ? { stationId: params.stationId } : {}),
    }).catch(() => ({ ok: false, status: 0, json: null, rawText: '' })),
  ]);

  let stationRecords = extractSolisRecords(stationRes.json?.data);
  let invRecords = extractSolisRecords(invListRes.json?.data);
  let collectorRecords = extractSolisRecords(collectorListRes.json?.data);

  // If /station/list returned empty with stationType='0', retry without stationType filter
  if (stationRecords.length === 0) {
    const stFallback = await solisWebPost(session, '/station/list', {
      pageNo: 1,
      pageSize: 30,
    }).catch(() => ({ ok: false, status: 0, json: null, rawText: '' }));
    stationRecords = extractSolisRecords(stFallback.json?.data);
  }
  if (stationRecords.length === 0) {
    const stV2 = await solisWebPost(session, '/station/listV2', {
      pageNo: 1,
      pageSize: 30,
    }).catch(() => ({ ok: false, status: 0, json: null, rawText: '' }));
    stationRecords = extractSolisRecords(stV2.json?.data);
  }

  // If /inverter/listV2 returned empty, query per-station inverters
  if (invRecords.length === 0 && stationRecords.length > 0) {
    for (const st of stationRecords.slice(0, 5)) {
      const stId = pickStr(st, ['id', 'stationId']);
      if (!stId) continue;
      const stInvRes = await solisWebPost(session, '/inverter/listV2', {
        pageNo: 1,
        pageSize: 20,
        stationId: stId,
      }).catch(() => ({ ok: false, status: 0, json: null, rawText: '' }));
      const recs = extractSolisRecords(stInvRes.json?.data);
      if (recs.length > 0) {
        invRecords = invRecords.concat(recs);
      }
    }
  }

  // If all three endpoints returned an auth/API error code (not just empty list), surface exact server message
  if (invRecords.length === 0 && stationRecords.length === 0 && collectorRecords.length === 0) {
    const apiErr =
      pickStr(invListRes.json, ['msg', 'message']) ||
      pickStr(stationRes.json, ['msg', 'message']) ||
      pickStr(collectorListRes.json, ['msg', 'message']);
    const apiStatus = invListRes.status || stationRes.status || collectorListRes.status;
    return {
      ok: false,
      brand: 'soliscloud',
      providerName: 'SolisCloud',
      error: apiErr
        ? `Signed in to www.soliscloud.com, but SolisCloud returned: ${apiErr} (HTTP ${apiStatus}).`
        : 'Signed in to www.soliscloud.com successfully, but no inverter, plant, or data logger was returned for this account.',
    };
  }

  // Match by Inverter S/N or Logger (Collector) S/N across inverters, collectors, and stations
  const matchedInv = invRecords.find((rec) => {
    const sn = pickStr(rec, ['sn', 'inverterSn']);
    const col = pickStr(rec, ['collectorSn', 'collectorsn', 'dataloggerSn']);
    return (
      (params.inverterSerial && serialsMatch(params.inverterSerial, sn)) ||
      (params.loggerSerial && serialsMatch(params.loggerSerial, col))
    );
  });

  const matchedCol = collectorRecords.find((c) => {
    const colSn = pickStr(c, ['sn', 'collectorSn']);
    return params.loggerSerial ? serialsMatch(params.loggerSerial, colSn) : false;
  });

  const matchedStation =
    (matchedInv
      ? stationRecords.find(
          (st) => pickStr(st, ['id', 'stationId']) === pickStr(matchedInv, ['stationId'])
        )
      : undefined) ||
    (matchedCol
      ? stationRecords.find(
          (st) => pickStr(st, ['id', 'stationId']) === pickStr(matchedCol, ['stationId'])
        )
      : undefined) ||
    (params.stationId
      ? stationRecords.find((st) => pickStr(st, ['id', 'stationId']) === params.stationId)
      : undefined) ||
    stationRecords[0];

  if (
    !matchedInv &&
    !matchedCol &&
    invRecords.length > 1 &&
    !params.stationId &&
    !params.inverterSerial &&
    !params.loggerSerial
  ) {
    return {
      ok: false,
      brand: 'soliscloud',
      detectedBrand: 'soliscloud',
      providerName: 'SolisCloud',
      requiresPlantSelection: true,
      discoveredPlants: invRecords.map((rec) => ({
        stationId: pickStr(rec, ['stationId', 'id']) || '',
        plantName: pickStr(rec, ['stationName', 'sno']) || 'SolisCloud Plant',
        capacityKwp: pickNum(rec, ['power', 'capacity']),
        inverterSerial: pickStr(rec, ['sn', 'inverterSn']),
        loggerSerial: pickStr(rec, ['collectorSn', 'collectorsn']),
        status:
          String(rec.state) === '1'
            ? 'Online'
            : String(rec.state) === '2'
              ? 'Offline'
              : 'Alarm',
      })),
      message: `Found ${invRecords.length} SolisCloud inverters on your account. Select the plant to sync.`,
    };
  }

  // Merge station summary + inverter summary so offline plants still carry plantName, capacity, and totals
  const chosenInv = matchedInv || invRecords[0];
  let inverterData: Record<string, unknown> = {
    ...(matchedStation || {}),
    ...(chosenInv || {}),
  };

  const invId = pickStr(chosenInv, ['id', 'inverterId']) || pickStr(matchedStation, ['inverterId']);
  let matchedInvSn =
    pickStr(chosenInv, ['sn', 'inverterSn']) ||
    pickStr(matchedStation, ['inverterSn']) ||
    params.inverterSerial;
  let matchedLogSn =
    pickStr(chosenInv, ['collectorSn', 'collectorsn', 'dataloggerSn']) ||
    pickStr(matchedCol, ['sn', 'collectorSn']) ||
    params.loggerSerial;
  let chosenStationId =
    pickStr(chosenInv, ['stationId']) ||
    pickStr(matchedCol, ['stationId']) ||
    pickStr(matchedStation, ['id', 'stationId']) ||
    params.stationId;

  // Step 3: Fetch full inverter telemetry via /inverter/detail (works even when inverter is offline/nighttime!)
  if (invId || matchedInvSn) {
    try {
      const detRes = await solisWebPost(session, '/inverter/detail', {
        ...(invId ? { id: invId } : {}),
        ...(matchedInvSn ? { sn: matchedInvSn } : {}),
      });
      if (
        detRes.ok &&
        String(detRes.json?.code) === '0' &&
        detRes.json?.data &&
        typeof detRes.json.data === 'object'
      ) {
        const detData = detRes.json.data as Record<string, unknown>;
        inverterData = { ...inverterData, ...detData };
        matchedInvSn = pickStr(detData, ['sn', 'inverterSn']) || matchedInvSn;
        matchedLogSn = pickStr(detData, ['collectorSn', 'collectorsn']) || matchedLogSn;
        chosenStationId = pickStr(detData, ['stationId']) || chosenStationId;
      }
    } catch {
      // Fallback to list summary fields
    }
  }

  // Also enrich from /station/detailMix if stationId is known (gives plant-level eToday, eMonth, eTotal, capacity even when inverter is offline!)
  if (chosenStationId) {
    try {
      const stDetRes = await solisWebPost(session, '/station/detailMix', {
        id: chosenStationId,
        needCheckSingleInverter: false,
      });
      if (
        stDetRes.ok &&
        String(stDetRes.json?.code) === '0' &&
        stDetRes.json?.data &&
        typeof stDetRes.json.data === 'object'
      ) {
        // Keep inverter-specific fields on top while filling missing station fields (stationName, capacity, dayEnergy, allEnergy)
        inverterData = { ...(stDetRes.json.data as Record<string, unknown>), ...inverterData };
      }
    } catch {
      // Optional station mix enrichment
    }
  }

  // Step 4: Verify Data Logger status & RSSI signal strength (works when logger is online while inverter is offline!)
  let loggerSignalPct: number | undefined;
  let loggerOnline: boolean | undefined;

  if (collectorRecords.length === 0 && chosenStationId) {
    try {
      const colRes = await solisWebPost(session, '/collector/listV2', {
        pageNo: 1,
        pageSize: 20,
        stationId: chosenStationId,
      });
      collectorRecords = extractSolisRecords(colRes.json?.data);
    } catch {
      // Optional collector diagnostics
    }
  }

  const colMatch =
    matchedCol ||
    collectorRecords.find((c) => serialsMatch(matchedLogSn || params.loggerSerial, pickStr(c, ['sn']))) ||
    collectorRecords[0];

  if (colMatch) {
    matchedLogSn = pickStr(colMatch, ['sn', 'collectorSn']) || matchedLogSn;
    const rssi = pickNum(colMatch, ['rssi', 'rssiLevel', 'signal']);
    if (rssi !== undefined) {
      loggerSignalPct =
        rssi < 0
          ? Math.max(0, Math.min(100, Math.round((rssi + 100) * 2)))
          : Math.min(100, Math.round(rssi));
    }
    const cState = pickNum(colMatch, ['state']);
    if (cState !== undefined) {
      loggerOnline = cState === 1;
    }
  }

  const serialMatchVerified =
    (!params.inverterSerial || serialsMatch(params.inverterSerial, matchedInvSn)) &&
    (!params.loggerSerial || serialsMatch(params.loggerSerial, matchedLogSn));

  // Step 5: Pull current month's daily generation logs via /chart/inverter/month
  const stamp = toIstStamp();
  const historicalDailyLogs: NonNullable<CloudInverterSyncResponse['historicalDailyLogs']> = [];
  if (invId || matchedInvSn) {
    try {
      const monthStr = stamp.dateKey.slice(0, 7);
      const mRes = await solisWebPost(session, '/chart/inverter/month', {
        ...(invId ? { id: invId } : {}),
        ...(matchedInvSn ? { sn: matchedInvSn } : {}),
        month: monthStr,
        money: 'INR',
      });
      const rawData = mRes.json?.data;
      const days = Array.isArray(rawData)
        ? (rawData as Array<Record<string, unknown>>)
        : rawData && typeof rawData === 'object' && Array.isArray((rawData as Record<string, unknown>).list)
          ? ((rawData as Record<string, unknown>).list as Array<Record<string, unknown>>)
          : [];
      for (const dayRow of days) {
        const dk = sanitizeDateKey(pickStr(dayRow, ['dateStr', 'date', 'time']));
        const gen = pickNum(dayRow, ['energy', 'eToday', 'value']);
        if (dk && gen !== undefined && gen >= 0) {
          historicalDailyLogs.push({
            dateKey: dk,
            generationKwh: round2(gen),
            consumptionKwh: pickNum(dayRow, ['consumeEnergy', 'homeLoadEnergy']),
            exportKwh: pickNum(dayRow, ['gridSellEnergy']),
            importKwh: pickNum(dayRow, ['gridPurchasedEnergy']),
          });
        }
      }
    } catch {
      // Optional history fetch
    }
  }

  return buildSolisTelemetryResponse({
    inverterData,
    matchedInvSn,
    matchedLogSn,
    chosenStationId,
    serialMatchVerified,
    loggerSignalPct,
    loggerOnline,
    historicalDailyLogs,
    detectedFormat: 'soliscloud_web_login',
  });
}

async function syncSolisCloudPortal(params: PortalSyncParams): Promise<CloudInverterSyncResponse> {
  const apiBase = (envVar('INVERTER_SOLIS_API_BASE') || 'https://www.soliscloud.com:13333').replace(
    /\/+$/,
    ''
  );

  // Path A: Official API Integration mode (explicit authMode === 'api' OR numeric KeyID entered)
  const explicitApiMode = params.authMode === 'api';
  const candidateKeyId = (params.apiKey || params.username || '').trim();
  const candidateKeySecret = (params.apiSecret || params.password || '').trim();
  const userEnteredApiKey =
    (explicitApiMode && candidateKeyId.length > 0 && candidateKeySecret.length > 0) ||
    (looksLikeSolisKeyId(candidateKeyId) && candidateKeySecret.length >= 16);

  const keyId = userEnteredApiKey
    ? candidateKeyId
    : explicitApiMode
      ? envVar('INVERTER_SOLIS_KEY_ID') || ''
      : '';
  const keySecret = userEnteredApiKey
    ? candidateKeySecret
    : explicitApiMode
      ? envVar('INVERTER_SOLIS_KEY_SECRET') || ''
      : '';

  if (explicitApiMode && (!keyId || !keySecret)) {
    return {
      ok: false,
      brand: 'soliscloud',
      providerName: 'SolisCloud API',
      requiresApiCredentialsHint: true,
      error:
        'Enter your SolisCloud API KeyID and KeySecret to sync via API Integration (or switch to Manufacturer Website Login to sign in with your www.soliscloud.com email and password).',
    };
  }

  // Path B: Direct https://www.soliscloud.com/login email/username + password authentication
  if (!keyId || !keySecret) {
    return syncSolisCloudWebLogin(params);
  }

  let inverterData: Record<string, unknown> | null = null;
  let matchedInvSn = params.inverterSerial;
  let matchedLogSn = params.loggerSerial;
  let chosenStationId = params.stationId;
  let serialMatchVerified = false;
  let loggerSignalPct: number | undefined;
  let loggerOnline: boolean | undefined;

  // Step 1: If inverter S/N is provided, fetch /v1/api/inverterDetail directly
  if (params.inverterSerial) {
    const det = await solisSignedPost(
      apiBase,
      '/v1/api/inverterDetail',
      { sn: params.inverterSerial },
      keyId,
      keySecret
    );
    if (det.ok && det.json?.success && det.json.data && typeof det.json.data === 'object') {
      inverterData = det.json.data as Record<string, unknown>;
      matchedInvSn = pickStr(inverterData, ['sn']) || params.inverterSerial;
      matchedLogSn = pickStr(inverterData, ['collectorSn', 'collectorsn']) || params.loggerSerial;
      chosenStationId = pickStr(inverterData, ['stationId']) || chosenStationId;
      const invOk = serialsMatch(params.inverterSerial, matchedInvSn);
      const logOk = !params.loggerSerial || serialsMatch(params.loggerSerial, matchedLogSn);
      serialMatchVerified = invOk && logOk;
    }
  }

  // Step 2: If no inverterDetail yet (e.g. only Logger S/N or Station ID provided), scan inverterDetailList
  if (!inverterData) {
    const listRes = await solisSignedPost(
      apiBase,
      '/v1/api/inverterDetailList',
      { pageNo: 1, pageSize: 20, ...(params.stationId ? { stationId: params.stationId } : {}) },
      keyId,
      keySecret
    );
    const records = extractSolisRecords(listRes.json?.data);

    if (!listRes.ok || listRes.json?.success === false) {
      return {
        ok: false,
        brand: 'soliscloud',
        providerName: 'SolisCloud',
        error: `SolisCloud API authentication failed: ${String(listRes.json?.msg || `HTTP ${listRes.status}`)}. Verify your KeyID and KeySecret.`,
      };
    }

    if (records.length === 0) {
      return {
        ok: false,
        brand: 'soliscloud',
        providerName: 'SolisCloud',
        error: 'Signed in to SolisCloud, but no inverters were found on this account.',
      };
    }

    const matchedRec = records.find((rec) => {
      const sn = pickStr(rec, ['sn']);
      const col = pickStr(rec, ['collectorSn']);
      return (
        (params.inverterSerial && serialsMatch(params.inverterSerial, sn)) ||
        (params.loggerSerial && serialsMatch(params.loggerSerial, col))
      );
    });

    if (
      !matchedRec &&
      records.length > 1 &&
      !params.stationId &&
      !params.inverterSerial &&
      !params.loggerSerial
    ) {
      return {
        ok: false,
        brand: 'soliscloud',
        detectedBrand: 'soliscloud',
        providerName: 'SolisCloud',
        requiresPlantSelection: true,
        discoveredPlants: records.map((rec) => ({
          stationId: pickStr(rec, ['stationId']) || '',
          plantName: pickStr(rec, ['stationName']) || 'SolisCloud Plant',
          capacityKwp: pickNum(rec, ['power']),
          inverterSerial: pickStr(rec, ['sn']),
          loggerSerial: pickStr(rec, ['collectorSn']),
          status:
            String(rec.state) === '1'
              ? 'Online'
              : String(rec.state) === '2'
                ? 'Offline'
                : 'Alarm',
        })),
        message: `Found ${records.length} SolisCloud inverters on your account. Select the plant to sync.`,
      };
    }

    inverterData = matchedRec || records[0];
    matchedInvSn = pickStr(inverterData, ['sn']);
    matchedLogSn = pickStr(inverterData, ['collectorSn']);
    chosenStationId = pickStr(inverterData, ['stationId']) || chosenStationId;
    serialMatchVerified =
      (!params.inverterSerial || serialsMatch(params.inverterSerial, matchedInvSn)) &&
      (!params.loggerSerial || serialsMatch(params.loggerSerial, matchedLogSn));
  }

  // Step 3: Query collectorList to verify Data Logger status & RSSI signal strength
  if (matchedLogSn || chosenStationId) {
    try {
      const colRes = await solisSignedPost(
        apiBase,
        '/v1/api/collectorList',
        { pageNo: 1, pageSize: 20, ...(chosenStationId ? { stationId: chosenStationId } : {}) },
        keyId,
        keySecret
      );
      const colRecords = extractSolisRecords(colRes.json?.data);
      const colMatch =
        colRecords.find((c) => serialsMatch(matchedLogSn || params.loggerSerial, pickStr(c, ['sn']))) ||
        colRecords[0];
      if (colMatch) {
        matchedLogSn = pickStr(colMatch, ['sn']) || matchedLogSn;
        const rssi = pickNum(colMatch, ['rssi', 'rssiLevel']);
        if (rssi !== undefined) {
          loggerSignalPct =
            rssi < 0
              ? Math.max(0, Math.min(100, Math.round((rssi + 100) * 2)))
              : Math.min(100, Math.round(rssi));
        }
        const cState = pickNum(colMatch, ['state']);
        loggerOnline = cState === 1;
      }
    } catch {
      // Optional logger diagnostics
    }
  }

  // Step 4: Pull current month daily logs via /v1/api/inverterMonth
  const stamp = toIstStamp();
  const historicalDailyLogs: NonNullable<CloudInverterSyncResponse['historicalDailyLogs']> = [];
  if (matchedInvSn) {
    try {
      const monthStr = stamp.dateKey.slice(0, 7);
      const mRes = await solisSignedPost(
        apiBase,
        '/v1/api/inverterMonth',
        { sn: matchedInvSn, month: monthStr, money: 'INR' },
        keyId,
        keySecret
      );
      const days = Array.isArray(mRes.json?.data)
        ? (mRes.json.data as Array<Record<string, unknown>>)
        : [];
      for (const dayRow of days) {
        const dk = sanitizeDateKey(pickStr(dayRow, ['dateStr', 'date']));
        const gen = pickNum(dayRow, ['energy', 'eToday']);
        if (dk && gen !== undefined && gen >= 0) {
          historicalDailyLogs.push({
            dateKey: dk,
            generationKwh: round2(gen),
            consumptionKwh: pickNum(dayRow, ['consumeEnergy']),
            exportKwh: pickNum(dayRow, ['gridSellEnergy']),
            importKwh: pickNum(dayRow, ['gridPurchasedEnergy']),
          });
        }
      }
    } catch {
      // Optional history fetch
    }
  }

  return buildSolisTelemetryResponse({
    inverterData,
    matchedInvSn,
    matchedLogSn,
    chosenStationId,
    serialMatchVerified,
    loggerSignalPct,
    loggerOnline,
    historicalDailyLogs,
    detectedFormat: 'soliscloud_api',
  });
}

// ============================================================================
// 4. SOLARMAN SMART / BUSINESS (Deye, V-Sole, KSolare, Sofar, Havells, Polycab)
// ============================================================================
async function syncSolarmanPortal(params: PortalSyncParams): Promise<CloudInverterSyncResponse> {
  const apiBase = (envVar('INVERTER_SOLARMAN_API_BASE') || 'https://globalapi.solarmanpv.com').replace(
    /\/+$/,
    ''
  );
  const appId = (params.apiKey || envVar('INVERTER_SOLARMAN_APP_ID') || '').trim();
  const appSecret = (params.apiSecret || envVar('INVERTER_SOLARMAN_APP_SECRET') || '').trim();
  const sha256Pwd = crypto.createHash('sha256').update(params.password, 'utf8').digest('hex');

  let accessToken = '';
  let useOpenApi = false;
  let lastErr = 'Solarman login failed. Verify your Solarman Smart/Business email and password.';

  // Method A: Official Solarman OpenAPI token when server AppID & AppSecret are configured
  if (appId && appSecret) {
    try {
      const resp = await portalFetch(
        `${apiBase}/account/v1.0/token?appId=${encodeURIComponent(appId)}&language=en`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            appSecret,
            ...(params.username.includes('@')
              ? { email: params.username }
              : { username: params.username }),
            password: sha256Pwd,
          }),
        }
      );
      const j = (await resp.json().catch(() => null)) as {
        access_token?: string;
        msg?: string;
      } | null;
      if (resp.ok && j?.access_token) {
        accessToken = j.access_token;
        useOpenApi = true;
      } else if (j?.msg) {
        lastErr = `Solarman OpenAPI: ${j.msg}`;
      }
    } catch {
      // Fallback to web token
    }
  }

  // Method B: Solarman Smart / Pro Web OAuth Token (Direct Email/Username + SHA256 Password)
  let webApiOrigin = 'https://globalhome.solarmanpv.com';
  if (!accessToken) {
    const webEndpoints = [
      { origin: 'https://globalhome.solarmanpv.com', clientId: 'test', grantType: 'password' },
      { origin: 'https://globalpro.solarmanpv.com', clientId: 'test', grantType: 'password' },
    ];
    for (const ep of webEndpoints) {
      try {
        const form = new URLSearchParams({
          grant_type: ep.grantType,
          username: params.username,
          password: sha256Pwd,
          clear_text_pwd: params.password,
          identity_type: params.username.includes('@') ? '2' : '1',
          client_id: ep.clientId,
          system: 'SOLARMAN',
        });
        const resp = await portalFetch(`${ep.origin}/oauth-s/oauth/token`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: form.toString(),
        });
        const j = (await resp.json().catch(() => null)) as {
          access_token?: string;
          error_description?: string;
          msg?: string;
        } | null;
        if (resp.ok && j?.access_token) {
          accessToken = j.access_token;
          webApiOrigin = ep.origin;
          break;
        }
        if (j?.error_description || j?.msg) {
          lastErr = `Solarman: ${j.error_description || j.msg}`;
        }
      } catch {
        // Try next Solarman portal origin
      }
    }
  }

  if (!accessToken) {
    return {
      ok: false,
      brand: 'solarman',
      providerName: 'Solarman',
      requiresApiCredentialsHint: !appId,
      error: !appId
        ? `${lastErr} (If Solarman Smart requires developer OpenAPI access for your region, configure INVERTER_SOLARMAN_APP_ID & INVERTER_SOLARMAN_APP_SECRET in server settings, or use Local Wi-Fi IP / HTTPS Bridge.)`
        : lastErr,
    };
  }

  const stamp = toIstStamp();
  const authHeader = `bearer ${accessToken}`;

  if (useOpenApi) {
    // 1. List stations
    const stResp = await portalFetch(`${apiBase}/station/v1.0/list?language=en`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body: JSON.stringify({ page: 1, size: 20 }),
    });
    const stJson = (await stResp.json().catch(() => null)) as {
      stationList?: Array<Record<string, unknown>>;
    } | null;
    const stations = Array.isArray(stJson?.stationList) ? stJson.stationList : [];

    // 2. Match device/station by Inverter S/N & Logger S/N
    let chosenStation =
      (params.stationId
        ? stations.find((s) => String(s.id) === params.stationId)
        : undefined) || stations[0];
    let matchedInvSn = params.inverterSerial;
    let matchedLogSn = params.loggerSerial;
    let serialMatchVerified = false;
    let loggerSignalPct: number | undefined;
    let loggerOnline: boolean | undefined;

    for (const st of stations.slice(0, 6)) {
      const sid = pickStr(st, ['id']);
      if (!sid) continue;
      try {
        const dResp = await portalFetch(`${apiBase}/station/v1.0/device?language=en`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: authHeader },
          body: JSON.stringify({ stationId: Number(sid) || sid, page: 1, size: 20 }),
        });
        const dJson = (await dResp.json().catch(() => null)) as {
          deviceListItems?: Array<Record<string, unknown>>;
        } | null;
        const devs = Array.isArray(dJson?.deviceListItems) ? dJson.deviceListItems : [];
        const invDev = devs.find(
          (dv) =>
            String(dv.deviceType || '').toUpperCase().includes('INVERTER') ||
            (params.inverterSerial && serialsMatch(params.inverterSerial, pickStr(dv, ['deviceSn'])))
        );
        const colDev = devs.find(
          (dv) =>
            String(dv.deviceType || '').toUpperCase().includes('COLLECTOR') ||
            (params.loggerSerial && serialsMatch(params.loggerSerial, pickStr(dv, ['deviceSn'])))
        );

        const invMatch = params.inverterSerial
          ? serialsMatch(params.inverterSerial, pickStr(invDev, ['deviceSn']))
          : false;
        const logMatch = params.loggerSerial
          ? serialsMatch(params.loggerSerial, pickStr(colDev, ['deviceSn']))
          : false;

        if (invMatch || logMatch) {
          chosenStation = st;
          matchedInvSn = pickStr(invDev, ['deviceSn']) || matchedInvSn;
          matchedLogSn = pickStr(colDev, ['deviceSn']) || matchedLogSn;
          loggerOnline = Number(colDev?.connectStatus) === 1;
          serialMatchVerified =
            (!params.inverterSerial || invMatch) && (!params.loggerSerial || logMatch);
          break;
        }
      } catch {
        // Continue checking stations
      }
    }

    const chosenStationId = params.stationId || pickStr(chosenStation, ['id']);
    let rtJson: Record<string, unknown> = {};
    if (chosenStationId) {
      const rtResp = await portalFetch(`${apiBase}/station/v1.0/realTime?language=en`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: authHeader },
        body: JSON.stringify({ stationId: Number(chosenStationId) || chosenStationId }),
      });
      rtJson = ((await rtResp.json().catch(() => ({}))) as Record<string, unknown>) || {};
    }

    // 3. Query /device/v1.0/currentData for deep electrical & PV/AC/Battery telemetry
    const pvStrings: InverterPvStringReading[] = [];
    let inverterTempC: number | undefined;
    let gridVoltageV: number | undefined;
    let gridFrequencyHz: number | undefined;
    let acCurrentA: number | undefined;
    let batterySocPct: number | undefined;
    let batteryPowerKw: number | undefined;
    let deviceState: number | undefined;

    const querySn = matchedInvSn || matchedLogSn;
    if (querySn) {
      try {
        const cdResp = await portalFetch(`${apiBase}/device/v1.0/currentData?language=en`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: authHeader },
          body: JSON.stringify({ deviceSn: querySn }),
        });
        const cdJson = (await cdResp.json().catch(() => null)) as {
          deviceState?: number;
          dataList?: Array<{ key?: string; name?: string; value?: string; unit?: string }>;
        } | null;
        deviceState = cdJson?.deviceState;
        const points = Array.isArray(cdJson?.dataList) ? cdJson.dataList : [];
        const findPt = (rx: RegExp) =>
          points.find((p) => rx.test(`${p.key || ''} ${p.name || ''}`));

        for (let i = 1; i <= 4; i++) {
          const v = numVal(findPt(new RegExp(`(pv${i}.*volt|dc.*volt.*${i}|dv${i})`, 'i'))?.value);
          const a = numVal(findPt(new RegExp(`(pv${i}.*curr|dc.*curr.*${i}|dc${i})`, 'i'))?.value);
          const w =
            numVal(findPt(new RegExp(`(pv${i}.*pow|dp${i})`, 'i'))?.value) ??
            (v !== undefined && a !== undefined ? Math.round(v * a) : undefined);
          if ((v ?? 0) > 0 || (a ?? 0) > 0) {
            pvStrings.push({ id: `PV${i}`, voltageV: v, currentA: a, powerW: w });
          }
        }
        inverterTempC = numVal(findPt(/(radiator|inverter|module|internal).*temp/i)?.value);
        gridVoltageV = numVal(findPt(/(ac|grid).*volt.*(1|a|r)?/i)?.value);
        acCurrentA = numVal(findPt(/(ac|grid).*curr.*(1|a|r)?/i)?.value);
        gridFrequencyHz = numVal(findPt(/(ac|grid).*freq/i)?.value);
        batterySocPct = numVal(findPt(/\bsoc\b|battery.*level|state.*charge/i)?.value);
        const batP = findPt(/battery.*power/i);
        batteryPowerKw = toKwSmart(numVal(batP?.value), batP?.unit);
        const rssiPt = findPt(/rssi|signal/i);
        const rssiNum = numVal(rssiPt?.value);
        if (rssiNum !== undefined) {
          loggerSignalPct = rssiNum < 0 ? Math.max(0, Math.min(100, Math.round((rssiNum + 100) * 2))) : Math.min(100, Math.round(rssiNum));
        }
      } catch {
        // Optional deep device telemetry
      }
    }

    const livePowerW = pickNum(rtJson, ['generationPower']) ?? 0;
    const todayGenKwh = pickNum(rtJson, ['generationValue']) ?? 0;
    const todayUsageKwh = pickNum(rtJson, ['useValue']);
    const todayExportKwh = pickNum(rtJson, ['wireValue', 'gridValue']);
    const todayImportKwh = pickNum(rtJson, ['buyValue']);
    const lifetimeKwh = pickNum(rtJson, ['generationTotal']);
    const hasSmartMeter =
      todayUsageKwh !== undefined || todayExportKwh !== undefined || todayImportKwh !== undefined;

    const extendedTelemetry = compactExtendedTelemetry({
      inverterStatus: deviceState === 1 ? 'online' : deviceState === 2 ? 'fault' : deviceState === 3 ? 'offline' : livePowerW > 0 ? 'online' : 'standby',
      inverterStatusText: deviceState === 1 ? 'Online' : deviceState === 2 ? 'Fault' : deviceState === 3 ? 'Offline' : 'Synced',
      loggerStatus: loggerOnline === false ? 'offline' : 'online',
      loggerSignalPct,
      serialMatchVerified,
      matchedInverterSerial: matchedInvSn,
      matchedLoggerSerial: matchedLogSn,
      inverterTempC,
      gridVoltageV,
      acCurrentA,
      gridFrequencyHz,
      batterySocPct: batterySocPct ?? pickNum(rtJson, ['batterySoc']),
      batteryPowerKw: batteryPowerKw ?? toKwSmart(pickNum(rtJson, ['batteryPower']), 'w'),
      pvStrings,
      portalRegion: new URL(apiBase).hostname,
    });

    return {
      ok: true,
      brand: 'solarman',
      detectedBrand: 'solarman',
      providerName: 'Solarman',
      detectedFormat: 'solarman_cloud_api',
      detectedStationId: chosenStationId,
      detectedPlantName: pickStr(chosenStation, ['name']) || 'Solarman Solar Plant',
      detectedInverterSerial: matchedInvSn,
      detectedLoggerSerial: matchedLogSn,
      serialMatchVerified,
      detectedCapacityKwp: toKwSmart(pickNum(chosenStation, ['installedCapacity']), 'kw'),
      message: `Synced live Solarman telemetry${serialMatchVerified ? ' (Inverter & Logger verified)' : ''}`,
      telemetry: {
        dateKey: stamp.dateKey,
        todayGenKwh: round2(Math.max(0, todayGenKwh)),
        livePowerKw: round2(Math.max(0, livePowerW / 1000)),
        ...(todayUsageKwh !== undefined ? { todayUsageKwh: round2(Math.max(0, todayUsageKwh)) } : {}),
        ...(todayExportKwh !== undefined ? { todayExportKwh: round2(Math.max(0, todayExportKwh)) } : {}),
        ...(todayImportKwh !== undefined ? { todayImportKwh: round2(Math.max(0, todayImportKwh)) } : {}),
        ...(lifetimeKwh !== undefined ? { lifetimeKwh: Number(Math.max(0, lifetimeKwh).toFixed(1)) } : {}),
        hasSmartMeter,
        syncedAtIso: stamp.iso,
        syncedAtIst: stamp.ist,
        statusNote: `Solarman Cloud · ${matchedInvSn || chosenStationId || 'Synced'}`,
      },
      extendedTelemetry,
    };
  }

  // Web OAuth path (globalhome / globalpro)
  const webStResp = await portalFetch(`${webApiOrigin}/maintain-s/operating/station/v2/search?page=1&size=20&order.direction=DESC&order.property=id`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: authHeader },
    body: JSON.stringify({}),
  });
  const webStJson = (await webStResp.json().catch(() => null)) as {
    data?: Array<Record<string, unknown>>;
  } | null;
  const webStations = Array.isArray(webStJson?.data) ? webStJson.data : [];
  const chosen = webStations[0];
  if (!chosen) {
    return {
      ok: false,
      brand: 'solarman',
      providerName: 'Solarman',
      error: 'Signed in to Solarman, but no stations were returned for this account.',
    };
  }
  const genPowerW = pickNum(chosen, ['generationPower']) ?? 0;
  const genToday = pickNum(chosen, ['generationValue']) ?? 0;
  const genTotal = pickNum(chosen, ['generationTotal']);
  return {
    ok: true,
    brand: 'solarman',
    detectedBrand: 'solarman',
    providerName: 'Solarman',
    detectedFormat: 'solarman_web_oauth',
    detectedStationId: pickStr(chosen, ['id']),
    detectedPlantName: pickStr(chosen, ['name']) || 'Solarman Plant',
    detectedInverterSerial: params.inverterSerial,
    detectedLoggerSerial: params.loggerSerial,
    detectedCapacityKwp: pickNum(chosen, ['installedCapacity']),
    message: 'Synced live Solarman Smart telemetry',
    telemetry: {
      dateKey: stamp.dateKey,
      todayGenKwh: round2(Math.max(0, genToday)),
      livePowerKw: round2(Math.max(0, genPowerW / 1000)),
      ...(genTotal !== undefined ? { lifetimeKwh: Number(Math.max(0, genTotal).toFixed(1)) } : {}),
      hasSmartMeter: false,
      syncedAtIso: stamp.iso,
      syncedAtIst: stamp.ist,
      statusNote: `Solarman Web · ${pickStr(chosen, ['name']) || 'Synced'}`,
    },
  };
}

// ============================================================================
// 5. SUNGROW iSOLARCLOUD (Multi-Region Gateway Login)
// ============================================================================
async function syncSungrowPortal(params: PortalSyncParams): Promise<CloudInverterSyncResponse> {
  const appKey = envVar('INVERTER_SUNGROW_APP_KEY') || 'ANDROIDE13EC118D789299C9A503F2184611882';
  const gateways = [
    'https://gateway.isolarcloud.com.hk',
    'https://gateway.isolarcloud.com',
    'https://gateway.isolarcloud.eu',
  ];

  let activeGateway = gateways[0];
  let token = '';
  let userId = '';
  let lastErr = 'Sungrow iSolarCloud login failed. Verify your email/username and password.';

  for (const gw of gateways) {
    try {
      const resp = await portalFetch(`${gw}/v1/userService/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', sys_code: '900' },
        body: JSON.stringify({
          appkey: appKey,
          user_account: params.username,
          user_password: params.password,
          login_type: '1',
          sys_code: '900',
          lang: '_en_US',
        }),
      });
      const json = (await resp.json().catch(() => null)) as {
        result_code?: string;
        result_msg?: string;
        result_data?: Record<string, unknown>;
      } | null;

      if (resp.ok && json?.result_code === '1' && json.result_data?.token) {
        activeGateway = gw;
        token = String(json.result_data.token);
        userId = String(json.result_data.user_id || '');
        break;
      }
      if (json?.result_msg) lastErr = `Sungrow iSolarCloud: ${json.result_msg}`;
    } catch {
      // Try next regional gateway
    }
  }

  if (!token) {
    return {
      ok: false,
      brand: 'sungrow',
      providerName: 'Sungrow iSolarCloud',
      error: lastErr,
    };
  }

  const psResp = await portalFetch(`${activeGateway}/v1/powerStationService/getPsList`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', sys_code: '900' },
    body: JSON.stringify({
      appkey: appKey,
      token,
      user_id: userId,
      sys_code: '900',
      lang: '_en_US',
      curPage: 1,
      size: 20,
    }),
  });
  const psJson = (await psResp.json().catch(() => null)) as {
    result_data?: { pageList?: Array<Record<string, unknown>> };
  } | null;
  const plants = Array.isArray(psJson?.result_data?.pageList) ? psJson.result_data.pageList : [];
  if (plants.length === 0) {
    return {
      ok: false,
      brand: 'sungrow',
      providerName: 'Sungrow iSolarCloud',
      error: 'Signed in to Sungrow iSolarCloud, but no power stations were found on this account.',
    };
  }

  let chosenPlant =
    (params.stationId ? plants.find((p) => String(p.ps_id) === params.stationId) : undefined) ||
    plants[0];
  let matchedInvSn = params.inverterSerial;
  let matchedLogSn = params.loggerSerial;
  let serialMatchVerified = false;
  const discovered: DiscoveredCloudPlant[] = [];

  for (const pl of plants.slice(0, 6)) {
    const psId = pickStr(pl, ['ps_id']);
    if (!psId) continue;
    let invSn: string | undefined;
    let logSn: string | undefined;
    let matchedHere = false;

    try {
      const devResp = await portalFetch(`${activeGateway}/v1/devService/getDeviceList`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', sys_code: '900' },
        body: JSON.stringify({
          appkey: appKey,
          token,
          ps_id: psId,
          sys_code: '900',
          lang: '_en_US',
          curPage: 1,
          size: 20,
        }),
      });
      const devJson = (await devResp.json().catch(() => null)) as {
        result_data?: { pageList?: Array<Record<string, unknown>> };
      } | null;
      const devs = Array.isArray(devJson?.result_data?.pageList) ? devJson.result_data.pageList : [];
      for (const dv of devs) {
        const sn = pickStr(dv, ['device_sn', 'sn']);
        const commSn = pickStr(dv, ['communication_dev_sn', 'rel_device_sn']);
        if (!invSn && sn) invSn = sn;
        if (!logSn && commSn) logSn = commSn;
        const invOk = params.inverterSerial ? serialsMatch(params.inverterSerial, sn) : false;
        const logOk = params.loggerSerial ? serialsMatch(params.loggerSerial, commSn) : false;
        if (invOk || logOk) {
          matchedHere = true;
          chosenPlant = pl;
          matchedInvSn = sn;
          matchedLogSn = commSn;
          serialMatchVerified =
            (!params.inverterSerial || invOk) && (!params.loggerSerial || logOk);
          break;
        }
      }
    } catch {
      // Continue
    }

    discovered.push({
      stationId: psId,
      plantName: pickStr(pl, ['ps_name']) || `Sungrow Plant ${psId}`,
      capacityKwp: toKwSmart(
        pickNum((pl.total_capcity as Record<string, unknown>) || pl, ['value', 'total_capcity']),
        pickStr(pl.total_capcity as Record<string, unknown>, ['unit']) || 'kwp'
      ),
      inverterSerial: invSn,
      loggerSerial: logSn,
    });

    if (matchedHere) break;
  }

  if (
    !params.stationId &&
    !serialMatchVerified &&
    discovered.length > 1 &&
    !params.inverterSerial &&
    !params.loggerSerial
  ) {
    return {
      ok: false,
      brand: 'sungrow',
      detectedBrand: 'sungrow',
      providerName: 'Sungrow iSolarCloud',
      requiresPlantSelection: true,
      discoveredPlants: discovered,
      message: `Found ${discovered.length} Sungrow power stations. Select the station to sync.`,
    };
  }

  const stamp = toIstStamp();
  const extractMetric = (field: unknown) => {
    if (field && typeof field === 'object' && 'value' in field) {
      const f = field as { value?: unknown; unit?: string };
      return { val: numVal(f.value), unit: f.unit };
    }
    return { val: numVal(field), unit: undefined };
  };

  const currP = extractMetric(chosenPlant.curr_power);
  const todayE = extractMetric(chosenPlant.today_energy);
  const totalE = extractMetric(chosenPlant.total_energy);
  const capM = extractMetric(chosenPlant.total_capcity);

  const livePowerKw = toKwSmart(currP.val, currP.unit) ?? 0;
  const todayGenKwh =
    todayE.val !== undefined
      ? (todayE.unit || '').toLowerCase() === 'mwh'
        ? todayE.val * 1000
        : (todayE.unit || '').toLowerCase() === 'wh'
          ? todayE.val / 1000
          : todayE.val
      : 0;
  const lifetimeKwh =
    totalE.val !== undefined
      ? (totalE.unit || '').toLowerCase() === 'mwh'
        ? totalE.val * 1000
        : totalE.val
      : undefined;

  const psStatus = pickNum(chosenPlant, ['ps_status', 'ps_fault_status']);
  const extendedTelemetry = compactExtendedTelemetry({
    inverterStatus: psStatus === 1 ? 'online' : psStatus === 2 ? 'offline' : psStatus === 3 ? 'fault' : 'online',
    inverterStatusText: psStatus === 1 ? 'Normal' : psStatus === 2 ? 'Offline' : psStatus === 3 ? 'Fault' : 'Synced',
    loggerStatus: psStatus === 2 ? 'offline' : 'online',
    serialMatchVerified,
    matchedInverterSerial: matchedInvSn,
    matchedLoggerSerial: matchedLogSn,
    portalRegion: new URL(activeGateway).hostname,
  });

  return {
    ok: true,
    brand: 'sungrow',
    detectedBrand: 'sungrow',
    providerName: 'Sungrow iSolarCloud',
    detectedFormat: 'sungrow_isolarcloud',
    detectedStationId: pickStr(chosenPlant, ['ps_id']),
    detectedPlantName: pickStr(chosenPlant, ['ps_name']) || 'Sungrow Solar Plant',
    detectedInverterSerial: matchedInvSn,
    detectedLoggerSerial: matchedLogSn,
    serialMatchVerified,
    detectedCapacityKwp: toKwSmart(capM.val, capM.unit || 'kwp'),
    message: `Synced live Sungrow iSolarCloud telemetry${serialMatchVerified ? ' (Inverter & Logger verified)' : ''}`,
    telemetry: {
      dateKey: stamp.dateKey,
      todayGenKwh: round2(Math.max(0, todayGenKwh)),
      livePowerKw: round2(Math.max(0, livePowerKw)),
      ...(lifetimeKwh !== undefined ? { lifetimeKwh: Number(Math.max(0, lifetimeKwh).toFixed(1)) } : {}),
      hasSmartMeter: false,
      syncedAtIso: stamp.iso,
      syncedAtIst: stamp.ist,
      statusNote: `Sungrow iSolarCloud · ${matchedInvSn || pickStr(chosenPlant, ['ps_id']) || 'Synced'}`,
    },
    extendedTelemetry,
  };
}

// ============================================================================
// SMART AUTO-DETECT ORDERING BY SERIAL NUMBER PREFIXES & CREDENTIALS
// ============================================================================
function inferPortalTryOrder(params: PortalSyncParams): CloudPortalBrand[] {
  const inv = normSerial(params.inverterSerial);
  const log = normSerial(params.loggerSerial);
  const user = params.username.trim();

  if (looksLikeSolisKeyId(user)) {
    return ['soliscloud', 'goodwe', 'growatt', 'solarman', 'sungrow'];
  }
  if (/^(90|50|GW|GE)/.test(inv)) {
    return ['goodwe', 'growatt', 'solarman', 'sungrow', 'soliscloud'];
  }
  if (
    /^(100|110|120|140|150|160|170|180|181)/.test(inv) ||
    /^(S2|S3|300|400|5A1)/.test(log)
  ) {
    return ['soliscloud', 'solarman', 'goodwe', 'growatt', 'sungrow'];
  }
  if (/^(17|21|23|27|29|31)\d{8}$/.test(log)) {
    return ['solarman', 'goodwe', 'growatt', 'sungrow', 'soliscloud'];
  }
  if (/^(SH|SG|A2|B2)/.test(inv)) {
    return ['sungrow', 'goodwe', 'growatt', 'solarman', 'soliscloud'];
  }
  return ['soliscloud', 'goodwe', 'growatt', 'sungrow', 'solarman'];
}

async function runSinglePortalAdapter(
  brand: CloudPortalBrand,
  params: PortalSyncParams
): Promise<CloudInverterSyncResponse> {
  switch (brand) {
    case 'goodwe':
      return syncGoodWeSemsPortal(params);
    case 'growatt':
      return syncGrowattPortal(params);
    case 'soliscloud':
      return syncSolisCloudPortal(params);
    case 'solarman':
      return syncSolarmanPortal(params);
    case 'sungrow':
      return syncSungrowPortal(params);
  }
}

// ============================================================================
// EXPRESS ROUTE HANDLERS
// ============================================================================
async function runInverterPortalSync(body: any, res: any) {
  body = body || {};
  const rawBrand = String(body.brand || 'auto').trim().toLowerCase();
  const authMode: 'website' | 'api' = body.authMode === 'api' ? 'api' : 'website';
  const autoDetect = rawBrand === 'auto' || Boolean(body.autoDetect);
  const username = typeof body.username === 'string' ? body.username.trim().slice(0, 140) : '';
  const password = typeof body.password === 'string' ? body.password.slice(0, 200) : '';
  const apiKey = typeof body.apiKey === 'string' ? body.apiKey.trim().slice(0, 140) : '';
  const apiSecret = typeof body.apiSecret === 'string' ? body.apiSecret.trim().slice(0, 200) : '';
  const inverterSerial =
    typeof body.inverterSerial === 'string' ? body.inverterSerial.trim().slice(0, 80) : '';
  const loggerSerial =
    typeof body.loggerSerial === 'string' ? body.loggerSerial.trim().slice(0, 80) : '';
  const stationId = typeof body.stationId === 'string' ? body.stationId.trim().slice(0, 80) : '';
  const region = typeof body.region === 'string' ? body.region.trim().slice(0, 40) : undefined;

  const hasWebsiteCreds = Boolean(username && password);
  const hasApiCreds = Boolean(apiKey && apiSecret);

  if (authMode === 'website' && !hasWebsiteCreds) {
    res.status(200).json({
      ok: false,
      brand: (CLOUD_PORTAL_BRANDS.includes(rawBrand as CloudPortalBrand)
        ? rawBrand
        : 'soliscloud') as InverterBrandId,
      error: 'Enter your manufacturer website email/username and password to log in and sync.',
    });
    return;
  }

  if (authMode === 'api' && !hasApiCreds && !hasWebsiteCreds) {
    res.status(200).json({
      ok: false,
      brand: (CLOUD_PORTAL_BRANDS.includes(rawBrand as CloudPortalBrand)
        ? rawBrand
        : 'soliscloud') as InverterBrandId,
      error: 'Enter your Manufacturer API Key / KeyID and API Secret / KeySecret to sync via API.',
    });
    return;
  }

  const syncParams: PortalSyncParams = {
    authMode,
    username: username || apiKey,
    password: password || apiSecret,
    apiKey: apiKey || undefined,
    apiSecret: apiSecret || undefined,
    inverterSerial: inverterSerial || undefined,
    loggerSerial: loggerSerial || undefined,
    stationId: stationId || undefined,
    region,
  };

  try {
    if (!autoDetect && CLOUD_PORTAL_BRANDS.includes(rawBrand as CloudPortalBrand)) {
      const result = await runSinglePortalAdapter(rawBrand as CloudPortalBrand, syncParams);
      // Always return HTTP 200 with structured JSON ({ ok: false, error }) so Cloud Run / proxies
      // never intercept 502 responses and replace our JSON payload with an HTML error page.
      res.status(200).json(result);
      return;
    }

    // Automatic Multi-Portal Detection: try inferred brand order until one authenticates
    const order = inferPortalTryOrder(syncParams);
    const errors: string[] = [];

    for (const candidateBrand of order) {
      try {
        const result = await runSinglePortalAdapter(candidateBrand, syncParams);
        if (result.ok || result.requiresPlantSelection) {
          res.status(200).json(result);
          return;
        }
        if (result.error) {
          errors.push(`${result.providerName || candidateBrand}: ${result.error}`);
        }
      } catch (err) {
        errors.push(
          `${candidateBrand}: ${err instanceof Error ? err.message : 'Portal unreachable'}`
        );
      }
    }

    res.status(200).json({
      ok: false,
      brand: order[0],
      error:
        errors[0] ||
        'Could not authenticate against SolisCloud, Solarman, Growatt, Sungrow, or GoodWe with these credentials. Select your exact inverter brand and re-verify your portal login.',
    });
  } catch (err) {
    res.status(200).json({
      ok: false,
      brand: (CLOUD_PORTAL_BRANDS.includes(rawBrand as CloudPortalBrand)
        ? rawBrand
        : 'soliscloud') as InverterBrandId,
      error:
        err instanceof Error
          ? `Cloud portal sync failed: ${err.message}`
          : 'Cloud portal sync timed out. Please retry.',
    });
  }
}

async function runInverterPortalPing(body: any, res: any) {
  body = body || {};
  const rawBrand = String(body.brand || 'soliscloud').trim().toLowerCase();

  const probeUrlByBrand: Record<string, string> = {
    soliscloud: 'https://www.soliscloud.com',
    solarman: 'https://globalapi.solarmanpv.com',
    growatt: 'https://server.growatt.com',
    sungrow: 'https://gateway.isolarcloud.com.hk',
    goodwe: 'https://www.semsportal.com',
  };

  const targetUrl = probeUrlByBrand[rawBrand] || probeUrlByBrand.soliscloud;
  const startedAt = Date.now();
  try {
    const resp = await portalFetch(targetUrl, { method: 'HEAD' }, 5000);
    const latencyMs = Math.max(1, Date.now() - startedAt);
    res.json({
      reachable: true,
      latencyMs,
      httpStatus: resp.status,
      host: new URL(targetUrl).hostname,
    });
  } catch (err) {
    res.json({
      reachable: false,
      latencyMs: null,
      error: err instanceof Error ? err.message : 'Cloud portal did not respond.',
    });
  }
}

// ============================================================================
// WORKER HANDLERS (called from index.js). Return the JSON body to send.
// ============================================================================
function collect(run: (body: any, res: any) => Promise<void>) {
  return async (body: any): Promise<any> => {
    let out: any = null;
    const res = {
      status(_code: number) {
        return res;
      },
      json(v: any) {
        out = v;
        return res;
      },
    };
    await run(body, res);
    return out;
  };
}

export const handleInverterPortalSync = collect(runInverterPortalSync);
export const handleInverterPortalPing = collect(runInverterPortalPing);
