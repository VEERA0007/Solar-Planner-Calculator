// HTTPS bridge sync and local-logger parsing for the Worker.
// Ported from the reference server.ts (handleInverterBridgeSync, validatePublicHttpsBridgeUrl,
// isPrivateOrReservedIp, toIstStamp). The logger parser is copied unchanged into loggerPayloadParser.ts.
import { parseLoggerPayload } from './loggerPayloadParser';

const MAX_BYTES = 524288;
const TIMEOUT_MS = 8000;

export interface BridgeCheck {
  ok: boolean;
  error?: string;
  url?: URL;
}

/** Private, loopback, link-local, CGNAT, multicast and reserved IPv4/IPv6 ranges. */
export function isPrivateOrReservedIp(ipRaw: string): boolean {
  const ip = (ipRaw || '').trim().toLowerCase();
  if (!ip) return true;
  const mapped = ip.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isPrivateOrReservedIp(mapped[1]);
  if (/^\d+\.\d+\.\d+\.\d+$/.test(ip)) {
    const p = ip.split('.').map(Number);
    if (p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
    const [a, b] = p;
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
    if (a === 192 && b === 0) return true;
    if (a >= 224) return true;
    return false;
  }
  if (ip.includes(':')) {
    return ip === '::1' || ip === '::' || ip.startsWith('fc') || ip.startsWith('fd') || ip.startsWith('fe80');
  }
  return false;
}

/**
 * Accepts only a public https:// URL with no embedded login. The Worker cannot resolve
 * hostnames (no DNS API), so a name is checked by its text only; Workers also cannot reach
 * private networks at all.
 */
export function validatePublicHttpsBridgeUrl(rawUrl: string): BridgeCheck {
  const trimmed = (rawUrl || '').trim();
  if (!trimmed || trimmed.length > 240) return { ok: false, error: 'Enter a valid HTTPS Bridge or Home Assistant URL.' };
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { ok: false, error: 'Enter a complete HTTPS URL (for example https://solar.yourdomain.com/status.html).' };
  }
  if (parsed.protocol !== 'https:') {
    return { ok: false, error: 'HTTPS Bridge mode requires an https:// URL. For a home Wi-Fi logger IP, use Local Wi-Fi Logger mode.' };
  }
  if (parsed.username || parsed.password) {
    return { ok: false, error: 'Do not put username or password inside the URL. Use the optional Login fields instead.' };
  }
  const host = parsed.hostname.toLowerCase();
  if (!host || host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') || host.endsWith('.internal')) {
    return { ok: false, error: 'Local network hostnames cannot be reached through the bridge. Use Local Wi-Fi Logger mode on your home Wi-Fi.' };
  }
  if (isPrivateOrReservedIp(host.replace(/^\[|\]$/g, ''))) {
    return { ok: false, error: 'Private LAN addresses cannot be reached through the bridge. Use Local Wi-Fi Logger mode on your home Wi-Fi.' };
  }
  return { ok: true, url: parsed };
}

/** Date and time in India, as the app shows them. */
export function istStamp(now: Date = new Date()): { dateKey: string; iso: string; ist: string } {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  const dateKey = `${get('year')}-${get('month')}-${get('day')}`;
  const human = now.toLocaleString('en-IN', {
    timeZone: 'Asia/Kolkata',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
  return { dateKey, iso: now.toISOString(), ist: `${human} IST` };
}

/** The same success shape the app already reads (see inverter_sync.dart). */
function okResponse(
  brand: string,
  parsed: NonNullable<ReturnType<typeof parseLoggerPayload>>,
  providerName: string,
  note: string,
) {
  const stamp = istStamp(new Date());
  return {
    ok: true,
    brand,
    providerName,
    detectedFormat: parsed.detectedFormat,
    detectedLoggerSerial: parsed.loggerSerial,
    detectedInverterSerial: parsed.inverterSerial,
    detectedPlantName: parsed.plantName,
    detectedModelName: parsed.modelName,
    detectedCapacityKwp: parsed.installedCapacityKwp,
    detectedExportTariffInr: parsed.exportTariffInr,
    message: parsed.summaryNote,
    telemetry: {
      dateKey: stamp.dateKey,
      todayGenKwh: parsed.todayGenKwh ?? 0,
      livePowerKw: parsed.livePowerKw ?? 0,
      ...(parsed.todayUsageKwh !== undefined ? { todayUsageKwh: parsed.todayUsageKwh } : {}),
      ...(parsed.todayExportKwh !== undefined ? { todayExportKwh: parsed.todayExportKwh } : {}),
      ...(parsed.todayImportKwh !== undefined ? { todayImportKwh: parsed.todayImportKwh } : {}),
      ...(parsed.lifetimeKwh !== undefined ? { lifetimeKwh: parsed.lifetimeKwh } : {}),
      hasSmartMeter: parsed.hasSmartMeter,
      syncedAtIso: stamp.iso,
      syncedAtIst: stamp.ist,
      statusNote: note,
    },
  };
}

function failure(status: number, brand: string, error: string) {
  return { status, body: { ok: false, brand, error } };
}

/** POST /api/inverter/bridge-sync. Returns {status, body}. */
export async function handleBridgeSync(body: any, fetchImpl: typeof fetch = fetch): Promise<{ status: number; body: any }> {
  const b = body || {};
  const brand = String(b.brand || 'soliscloud');
  const check = validatePublicHttpsBridgeUrl(String(b.bridgeUrl || ''));
  if (!check.ok || !check.url) return failure(400, brand, check.error || 'Invalid bridge URL.');

  const username = typeof b.username === 'string' ? b.username.trim().slice(0, 120) : '';
  const password = typeof b.password === 'string' ? b.password.slice(0, 200) : '';
  const headers: Record<string, string> = {
    Accept: 'application/json, text/html, text/plain;q=0.9, */*;q=0.5',
    'User-Agent': 'SolarPlannerBridgeSync/1.0',
  };
  if (username) headers.Authorization = `Basic ${btoa(unescape(encodeURIComponent(`${username}:${password}`)))}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let resp: Response;
  try {
    resp = await fetchImpl(check.url.toString(), { method: 'GET', headers, redirect: 'error', signal: controller.signal });
  } catch (err: any) {
    clearTimeout(timer);
    const raw = String(err?.message || 'Bridge request failed.');
    if (/redirect/i.test(raw)) return failure(502, brand, 'Bridge URL redirected to another address. Enter the final direct HTTPS URL.');
    if (/abort|timeout/i.test(raw) || err?.name === 'AbortError') return failure(502, brand, 'Bridge URL timed out after 8 seconds. Check that the bridge is online.');
    return failure(502, brand, `Could not reach the HTTPS bridge: ${raw}`);
  }
  clearTimeout(timer);

  if (resp.status === 401 || resp.status === 403) {
    return failure(401, brand, 'Bridge endpoint rejected the login (HTTP 401/403). Check the bridge username and password.');
  }
  if (!resp.ok) {
    return failure(502, brand, `Bridge endpoint returned HTTP ${resp.status}. Check that the URL returns the logger status page or solar JSON.`);
  }
  const len = Number(resp.headers.get('content-length') || '0');
  if (Number.isFinite(len) && len > MAX_BYTES) return failure(413, brand, 'Bridge response exceeded the 512 KB safety limit.');

  const text = (await resp.text()).slice(0, MAX_BYTES);
  const parsed = parseLoggerPayload(text, {
    loggerSerial: typeof b.loggerSerial === 'string' ? b.loggerSerial.trim().slice(0, 80) : undefined,
    inverterSerial: typeof b.inverterSerial === 'string' ? b.inverterSerial.trim().slice(0, 80) : undefined,
    plantName: typeof b.plantName === 'string' ? b.plantName.trim().slice(0, 80) : undefined,
  });
  if (!parsed) {
    return failure(422, brand, 'Connected to the bridge, but no solar generation fields were found in the response.');
  }
  return { status: 200, body: okResponse(brand, parsed, check.url.hostname, `${parsed.summaryNote} · ${check.url.hostname}`) };
}

/**
 * POST /api/inverter/parse-logger. The phone reads the logger's status page over the home Wi-Fi
 * (no browser CORS limit in the app) and sends the page text here to be parsed.
 * Credentials never reach the Worker: they are used only by the phone for the logger request.
 */
export function handleParseLogger(body: any): { status: number; body: any } {
  const b = body || {};
  const brand = String(b.brand || 'soliscloud');
  const text = typeof b.text === 'string' ? b.text : '';
  if (!text.trim()) return failure(400, brand, 'The logger page was empty.');
  if (text.length > MAX_BYTES) return failure(413, brand, 'The logger page exceeded the 512 KB safety limit.');
  const parsed = parseLoggerPayload(text.slice(0, MAX_BYTES), {
    loggerSerial: typeof b.loggerSerial === 'string' ? b.loggerSerial.trim().slice(0, 80) : undefined,
    inverterSerial: typeof b.inverterSerial === 'string' ? b.inverterSerial.trim().slice(0, 80) : undefined,
    plantName: typeof b.plantName === 'string' ? b.plantName.trim().slice(0, 80) : undefined,
  });
  if (!parsed) {
    return failure(422, brand, 'Reached the logger page, but could not find solar generation fields. Check the logger model.');
  }
  return { status: 200, body: okResponse(brand, parsed, 'Local Wi-Fi logger', `${parsed.summaryNote} · local Wi-Fi`) };
}
