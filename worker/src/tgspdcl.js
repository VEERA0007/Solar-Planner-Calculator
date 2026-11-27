// TGSPDCL (Southern Telangana DISCOM) live lookup. Ported from the reference server.ts
// (generateTgspdclCaptcha, fetchTgspdclLiveData). Flow:
//   1. GET captcha (needs the API key)            -> captchaId + image
//   2. user types the captcha text
//   3. POST lookup-token {captchaId, answer}      -> token (wrong answer -> new captcha)
//   4. GET bill/download/{usc} and bill/history   -> current bill + monthly history
// The API key is read from the Worker secret TGSPDCL_API_KEY, never written into code.

const BASE = 'https://tgsouthernpower.org';
const WEB_REFERER = 'https://tgsouthernpower.org/';
const BROWSER_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  'Accept-Language': 'en-US,en;q=0.9',
  Accept: 'application/json, text/plain, */*',
};
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function fail(message, status) {
  const err = new Error(message);
  err.status = status;
  return err;
}

const num = (v) => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : 0;
  const n = parseFloat(String(v ?? '').replace(/,/g, '').trim());
  return Number.isFinite(n) ? n : 0;
};
const round2 = (n) => Math.round(n * 100) / 100;
const str = (v) => (v !== null && v !== undefined && String(v).trim() ? String(v).trim() : '');

/** Reads "Nov-26", "Nov 2026", "02/11/2026", "2026-11" and similar into {month0, year}. */
export function parseMonthYear(raw) {
  const clean = String(raw ?? '').trim();
  if (!clean) return {};
  const monthIdx = MONTH_NAMES.findIndex((m) => new RegExp(`\\b${m}[a-z]*\\b`, 'i').test(clean));
  if (monthIdx >= 0) {
    const four = clean.match(/\b(20\d{2})\b/);
    const after = clean.match(new RegExp(`\\b${MONTH_NAMES[monthIdx]}[a-z]*[\\s\\-/']*'?(\\d{2})\\b`, 'i'));
    const apos = clean.match(/'(\d{2})\b/);
    const yr = four?.[1] || after?.[1] || apos?.[1];
    let year;
    if (yr) {
      const y = parseInt(yr, 10);
      year = y < 100 ? 2000 + y : y;
    }
    return { month0: monthIdx, year };
  }
  const dmy = clean.match(/\b(\d{1,2})[-/](\d{1,2})[-/](20\d{2})\b/);
  if (dmy) {
    const m = parseInt(dmy[2], 10);
    if (m >= 1 && m <= 12) return { month0: m - 1, year: parseInt(dmy[3], 10) };
  }
  const ymd = clean.match(/\b(20\d{2})[-/](\d{1,2})(?:[-/]\d{1,2})?\b/);
  if (ymd) {
    const m = parseInt(ymd[2], 10);
    if (m >= 1 && m <= 12) return { month0: m - 1, year: parseInt(ymd[1], 10) };
  }
  return {};
}

/** Asks TGSPDCL for a new captcha. Returns {captchaId, image} or null. */
export async function generateTgspdclCaptcha(apiKey, fetchImpl = fetch) {
  try {
    const resp = await fetchImpl(`${BASE}/api/captcha/generate`, {
      headers: { ...BROWSER_HEADERS, 'X-API-Key': apiKey, Referer: WEB_REFERER },
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    if (data?.captchaId && data?.image) return { captchaId: String(data.captchaId), image: String(data.image) };
    return null;
  } catch {
    return null;
  }
}

/** Trades the captcha answer for a lookup token. Returns the token, or null when wrong. */
async function exchangeCaptcha(apiKey, captchaId, answer, fetchImpl) {
  let resp;
  try {
    resp = await fetchImpl(`${BASE}/api/public/lookup-token`, {
      method: 'POST',
      headers: { ...BROWSER_HEADERS, 'Content-Type': 'application/json', 'X-API-Key': apiKey, Referer: WEB_REFERER },
      body: JSON.stringify({ captchaId, answer: answer.trim() }),
    });
  } catch {
    return null;
  }
  const json = await resp.json().catch(() => ({}));
  return resp.ok && json?.token ? String(json.token) : null;
}

async function getJson(url, headers, fetchImpl) {
  try {
    const resp = await fetchImpl(url, { headers });
    const data = await resp.json().catch(() => null);
    return { ok: resp.ok, status: resp.status, data };
  } catch {
    return { ok: false, status: 0, data: null };
  }
}

/** One month row from the history array. Mirrors the reference field names. */
function historyRow(item) {
  const rawMonth = str(item.BILLMONTH ?? item.billmonth ?? item.MONTH ?? item.month ?? item.BILL_MONTH);
  const my = parseMonthYear(rawMonth);
  const units = Math.max(0, Math.round(num(item.UNITS ?? item.units ?? item.BILLEDUNITS ?? item.BILLED_UNITS ?? item.KWH ?? item.kwh)));
  const bill = Math.max(0, round2(num(item.DEMAND ?? item.demand ?? item.CURDEMAND ?? item.BILLAMT ?? item.TOTAMT ?? item.NETAMT ?? item.AMOUNTPAYABLE ?? item.billAmount)));
  return { my, rawMonth, units, bill };
}

/** Full lookup. Throws Error with .status (409 = captcha needed, 404 = no bill, 502 = portal down). */
export async function fetchTgspdclBill(usc, { apiKey, captchaId, captchaAnswer, fetchImpl = fetch } = {}) {
  if (!apiKey) throw fail('TGSPDCL lookup is not configured on the server yet. No bill data was shown.', 500);

  if (!captchaId || !captchaAnswer) {
    const captcha = await generateTgspdclCaptcha(apiKey, fetchImpl);
    const err = fail('Enter the security code shown below to fetch the TGSPDCL bill.', 409);
    err.captcha = captcha;
    throw err;
  }

  const token = await exchangeCaptcha(apiKey, captchaId, captchaAnswer, fetchImpl);
  if (!token) {
    const err = fail('The security code was wrong. Enter the new code shown below.', 409);
    err.captcha = await generateTgspdclCaptcha(apiKey, fetchImpl);
    throw err;
  }

  const headers = { ...BROWSER_HEADERS, 'X-API-Key': apiKey, Referer: WEB_REFERER, 'X-Lookup-Token': token };
  const [dl, hist] = await Promise.all([
    getJson(`${BASE}/api/public/bill/download/${encodeURIComponent(usc)}`, headers, fetchImpl),
    getJson(`${BASE}/api/public/bill/history?uscno=${encodeURIComponent(usc)}`, headers, fetchImpl),
  ]);

  const rows = [];
  if (hist.ok && Array.isArray(hist.data)) {
    for (const item of hist.data) rows.push(historyRow(item));
  }

  const d = dl.ok && dl.data && typeof dl.data === 'object' ? (dl.data.data ?? dl.data) : null;
  const dlUnits = d ? Math.max(0, Math.round(num(d.BLDUNITS ?? d.UNITS ?? d.BILLEDUNITS ?? d.BILLED_UNITS))) : 0;
  const dlBill = d ? Math.max(0, round2(num(d.BILLAMT ?? d.NETAMT ?? d.CURDEMAND ?? d.TOTALAMOUNT))) : 0;
  const hasCurrent = Boolean(d && (d.CTUKSCNO || d.CTNAME || dlUnits > 0 || dlBill > 0));
  if (hasCurrent) {
    const billDate = str(d.BLDT ?? d.CTPRESENTDT);
    rows.push({ my: parseMonthYear(billDate), rawMonth: billDate, units: dlUnits, bill: dlBill });
  }

  if (!hasCurrent && rows.length === 0) {
    throw fail(`No bill found on TGSPDCL for USC "${usc}". Check the number on your bill.`, 404);
  }

  // One row per month. A later non-zero value fills in an earlier empty one.
  const byMonth = new Map();
  const undated = [];
  for (const r of rows) {
    if (typeof r.my.month0 !== 'number' || typeof r.my.year !== 'number') {
      undated.push(r);
      continue;
    }
    const key = `${r.my.year}-${r.my.month0}`;
    const prev = byMonth.get(key);
    byMonth.set(key, {
      my: r.my,
      units: r.units > 0 ? r.units : prev?.units ?? 0,
      bill: r.bill > 0 ? r.bill : prev?.bill ?? 0,
    });
  }
  const sorted = [...byMonth.values()].sort((a, b) => a.my.year - b.my.year || a.my.month0 - b.my.month0);
  const months = sorted.map((r) => ({
    month: `${MONTH_NAMES[r.my.month0]} ${r.my.year}`,
    units: r.units,
    bill: r.bill,
    onPortal: true,
    present: true,
  }));

  const totalDue = d ? Math.max(0, round2(num(d.TOTAL_DUE ?? d.TOTALAMOUNT ?? d.NETAMT ?? dlBill))) : 0;
  return {
    consumerName: d ? str(d.CTNAME ?? d.CUSTOMERNAME) : '',
    address: d ? str(d.ADDRESS ?? d.CUSTOMERADD) : '',
    billNo: d ? str(d.BLNO ?? d.BILLNO) : '',
    billDate: d ? str(d.BLDT ?? d.CTPRESENTDT) : '',
    dueDate: d ? str(d.DUEDT) : '',
    billAmount: dlBill,
    totalDue,
    billedUnits: dlUnits || null,
    category: d ? str(d.CAT_DECODE) : '',
    contractedLoad: d && num(d.CTLOAD) > 0 ? `${num(d.CTLOAD)}KW` : '',
    unitsSource: months.length ? 'history' : 'unavailable',
    months,
    historyError: hist.ok ? null : `History returned HTTP ${hist.status}.`,
    downloadError: dl.ok ? null : `Current bill returned HTTP ${dl.status}.`,
    undatedRows: undated.length,
  };
}
