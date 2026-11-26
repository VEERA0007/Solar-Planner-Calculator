// TGNPDCL (Northern Telangana DISCOM) latest-bill lookup.
// Flow: GET the lookup page for a session cookie and CSRF token, then POST the USC number.
// No password and no captcha on this portal. Only the latest bill is shown, so the
// caller keeps history over time.

const BROWSER_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  'Accept-Language': 'en-US,en;q=0.9',
};

const LOOKUP_PAGE = 'https://tgnpdcl.com/Menu/KnowYourBillLT';
const BILL_PAGE = 'https://tgnpdcl.com/Consumer/DuplicateBillValidate';

/** Turns the portal HTML into clean text lines, one per table row or block. */
export function htmlToLines(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(tr|p|div|li|h\d|table)>/gi, '\n')
    .replace(/<\/t[dh]>/gi, '\t')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .split('\n')
    .map((s) => s.replace(/\s+/g, ' ').trim())
    .filter(Boolean);
}

/** Rest of the first line that starts with [label] (case-insensitive), or '' if none. */
function after(lines, label) {
  const l = label.toLowerCase();
  for (const line of lines) {
    if (line.toLowerCase().startsWith(l)) return line.slice(label.length).replace(/^[\s:.]+/, '').trim();
  }
  return '';
}

function firstNumber(text) {
  const m = text.match(/-?\d+(?:\.\d+)?/);
  return m ? parseFloat(m[0]) : 0;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "04/11/2026" (dd/mm/yyyy) -> "Nov 2026". */
function billMonthLabel(dateText) {
  const m = dateText.match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (!m) return '';
  return `${MONTHS[parseInt(m[2], 10) - 1] ?? ''} ${m[3]}`;
}

/** Parses the bill page. Throws Error with a user-readable message when no bill is present. */
export function parseTgnpdclBill(html) {
  const lines = htmlToLines(html);
  const billNo = (after(lines, 'Bill No:').split(/\s+/)[0]) ?? '';
  if (!billNo) {
    const msg = lines.find((l) => /invalid|not found|no bill|no record|wrong/i.test(l));
    const err = new Error(msg ? `TGNPDCL: ${msg}` : 'TGNPDCL returned no bill for this USC number. No bill data was shown.');
    err.status = 404;
    throw err;
  }

  const billDate = after(lines, 'Dt:').split(/\s+/)[0] ?? '';
  const nameIdx = lines.findIndex((l) => l.toLowerCase().startsWith('name:'));
  const addrIdx = lines.findIndex((l) => l.toLowerCase().startsWith('addr:'));
  const addrParts = [];
  if (addrIdx >= 0) {
    const first = after(lines, 'Addr:');
    if (first) addrParts.push(first);
    if (lines[addrIdx + 1]) addrParts.push(lines[addrIdx + 1]);
  }
  const billAmount = firstNumber(after(lines, 'Bill Amount'));
  const totalDue = firstNumber(after(lines, 'Total Due')) || billAmount;
  const billedUnits = firstNumber(after(lines, 'Billed Units'));
  const monthUnits = billedUnits || firstNumber(after(lines, 'KWH Units'));
  const month = billMonthLabel(billDate);

  return {
    consumerName: nameIdx >= 0 ? after(lines, 'Name:') : '',
    address: addrParts.join(', '),
    billNo,
    billDate,
    scNo: after(lines, 'SC No.'),
    uscNo: after(lines, 'USC No.'),
    category: after(lines, 'Cat:').split(/\s+Ph:/)[0].trim(),
    contractedLoad: after(lines, 'Contracted Load:'),
    kwhUnits: firstNumber(after(lines, 'KWH Units')),
    exportUnits: firstNumber(after(lines, 'EXP KWH Units')),
    billedUnits,
    portalAverageUnits: firstNumber(after(lines, 'Average Month Units')),
    billAmount,
    totalDue,
    subsidyAmount: firstNumber(after(lines, 'Subsidy Amount')),
    dueDate: after(lines, 'Due Date').split(/\s+/)[0] ?? '',
    lastPaidDate: after(lines, 'Last Paid Date').split(/\s+/)[0] ?? '',
    lastPaidAmount: firstNumber(after(lines, 'Last Paid Amt')),
    // One month per lookup: the caller stores it and builds the 12-month history over time.
    months: month
      ? [{ month, units: monthUnits, bill: totalDue, onPortal: true, present: true }]
      : [],
  };
}

/** Fetches the latest bill for [usc] (8 digits). Returns the parsed bill. */
export async function fetchTgnpdclBill(usc, fetchImpl = fetch, debug = false) {
  let page;
  try {
    page = await fetchImpl(LOOKUP_PAGE, { headers: BROWSER_HEADERS });
  } catch {
    const err = new Error('Could not reach TGNPDCL. Try again in a few minutes.');
    err.status = 502;
    throw err;
  }
  const setCookies = typeof page.headers.getSetCookie === 'function' ? page.headers.getSetCookie() : [];
  const cookies = setCookies.map((c) => c.split(';')[0]).filter(Boolean);
  const xsrf = cookies.find((c) => c.startsWith('XSRF-TOKEN='))?.slice('XSRF-TOKEN='.length) ?? '';

  const form = new URLSearchParams({ uscno: usc, getBill: 'Get Bill', _csrf: xsrf });
  let resp;
  try {
    resp = await fetchImpl(BILL_PAGE, {
      method: 'POST',
      headers: {
        ...BROWSER_HEADERS,
        'Content-Type': 'application/x-www-form-urlencoded',
        Cookie: cookies.join('; '),
        Referer: LOOKUP_PAGE,
        Origin: 'https://tgnpdcl.com',
      },
      body: form.toString(),
    });
  } catch {
    const err = new Error('Could not reach TGNPDCL. Try again in a few minutes.');
    err.status = 502;
    throw err;
  }
  const html = await resp.text();
  try {
    return parseTgnpdclBill(html);
  } catch (err) {
    if (debug) {
      // Diagnostics only: status, cookie NAMES (never values), and the start of the reply text.
      err.debug = {
        pageStatus: page.status,
        postStatus: resp.status,
        cookieNames: cookies.map((c) => c.split('=')[0]),
        replyStart: htmlToLines(html).slice(0, 25),
      };
    }
    throw err;
  }
}
