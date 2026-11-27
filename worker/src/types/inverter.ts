/**
 * Universal Multi-Brand Solar Inverter Sync Hub — Domain Types
 */

export type InverterBrandId =
  | 'solarman'
  | 'growatt'
  | 'soliscloud'
  | 'sungrow'
  | 'goodwe'
  | 'fronius'
  | 'enphase'
  | 'custom_bridge';

export type InverterMeterMode = 'auto' | 'generation_only' | 'full_meter';

export type LoggerConnectivityType = 'wifi' | 'esim' | 'lan';

export type LoggerConnectionMode = 'local_wifi_ip' | 'https_bridge' | 'cloud_api';

export type InverterSyncSource =
  | 'local_logger'
  | 'https_bridge'
  | 'manual_entry'
  | 'cloud_api'
  // Legacy read-only compatibility for any previously saved Firestore documents
  | 'app_screenshot'
  | 'csv_import';

export type InverterHubTab = 'logger_sync' | 'manual_entry' | 'daily_logs';

export type InverterAuthMode = 'website' | 'api';

/**
 * Ephemeral in-memory credentials for Manufacturer Website Login or API Integration during the active session.
 * Never persisted to Firestore, localStorage, or sessionStorage.
 */
export interface LoggerSessionCredentials {
  authMode?: InverterAuthMode;
  username?: string;
  password?: string;
  apiKey?: string;
  apiSecret?: string;
  region?: string;
}

export interface InverterPvStringReading {
  id: string;
  voltageV?: number;
  currentA?: number;
  powerW?: number;
}

export interface InverterExtendedTelemetry {
  inverterStatus?: 'online' | 'standby' | 'fault' | 'offline' | 'unknown';
  inverterStatusText?: string;
  inverterModel?: string;
  firmwareVersion?: string;
  loggerStatus?: 'online' | 'offline' | 'unknown';
  loggerSignalPct?: number;
  serialMatchVerified?: boolean;
  matchedInverterSerial?: string;
  matchedLoggerSerial?: string;
  inverterTempC?: number;
  gridVoltageV?: number;
  gridVoltageR?: number;
  gridVoltageS?: number;
  gridVoltageT?: number;
  acCurrentA?: number;
  gridFrequencyHz?: number;
  powerFactor?: number;
  monthGenKwh?: number;
  yearGenKwh?: number;
  peakPowerKw?: number;
  batterySocPct?: number;
  batteryPowerKw?: number;
  batteryVoltageV?: number;
  batteryTempC?: number;
  todayBatteryChargeKwh?: number;
  todayBatteryDischargeKwh?: number;
  pvStrings?: InverterPvStringReading[];
  faultCode?: string;
  faultMessage?: string;
  portalRegion?: string;
}

export interface DiscoveredCloudPlant {
  stationId: string;
  plantName: string;
  capacityKwp?: number;
  inverterSerial?: string;
  loggerSerial?: string;
  status?: string;
}

export type LoggerHealthStatus =
  | 'checking'
  | 'cloud_online'
  | 'stable_wifi'
  | 'slow_wifi'
  | 'stable_lan'
  | 'slow_lan'
  | 'esim_active'
  | 'esim_sync_due'
  | 'bridge_online'
  | 'lan_restricted'
  | 'sync_stale'
  | 'disconnected';

export type LoggerHealthTone = 'healthy' | 'caution' | 'offline' | 'checking';

export type SyncQualityGrade = 'Excellent' | 'Good' | 'Fair' | 'Stale' | 'Offline';

export interface LoggerPingOutcome {
  reachable: boolean;
  latencyMs: number | null;
  checkedAtIso: string;
  probePath: 'local_browser' | 'https_bridge_proxy' | 'cloud_portal' | 'esim_passive' | 'unconfigured';
  blockedByBrowserCors?: boolean;
  authRequired?: boolean;
  httpStatus?: number;
  error?: string;
}

export interface LoggerConnectionHealthSnapshot {
  status: LoggerHealthStatus;
  label: string;
  tone: LoggerHealthTone;
  quality: SyncQualityGrade;
  latencyMs: number | null;
  lastSyncAgeLabel: string;
  detail: string;
  checkedAtIso: string;
  probePath: LoggerPingOutcome['probePath'];
}

export interface InverterProviderCatalogItem {
  id: InverterBrandId;
  name: string;
  portalName: string;
  subBrands: string;
  cloudApiConfigured: boolean;
  cloudApiMode: 'native_api' | 'custom_bridge';
  requiredFields: Array<'stationId' | 'loggerSerial'>;
  envVars: string[];
}

export interface InverterPlantProfile {
  id: string;
  brand: InverterBrandId;
  plantName: string;
  stationId?: string;
  loggerSerial?: string;
  inverterSerial?: string;
  esimNumber?: string;
  loggerConnectivity?: LoggerConnectivityType;
  loggerConnectionMode?: LoggerConnectionMode;
  /**
   * Non-secret bridge HTTPS URL (e.g. https://solar.example.com/status.html) or
   * Local Wi-Fi logger IP/URL (e.g. http://192.168.1.50/status.html).
   * Credentials are never stored in this field.
   */
  loggerEndpointUrl?: string;
  installedCapacityKwp: number;
  exportTariffInr: number;
  meterMode: InverterMeterMode;
  autoSyncMinutes: 0 | 5 | 15 | 30 | 60;
  hasSyncedData: boolean;
  todayDateKey: string; // YYYY-MM-DD
  todayGenKwh: number;
  livePowerKw: number;
  todayUsageKwh?: number;
  todayExportKwh?: number;
  todayImportKwh?: number;
  lifetimeKwh?: number;
  hasSmartMeter: boolean;
  syncSource: InverterSyncSource;
  lastSyncedAtIso: string;
  lastSyncedAtIst: string;
  statusNote?: string;
  extendedTelemetry?: InverterExtendedTelemetry;
  visibility?: 'public';
  ownerId?: string;
  isCloudSynced?: boolean;
}

export interface InverterDailyLog {
  dateKey: string; // YYYY-MM-DD
  plantId: string;
  generationKwh: number;
  consumptionKwh?: number;
  exportKwh?: number;
  importKwh?: number;
  peakPowerKw?: number;
  weatherPotentialKwh?: number;
  performanceRatioPct?: number;
  hasSmartMeter: boolean;
  syncSource: InverterSyncSource;
  recordedAtIso: string;
  visibility?: 'public';
  ownerId?: string;
  isCloudSynced?: boolean;
}

export interface CloudInverterSyncResponse {
  ok: boolean;
  brand: InverterBrandId;
  detectedBrand?: InverterBrandId;
  providerName?: string;
  needsServerCredentials?: boolean;
  requiresApiCredentialsHint?: boolean;
  requiresPlantSelection?: boolean;
  discoveredPlants?: DiscoveredCloudPlant[];
  requiredEnvVars?: string[];
  error?: string;
  message?: string;
  blockedByBrowserCors?: boolean;
  detectedFormat?: string;
  detectedStationId?: string;
  detectedLoggerSerial?: string;
  detectedInverterSerial?: string;
  serialMatchVerified?: boolean;
  detectedPlantName?: string;
  detectedModelName?: string;
  detectedCapacityKwp?: number;
  detectedExportTariffInr?: number;
  telemetry?: {
    dateKey: string;
    todayGenKwh: number;
    livePowerKw: number;
    todayUsageKwh?: number;
    todayExportKwh?: number;
    todayImportKwh?: number;
    lifetimeKwh?: number;
    hasSmartMeter: boolean;
    syncedAtIso: string;
    syncedAtIst: string;
    statusNote?: string;
  };
  extendedTelemetry?: InverterExtendedTelemetry;
  historicalDailyLogs?: Array<{
    dateKey: string;
    generationKwh: number;
    consumptionKwh?: number;
    exportKwh?: number;
    importKwh?: number;
    peakPowerKw?: number;
  }>;
}

/**
 * Unified telemetry snapshot consumed by WelcomeScreen, DashboardScreen,
 * SolarHeroCard, LiveSyncControlBar, TodayEnergySummaryWidgets, and all 4 detail modals.
 */
export interface ResolvedInverterTelemetry {
  isConnected: boolean;
  isTodayReading: boolean;
  plant: InverterPlantProfile | null;
  dailyLogs: InverterDailyLog[];
  brandLabel: string;
  syncSourceLabel: string;
  effectiveCapacityKwp: number;

  // Weather benchmark vs actual inverter generation
  weatherPotentialGenKwh: number;
  weatherLiveKw: number;
  actualGenKwh: number | null;
  displayGenKwh: number;
  displayLiveKw: number;
  performanceRatioPct: number | null;

  // Auto-detected CT / Smart Meter consumption & grid exchange
  hasSmartMeterActive: boolean;
  meterModeLabel: string;
  displayUsageKwh: number;
  displayLiveUsageKw: number;
  meteredUsageKwh: number | null;
  meteredExportKwh: number | null;
  meteredImportKwh: number | null;

  // Net balance & financial metrics
  selfConsumedKwh: number;
  exportedKwh: number;
  importedKwh: number;
  netBalanceKwh: number;
  isSurplus: boolean;
  solarCoveragePercent: number;

  // Real financial & carbon value
  exportTariffInr: number;
  todaySelfSavingsInr: number;
  todayExportEarningsInr: number;
  todayTotalSavingsInr: number;
  todayCo2AvoidedKg: number;
  cumulativeLoggedGenKwh: number;
  cumulativeLoggedDays: number;
}
