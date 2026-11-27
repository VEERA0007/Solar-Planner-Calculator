/**
 * Direct Solar Data Logger & Home Assistant / JSON Bridge Payload Parser
 *
 * Parses real telemetry returned by:
 * 1. Solis (S2-WL-ST / S3-WIFI-ST) & Solarman (LSW-3) local Wi-Fi stick `status.html`
 * 2. Plain text copied from a logger's web status page
 * 3. Home Assistant REST `/api/states` JSON array or single entity object
 * 4. SolarAssistant / Node-RED / custom JSON solar bridge payloads
 *
 * Strictly extracts only real values present in the payload (never fabricates numbers).
 */

export interface ParsedLoggerTelemetry {
  detectedFormat: 'solis_status_html' | 'home_assistant_json' | 'json_bridge' | 'status_text';
  loggerSerial?: string;
  inverterSerial?: string;
  esimNumber?: string;
  plantName?: string;
  modelName?: string;
  installedCapacityKwp?: number;
  exportTariffInr?: number;
  todayGenKwh?: number;
  livePowerKw?: number;
  todayUsageKwh?: number;
  todayExportKwh?: number;
  todayImportKwh?: number;
  lifetimeKwh?: number;
  hasSmartMeter: boolean;
  matchedBySerial?: boolean;
  summaryNote: string;
}

export interface LoggerParserHints {
  loggerSerial?: string;
  inverterSerial?: string;
  plantName?: string;
}

function parseFiniteNumber(raw: unknown): number | undefined {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : undefined;
  }
  if (typeof raw === 'string') {
    const cleaned = raw.replace(/,/g, '').trim();
    if (!cleaned || cleaned === '--' || cleaned.toLowerCase() === 'unknown' || cleaned.toLowerCase() === 'unavailable') {
      return undefined;
    }
    const match = cleaned.match(/-?\d+(?:\.\d+)?/);
    if (!match) return undefined;
    const n = Number(match[0]);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

function normalizeEnergyToKwh(val: number | undefined, unitHint?: string): number | undefined {
  if (val === undefined || val < 0) return undefined;
  const u = (unitHint || '').trim().toLowerCase();
  if (u === 'mwh') return Number((val * 1000).toFixed(2));
  if (u === 'wh') return Number((val / 1000).toFixed(2));
  if (u === 'gwh') return Number((val * 1_000_000).toFixed(2));
  return Number(val.toFixed(2));
}

function normalizePowerToKw(val: number | undefined, unitHint?: string, defaultAssumeWattsIfLarge = true): number | undefined {
  if (val === undefined) return undefined;
  const absVal = Math.max(0, val);
  const u = (unitHint || '').trim().toLowerCase();
  if (u === 'w' || u === 'watt' || u === 'watts') {
    return Number((absVal / 1000).toFixed(2));
  }
  if (u === 'kw' || u === 'kilowatt' || u === 'kilowatts') {
    return Number(absVal.toFixed(2));
  }
  if (u === 'mw') {
    return Number((absVal * 1000).toFixed(2));
  }
  // Solis status.html `webdata_now_p` is reported in Watts (e.g., 3240 W)
  if (defaultAssumeWattsIfLarge && absVal > 60) {
    return Number((absVal / 1000).toFixed(2));
  }
  return Number(absVal.toFixed(2));
}

/**
 * Infers rated plant/inverter kWp from common solar inverter model codes
 * (e.g., Solis S6-GR1P5K, Solis-3P10K-4G, S5-GR1P3.6K, Deye SUN-5K-SG04LP1,
 * Sungrow SG5.0RS, Growatt MIN 5000TL-X, GoodWe GW5000-NS).
 */
export function inferCapacityKwpFromModelName(modelName?: string): number | undefined {
  const raw = (modelName || '').trim();
  if (!raw || raw.length < 3) return undefined;

  // Pattern 1: Explicit kW / kWp / K token inside Solis/Deye/Fronius model codes (e.g. 1P5K, 3P10K, SUN-6K, 3.6K)
  const kwMatch = raw.match(/(?:^|[^0-9.])(?:1P|3P|GR1P|GR3P|EH1P|EH3P|SUN-|SG|MIN|MOD|MID|Primo\s*|Symo\s*)(\d+(?:\.\d+)?)\s*(?:kWp|kW|K)(?:[^a-zA-Z0-9]|$|-)/i);
  if (kwMatch && kwMatch[1]) {
    const val = Number(kwMatch[1]);
    if (Number.isFinite(val) && val >= 0.5 && val <= 500) {
      return Number(val.toFixed(2));
    }
  }

  // Pattern 2: Generic "<num>kW" or "<num>kWp" anywhere in model string
  const explicitUnitMatch = raw.match(/\b(\d+(?:\.\d+)?)\s*(kWp|kW)\b/i);
  if (explicitUnitMatch && explicitUnitMatch[1]) {
    const val = Number(explicitUnitMatch[1]);
    if (Number.isFinite(val) && val >= 0.5 && val <= 500) {
      return Number(val.toFixed(2));
    }
  }

  // Pattern 3: Watt-based model codes (e.g., GW5000-NS, MIN 3000TL-X, SB5000TL)
  const wattCodeMatch = raw.match(/(?:GW|MIN|MOD|MID|MIC|SB|STP|TL|SG|SPH|SPH-)\s*(\d{4,5})(?:[^0-9]|$)/i);
  if (wattCodeMatch && wattCodeMatch[1]) {
    const watts = Number(wattCodeMatch[1]);
    if (Number.isFinite(watts) && watts >= 1000 && watts <= 100000 && watts % 100 === 0) {
      return Number((watts / 1000).toFixed(2));
    }
  }

  return undefined;
}

function readNumByKeys(obj: Record<string, unknown>, keys: string[]): number | undefined {
  const lowerMap = new Map<string, unknown>();
  for (const [k, v] of Object.entries(obj)) {
    lowerMap.set(k.toLowerCase().replace(/[^a-z0-9]/g, ''), v);
  }
  for (const key of keys) {
    if (key in obj) {
      const n = parseFiniteNumber(obj[key]);
      if (n !== undefined && n >= 0) return n;
    }
    const normKey = key.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (lowerMap.has(normKey)) {
      const n = parseFiniteNumber(lowerMap.get(normKey));
      if (n !== undefined && n >= 0) return n;
    }
  }
  return undefined;
}

function readStrByKeys(obj: Record<string, unknown>, keys: string[]): string | undefined {
  const lowerMap = new Map<string, unknown>();
  for (const [k, v] of Object.entries(obj)) {
    lowerMap.set(k.toLowerCase().replace(/[^a-z0-9]/g, ''), v);
  }
  for (const key of keys) {
    const val = key in obj ? obj[key] : lowerMap.get(key.toLowerCase().replace(/[^a-z0-9]/g, ''));
    if (typeof val === 'string' && val.trim()) return val.trim().slice(0, 80);
    if (typeof val === 'number' && Number.isFinite(val)) return String(val).slice(0, 80);
  }
  return undefined;
}

/**
 * 1. Parse Home Assistant REST `/api/states` JSON array
 */
function parseHomeAssistantStates(
  states: unknown[],
  hints?: LoggerParserHints
): ParsedLoggerTelemetry | null {
  interface HaEntity {
    entity_id: string;
    state: string;
    attributes?: {
      unit_of_measurement?: string;
      friendly_name?: string;
      device_class?: string;
    };
  }

  const entities: HaEntity[] = states.filter(
    (item): item is HaEntity =>
      Boolean(item) &&
      typeof item === 'object' &&
      typeof (item as HaEntity).entity_id === 'string' &&
      typeof (item as HaEntity).state === 'string'
  );

  if (entities.length === 0) return null;

  const cleanSerial = (hints?.loggerSerial || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const cleanInverterSn = (hints?.inverterSerial || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const cleanPlant = (hints?.plantName || '').toLowerCase().replace(/[^a-z0-9]/g, '');

  // Prefer entities matching loggerSerial, inverterSerial, or plantName when multiple inverters exist
  const scoreEntity = (e: HaEntity): number => {
    const hay = `${e.entity_id} ${e.attributes?.friendly_name || ''}`.toLowerCase();
    const compactHay = hay.replace(/[^a-z0-9]/g, '');
    let score = 0;
    if (cleanSerial && cleanSerial.length >= 4 && compactHay.includes(cleanSerial)) score += 20;
    if (cleanInverterSn && cleanInverterSn.length >= 4 && compactHay.includes(cleanInverterSn)) score += 20;
    if (cleanPlant && cleanPlant.length >= 3 && compactHay.includes(cleanPlant)) score += 10;
    if (/solis|solarman|inverter|pv|solar|growatt|sungrow|goodwe|fronius|enphase/.test(hay)) score += 4;
    return score;
  };

  const findBestMetric = (
    patterns: RegExp[],
    excludePatterns: RegExp[],
    converter: (val: number, unit?: string) => number | undefined
  ): { value: number; matchedSerial: boolean } | undefined => {
    let best: { value: number; score: number; matchedSerial: boolean } | undefined;
    for (const e of entities) {
      if (!e.entity_id.startsWith('sensor.')) continue;
      const hay = `${e.entity_id} ${e.attributes?.friendly_name || ''}`.toLowerCase();
      if (excludePatterns.some((rx) => rx.test(hay))) continue;
      if (!patterns.some((rx) => rx.test(hay))) continue;
      const rawNum = parseFiniteNumber(e.state);
      if (rawNum === undefined || rawNum < 0) continue;
      const converted = converter(rawNum, e.attributes?.unit_of_measurement);
      if (converted === undefined) continue;
      const s = scoreEntity(e);
      const compactHay = hay.replace(/[^a-z0-9]/g, '');
      const matchedSerial = Boolean(
        (cleanSerial && cleanSerial.length >= 4 && compactHay.includes(cleanSerial)) ||
          (cleanInverterSn && cleanInverterSn.length >= 4 && compactHay.includes(cleanInverterSn))
      );
      if (!best || s > best.score) {
        best = { value: converted, score: s, matchedSerial };
      }
    }
    return best ? { value: best.value, matchedSerial: best.matchedSerial } : undefined;
  };

  const todayGen = findBestMetric(
    [
      /energy[_\s-]*today/,
      /daily[_\s-]*(?:yield|generation|energy|production|solar|pv)/,
      /(?:solar|pv|inverter)[_\s-]*(?:energy|generation|yield)[_\s-]*today/,
      /today[_\s-]*(?:yield|generation|energy|production|solar|pv)/,
      /e[_\s-]*today/,
    ],
    [/export|import|grid|load|consumption|house|home|battery|buy|sell|purchased/],
    (v, u) => normalizeEnergyToKwh(v, u)
  );

  const livePower = findBestMetric(
    [
      /(?:ac|pv|solar|inverter|generation|production)[_\s-]*power/,
      /power[_\s-]*(?:ac|pv|solar|generation|output|now)/,
      /current[_\s-]*power/,
      /webdata[_\s-]*now[_\s-]*p/,
    ],
    [/export|import|grid|load|consumption|house|home|battery|reactive|apparent|daily|today|total/],
    (v, u) => normalizePowerToKw(v, u, true)
  );

  const todayUsage = findBestMetric(
    [
      /(?:home|house|family|daily|today)[_\s-]*(?:load|consumption|usage)[_\s-]*(?:energy|today|daily)?/,
      /(?:load|consumption|usage)[_\s-]*(?:energy[_\s-]*)?(?:today|daily)/,
    ],
    [/power|watt|export|import|battery/],
    (v, u) => normalizeEnergyToKwh(v, u)
  );

  const todayExport = findBestMetric(
    [
      /(?:grid|daily|today)[_\s-]*(?:export|feed[_\s-]*in|sell)[_\s-]*(?:energy|today|daily)?/,
      /(?:export|feed[_\s-]*in|sell)[_\s-]*(?:energy[_\s-]*)?(?:today|daily)/,
    ],
    [/power|watt|total|lifetime/],
    (v, u) => normalizeEnergyToKwh(v, u)
  );

  const todayImport = findBestMetric(
    [
      /(?:grid|daily|today)[_\s-]*(?:import|purchased|buy)[_\s-]*(?:energy|today|daily)?/,
      /(?:import|purchased|buy)[_\s-]*(?:energy[_\s-]*)?(?:today|daily)/,
    ],
    [/power|watt|total|lifetime/],
    (v, u) => normalizeEnergyToKwh(v, u)
  );

  const lifetime = findBestMetric(
    [
      /(?:total|lifetime|cumulative)[_\s-]*(?:yield|generation|energy|production)/,
      /(?:solar|pv|inverter)[_\s-]*(?:total|lifetime)[_\s-]*(?:energy|yield|generation)/,
      /e[_\s-]*total/,
    ],
    [/export|import|grid|load|consumption|battery/],
    (v, u) => normalizeEnergyToKwh(v, u)
  );

  // Optional installed capacity / rated power & export tariff sensors in Home Assistant
  const capacityMetric = findBestMetric(
    [
      /(?:installed|plant|system|pv|solar|inverter)[_\s-]*(?:capacity|size|rated[_\s-]*power)/,
      /rated[_\s-]*power/,
    ],
    [/battery|storage|soc/],
    (v, u) => normalizePowerToKw(v, u, true)
  );

  const exportTariffMetric = findBestMetric(
    [
      /(?:export|feed[_\s-]*in|sell)[_\s-]*(?:tariff|rate|price|credit)/,
    ],
    [/power|energy|kwh|today|total/],
    (v) => (v >= 0 && v <= 50 ? Number(v.toFixed(2)) : undefined)
  );

  // Try to detect serial number & model entity in Home Assistant
  let detectedSerial: string | undefined;
  let detectedModel: string | undefined;
  for (const e of entities) {
    const hay = `${e.entity_id} ${e.attributes?.friendly_name || ''}`.toLowerCase();
    if (!detectedSerial && /(?:logger|collector|inverter|solis|solarman)[_\s-]*(?:sn|serial)/.test(hay)) {
      const s = e.state.trim();
      if (s && s.length >= 5 && s.length <= 64 && !/^(unknown|unavailable|none)$/i.test(s)) {
        detectedSerial = s;
      }
    }
    if (!detectedModel && /(?:inverter|solis|solarman)[_\s-]*model/.test(hay)) {
      const m = e.state.trim();
      if (m && m.length >= 3 && m.length <= 64 && !/^(unknown|unavailable|none)$/i.test(m)) {
        detectedModel = m;
      }
    }
  }

  if (
    todayGen === undefined &&
    livePower === undefined &&
    lifetime === undefined &&
    todayUsage === undefined
  ) {
    return null;
  }

  const hasSmartMeter =
    todayUsage !== undefined || todayExport !== undefined || todayImport !== undefined;
  const matchedBySerial = Boolean(todayGen?.matchedSerial || livePower?.matchedSerial);
  const resolvedCapacity =
    capacityMetric?.value !== undefined && capacityMetric.value >= 0.1 && capacityMetric.value <= 5000
      ? capacityMetric.value
      : inferCapacityKwpFromModelName(detectedModel);

  return {
    detectedFormat: 'home_assistant_json',
    loggerSerial: detectedSerial || hints?.loggerSerial,
    plantName: hints?.plantName,
    modelName: detectedModel,
    installedCapacityKwp: resolvedCapacity,
    exportTariffInr: exportTariffMetric?.value,
    todayGenKwh: todayGen?.value,
    livePowerKw: livePower?.value,
    todayUsageKwh: todayUsage?.value,
    todayExportKwh: todayExport?.value,
    todayImportKwh: todayImport?.value,
    lifetimeKwh: lifetime?.value,
    hasSmartMeter,
    matchedBySerial,
    summaryNote: matchedBySerial
      ? `Home Assistant sync matched logger ${hints?.loggerSerial}`
      : 'Synced from Home Assistant solar entities',
  };
}

/**
 * 2. Parse Generic / SolarAssistant / Node-RED JSON Bridge Payload
 */
function parseJsonBridgeObject(
  raw: Record<string, unknown>,
  hints?: LoggerParserHints
): ParsedLoggerTelemetry | null {
  // Support `{ devices: [...] }` or `{ inverters: [...] }` array lookup by loggerSerial, inverterSerial, or plantName
  const listCandidate =
    (Array.isArray(raw.devices) && raw.devices) ||
    (Array.isArray(raw.inverters) && raw.inverters) ||
    (Array.isArray(raw.stations) && raw.stations) ||
    (Array.isArray(raw.plants) && raw.plants) ||
    (Array.isArray(raw.records) && raw.records) ||
    null;

  let dataObj: Record<string, unknown> =
    raw.data && typeof raw.data === 'object' && !Array.isArray(raw.data)
      ? (raw.data as Record<string, unknown>)
      : raw;

  let matchedBySerial = false;
  if (listCandidate && listCandidate.length > 0) {
    const cleanSerial = (hints?.loggerSerial || '').trim().toLowerCase();
    const cleanInverterSn = (hints?.inverterSerial || '').trim().toLowerCase();
    const cleanPlant = (hints?.plantName || '').trim().toLowerCase();
    const objItems = listCandidate.filter(
      (x): x is Record<string, unknown> => Boolean(x) && typeof x === 'object' && !Array.isArray(x)
    );
    const bySerial =
      cleanSerial || cleanInverterSn
        ? objItems.find((item) => {
            const loggerSn = (
              readStrByKeys(item, ['loggerSerial', 'collectorSn', 'logger_sn', 'cover_mid', 'deviceSn']) ||
              ''
            ).toLowerCase();
            const invSn = (
              readStrByKeys(item, ['inverterSerial', 'inverter_sn', 'webdata_sn', 'sn', 'serialNumber']) ||
              ''
            ).toLowerCase();
            return (
              (cleanSerial && loggerSn && (loggerSn === cleanSerial || loggerSn.includes(cleanSerial))) ||
              (cleanInverterSn && invSn && (invSn === cleanInverterSn || invSn.includes(cleanInverterSn))) ||
              (cleanSerial && invSn && (invSn === cleanSerial || invSn.includes(cleanSerial)))
            );
          })
        : undefined;
    const byPlant =
      !bySerial && cleanPlant
        ? objItems.find((item) => {
            const pn = (
              readStrByKeys(item, ['plantName', 'stationName', 'name', 'siteName']) || ''
            ).toLowerCase();
            return pn === cleanPlant || (pn && pn.includes(cleanPlant));
          })
        : undefined;
    if (bySerial) {
      dataObj = bySerial;
      matchedBySerial = true;
    } else if (byPlant) {
      dataObj = byPlant;
    } else if (objItems[0]) {
      dataObj = objItems[0];
    }
  }

  const todayGenKwh = readNumByKeys(dataObj, [
    'todayGenKwh',
    'today_gen_kwh',
    'generation_kwh',
    'generationValue',
    'pv_today_kwh',
    'daily_yield_kwh',
    'dailyYield',
    'eToday',
    'dayEnergy',
    'today_energy',
    'webdata_today_e',
    'daily_generation',
  ]);

  const rawPowerKw = readNumByKeys(dataObj, [
    'livePowerKw',
    'live_power_kw',
    'power_kw',
    'pv_power_kw',
    'ac_power_kw',
    'pac_kw',
  ]);
  const rawPowerW = readNumByKeys(dataObj, [
    'livePowerW',
    'live_power_w',
    'power_w',
    'pv_power_w',
    'ac_power_w',
    'generationPower',
    'current_power',
    'webdata_now_p',
    'pac',
    'power',
  ]);
  const livePowerKw =
    rawPowerKw !== undefined
      ? Number(rawPowerKw.toFixed(2))
      : rawPowerW !== undefined
        ? normalizePowerToKw(rawPowerW, 'W', true)
        : undefined;

  const todayUsageKwh = readNumByKeys(dataObj, [
    'todayUsageKwh',
    'today_usage_kwh',
    'consumption_kwh',
    'load_today_kwh',
    'home_load_kwh',
    'homeLoadTodayEnergy',
    'useValue',
    'today_load_energy',
  ]);

  const todayExportKwh = readNumByKeys(dataObj, [
    'todayExportKwh',
    'today_export_kwh',
    'export_kwh',
    'grid_export_kwh',
    'feed_in_kwh',
    'gridSellTodayEnergy',
    'wireValue',
    'today_export_energy',
  ]);

  const todayImportKwh = readNumByKeys(dataObj, [
    'todayImportKwh',
    'today_import_kwh',
    'import_kwh',
    'grid_import_kwh',
    'gridPurchasedTodayEnergy',
    'buyValue',
    'today_import_energy',
  ]);

  const lifetimeKwh = readNumByKeys(dataObj, [
    'lifetimeKwh',
    'lifetime_kwh',
    'total_kwh',
    'total_energy',
    'generationTotal',
    'eTotal',
    'allEnergy',
    'webdata_total_e',
  ]);

  const rawCapacityKwp = readNumByKeys(dataObj, [
    'installedCapacityKwp',
    'capacity_kwp',
    'capacity',
    'stationCapacity',
    'plantCapacity',
    'ratedPowerKw',
    'systemCapacityKwp',
  ]);
  const rawRatedPowerW = readNumByKeys(dataObj, ['ratedPowerW', 'rated_power_w', 'webdata_rate_p']);
  const exportTariffInr = readNumByKeys(dataObj, [
    'exportTariffInr',
    'export_tariff_inr',
    'feedInTariff',
    'feed_in_tariff',
    'exportRate',
    'sellPrice',
  ]);

  const loggerSerial = readStrByKeys(dataObj, [
    'loggerSerial',
    'collectorSn',
    'logger_sn',
    'cover_mid',
    'deviceSn',
  ]);
  const inverterSerial = readStrByKeys(dataObj, [
    'inverterSerial',
    'inverter_sn',
    'webdata_sn',
    'sn',
    'serialNumber',
  ]);
  const plantName = readStrByKeys(dataObj, ['plantName', 'stationName', 'siteName', 'name']);
  const modelName = readStrByKeys(dataObj, ['model', 'modelName', 'inverterModel', 'webdata_msvn']);

  const installedCapacityKwp =
    rawCapacityKwp !== undefined && rawCapacityKwp >= 0.1 && rawCapacityKwp <= 5000
      ? Number(rawCapacityKwp.toFixed(2))
      : rawRatedPowerW !== undefined && rawRatedPowerW >= 100
        ? normalizePowerToKw(rawRatedPowerW, 'W', true)
        : inferCapacityKwpFromModelName(modelName);

  if (
    todayGenKwh === undefined &&
    livePowerKw === undefined &&
    lifetimeKwh === undefined &&
    todayUsageKwh === undefined
  ) {
    return null;
  }

  const hasSmartMeter =
    todayUsageKwh !== undefined || todayExportKwh !== undefined || todayImportKwh !== undefined;

  return {
    detectedFormat: 'json_bridge',
    loggerSerial: loggerSerial || hints?.loggerSerial,
    inverterSerial: inverterSerial || hints?.inverterSerial,
    plantName: plantName || hints?.plantName,
    modelName,
    installedCapacityKwp,
    exportTariffInr:
      exportTariffInr !== undefined && exportTariffInr >= 0 && exportTariffInr <= 50
        ? Number(exportTariffInr.toFixed(2))
        : undefined,
    todayGenKwh: todayGenKwh !== undefined ? Number(todayGenKwh.toFixed(2)) : undefined,
    livePowerKw,
    todayUsageKwh: todayUsageKwh !== undefined ? Number(todayUsageKwh.toFixed(2)) : undefined,
    todayExportKwh: todayExportKwh !== undefined ? Number(todayExportKwh.toFixed(2)) : undefined,
    todayImportKwh: todayImportKwh !== undefined ? Number(todayImportKwh.toFixed(2)) : undefined,
    lifetimeKwh: lifetimeKwh !== undefined ? Number(lifetimeKwh.toFixed(1)) : undefined,
    hasSmartMeter,
    matchedBySerial,
    summaryNote: matchedBySerial
      ? `Bridge sync matched ${loggerSerial || inverterSerial || hints?.loggerSerial || hints?.inverterSerial}`
      : 'Synced live telemetry from Solar JSON Bridge',
  };
}

/**
 * 3. Parse Solis (S2-WL-ST / S3-WIFI-ST) & Solarman (LSW-3) `status.html` JS variables
 *    or plain key-value text copied directly from the logger's browser status page.
 */
function parseSolisStatusHtmlOrText(
  rawText: string,
  hints?: LoggerParserHints
): ParsedLoggerTelemetry | null {
  const extractJsVar = (varNames: string[]): string | undefined => {
    for (const name of varNames) {
      const rx = new RegExp(`(?:var\\s+)?${name}\\s*=\\s*["']?([^"';\\r\\n]+)["']?`, 'i');
      const m = rawText.match(rx);
      if (m && m[1] !== undefined) {
        const val = m[1].trim();
        if (val && val !== '--' && val.toLowerCase() !== 'null') return val;
      }
    }
    return undefined;
  };

  const jsLoggerSn = extractJsVar(['cover_mid', 'myDeviceSn', 'logger_sn']);
  const jsInverterSn = extractJsVar(['webdata_sn', 'inverter_sn']);
  const jsNowP = extractJsVar(['webdata_now_p', 'now_p']);
  const jsTodayE = extractJsVar(['webdata_today_e', 'today_e']);
  const jsTotalE = extractJsVar(['webdata_total_e', 'total_e']);
  const jsRateP = extractJsVar(['webdata_rate_p', 'rated_p', 'rated_power']);
  const jsModel = extractJsVar(['webdata_msvn', 'webdata_model', 'cover_ver']);

  if (jsNowP !== undefined || jsTodayE !== undefined || jsTotalE !== undefined || jsInverterSn !== undefined) {
    const todayGenKwh = normalizeEnergyToKwh(parseFiniteNumber(jsTodayE));
    const livePowerKw = normalizePowerToKw(parseFiniteNumber(jsNowP), 'W', true);
    const lifetimeKwh = normalizeEnergyToKwh(parseFiniteNumber(jsTotalE));
    const ratedKwFromJs = normalizePowerToKw(parseFiniteNumber(jsRateP), undefined, true);
    const detectedCapacity =
      ratedKwFromJs !== undefined && ratedKwFromJs >= 0.1 && ratedKwFromJs <= 5000
        ? ratedKwFromJs
        : inferCapacityKwpFromModelName(jsModel);

    if (todayGenKwh !== undefined || livePowerKw !== undefined || lifetimeKwh !== undefined) {
      const cleanLoggerHint = (hints?.loggerSerial || '').trim().toLowerCase();
      const cleanInverterHint = (hints?.inverterSerial || '').trim().toLowerCase();
      const matchedBySerial = Boolean(
        (cleanLoggerHint && jsLoggerSn && jsLoggerSn.toLowerCase().includes(cleanLoggerHint)) ||
          (cleanInverterHint && jsInverterSn && jsInverterSn.toLowerCase().includes(cleanInverterHint)) ||
          (cleanLoggerHint && jsInverterSn && jsInverterSn.toLowerCase().includes(cleanLoggerHint))
      );

      return {
        detectedFormat: 'solis_status_html',
        loggerSerial: jsLoggerSn || hints?.loggerSerial,
        inverterSerial: jsInverterSn || hints?.inverterSerial,
        plantName: hints?.plantName,
        modelName: jsModel,
        installedCapacityKwp: detectedCapacity,
        todayGenKwh,
        livePowerKw,
        lifetimeKwh,
        hasSmartMeter: false,
        matchedBySerial,
        summaryNote: jsInverterSn
          ? `Solis Wi-Fi Logger status (Inv ${jsInverterSn}${jsLoggerSn ? ` · Log ${jsLoggerSn}` : ''})`
          : jsLoggerSn
            ? `Solis Wi-Fi Logger status (${jsLoggerSn})`
            : 'Solis / Solarman Wi-Fi Logger status.html',
      };
    }
  }

  // Plain-text parser for copied Solis local status page OR SolisCloud web portal text
  const matchLabelNumber = (
    patterns: RegExp[]
  ): { num: number; unit?: string } | undefined => {
    for (const rx of patterns) {
      const m = rawText.match(rx);
      if (m && m[1]) {
        const num = parseFiniteNumber(m[1]);
        if (num !== undefined && num >= 0) {
          return { num, unit: m[2]?.trim() };
        }
      }
    }
    return undefined;
  };

  const loggerSnMatch = rawText.match(
    /(?:data\s*logger|logger|collector|stick)\s*(?:s\/?n|serial(?:\s*number)?|no\.?)\s*[:=\-]?\s*([A-Z0-9\-_]{5,32})/i
  );
  const inverterSnMatch = rawText.match(
    /(?:inverter|device)\s*(?:s\/?n|serial(?:\s*number)?|no\.?)\s*[:=\-]?\s*([A-Z0-9\-_]{5,32})/i
  );
  const esimMatch = rawText.match(
    /(?:iccid|e-?sim(?:\s*(?:no\.?|number|id))?)\s*[:=\-]?\s*([A-Z0-9\-]{10,24})/i
  );

  const todayMatch = matchLabelNumber([
    /(?:yield\s*today|today'?s?\s*(?:yield|generation|energy)|daily\s*(?:yield|generation|energy|production)|e[_\s-]*today)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kWh|Wh|MWh)?/i,
    /(\d+(?:\.\d+)?)\s*(kWh|MWh)\s*(?:yield\s*today|daily\s*yield|today)/i,
  ]);
  const powerMatch = matchLabelNumber([
    /(?:current\s*power|active\s*power|output\s*power|live\s*power|total\s*ac\s*output\s*power|pv\s*power|inverter\s*power|pac)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kW|W|MW)?/i,
  ]);
  const totalMatch = matchLabelNumber([
    /(?:total\s*(?:yield|generation|energy|production)|cumulative\s*(?:yield|generation|energy)|lifetime\s*(?:yield|energy)|e[_\s-]*total)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kWh|Wh|MWh|GWh)?/i,
  ]);
  const usageMatch = matchLabelNumber([
    /(?:home\s*load|load\s*today|consumption\s*today|daily\s*(?:load|consumption)|usage\s*today)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kWh|Wh|MWh)?/i,
  ]);
  const exportMatch = matchLabelNumber([
    /(?:grid\s*export|feed[\s-]*in\s*(?:today|energy)|export\s*today|daily\s*grid\s*feed[\s-]*in|grid\s*sell)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kWh|Wh|MWh)?/i,
  ]);
  const importMatch = matchLabelNumber([
    /(?:grid\s*import|purchased\s*(?:today|energy)|import\s*today|daily\s*grid\s*purchased|grid\s*buy)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kWh|Wh|MWh)?/i,
  ]);

  const modelMatch = rawText.match(
    /(?:inverter\s*model|device\s*model|model(?:\s*name)?)\s*[:=\-]?\s*([A-Z0-9\-_. ]{3,48})/i
  );
  const capacityMatch = matchLabelNumber([
    /(?:installed\s*capacity|plant\s*(?:capacity|size)|system\s*(?:capacity|size)|rated\s*(?:power|capacity)|capacity)\s*[:=\-]?\s*(\d+(?:,\d+)*(?:\.\d+)?)\s*(kWp|kW|W|MW)?/i,
  ]);
  const exportTariffMatch = matchLabelNumber([
    /(?:export\s*(?:tariff|credit|rate)|feed[\s-]*in\s*(?:tariff|rate)|sell\s*price)\s*[:=\-]?\s*(?:₹|Rs\.?|INR)?\s*(\d+(?:\.\d+)?)/i,
  ]);

  const todayGenKwh = todayMatch ? normalizeEnergyToKwh(todayMatch.num, todayMatch.unit) : undefined;
  const livePowerKw = powerMatch ? normalizePowerToKw(powerMatch.num, powerMatch.unit, true) : undefined;
  const lifetimeKwh = totalMatch ? normalizeEnergyToKwh(totalMatch.num, totalMatch.unit) : undefined;
  const todayUsageKwh = usageMatch ? normalizeEnergyToKwh(usageMatch.num, usageMatch.unit) : undefined;
  const todayExportKwh = exportMatch ? normalizeEnergyToKwh(exportMatch.num, exportMatch.unit) : undefined;
  const todayImportKwh = importMatch ? normalizeEnergyToKwh(importMatch.num, importMatch.unit) : undefined;
  const detectedModelName = modelMatch?.[1]?.trim();
  const detectedCapacityFromText = capacityMatch
    ? normalizePowerToKw(capacityMatch.num, capacityMatch.unit || 'kW', true)
    : inferCapacityKwpFromModelName(detectedModelName);
  const detectedExportTariffInr =
    exportTariffMatch && exportTariffMatch.num >= 0 && exportTariffMatch.num <= 50
      ? Number(exportTariffMatch.num.toFixed(2))
      : undefined;

  if (
    todayGenKwh === undefined &&
    livePowerKw === undefined &&
    lifetimeKwh === undefined &&
    todayUsageKwh === undefined
  ) {
    return null;
  }

  const hasSmartMeter =
    todayUsageKwh !== undefined || todayExportKwh !== undefined || todayImportKwh !== undefined;

  return {
    detectedFormat: 'status_text',
    loggerSerial: loggerSnMatch?.[1]?.trim() || hints?.loggerSerial,
    inverterSerial: inverterSnMatch?.[1]?.trim() || hints?.inverterSerial,
    esimNumber: esimMatch?.[1]?.trim(),
    plantName: hints?.plantName,
    modelName: detectedModelName,
    installedCapacityKwp:
      detectedCapacityFromText !== undefined && detectedCapacityFromText >= 0.1 && detectedCapacityFromText <= 5000
        ? detectedCapacityFromText
        : undefined,
    exportTariffInr: detectedExportTariffInr,
    todayGenKwh,
    livePowerKw,
    todayUsageKwh,
    todayExportKwh,
    todayImportKwh,
    lifetimeKwh,
    hasSmartMeter,
    summaryNote: 'Synced from Solis logger / portal status text',
  };
}

/**
 * Unified entry point used by both the Express HTTPS Bridge proxy and browser Local Wi-Fi IP reader.
 */
export function parseLoggerPayload(
  rawBody: string,
  hints?: LoggerParserHints
): ParsedLoggerTelemetry | null {
  const trimmed = (rawBody || '').trim();
  if (!trimmed) return null;

  // Attempt JSON parsing first (Home Assistant / SolarAssistant / Node-RED / custom JSON bridge)
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        const haResult = parseHomeAssistantStates(parsed, hints);
        if (haResult) return haResult;
        // Fallback: array of device objects
        const wrapped = parseJsonBridgeObject({ devices: parsed }, hints);
        if (wrapped) return wrapped;
      } else if (parsed && typeof parsed === 'object') {
        const obj = parsed as Record<string, unknown>;
        // Single Home Assistant entity state `{ entity_id, state, attributes }`
        if (typeof obj.entity_id === 'string' && typeof obj.state === 'string') {
          const haSingle = parseHomeAssistantStates([obj], hints);
          if (haSingle) return haSingle;
        }
        const jsonResult = parseJsonBridgeObject(obj, hints);
        if (jsonResult) return jsonResult;
      }
    } catch {
      // Fall through to HTML/text parser
    }
  }

  return parseSolisStatusHtmlOrText(trimmed, hints);
}
