// USC lookup backend. Contract: see lib/core/usc_http.dart.
import { fetchTgnpdclBill } from './tgnpdcl.js';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (url.pathname === '/') return json({ service: 'usc-lookup', status: 'running' });
    if (url.pathname === '/api/usc/fetch' && request.method === 'POST') {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: 'Send the USC number and DISCOM as JSON.' }, 400);
      }
      const usc = String(body.usc ?? '').trim();
      const discom = String(body.discom ?? '').trim();
      if (discom !== 'TGNPDCL') {
        return json({ error: `${discom || 'This DISCOM'} lookup is not connected yet. No bill data was shown.` }, 501);
      }
      if (!/^\d{8}$/.test(usc)) {
        return json({ error: 'TGNPDCL USC numbers are 8 digits.' }, 400);
      }
      try {
        const bill = await fetchTgnpdclBill(usc, fetch, body.debug === true);
        return json({
          consumerName: bill.consumerName,
          address: bill.address,
          fetchedAt: new Date().toISOString(),
          months: bill.months,
          bill: bill,
        });
      } catch (err) {
        const out = { error: err.message || 'Lookup failed. No bill data was shown.' };
        if (err.debug) out.debug = err.debug;
        return json(out, err.status || 500);
      }
    }
    return json({ error: 'Not found' }, 404);
  },
};
