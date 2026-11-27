// USC lookup backend. Contract: see lib/core/usc_http.dart.
import { fetchTgnpdclBill } from './tgnpdcl.js';
import { fetchTgspdclBill, generateTgspdclCaptcha } from './tgspdcl.js';
import { DISCOMS, validateUsc } from './discoms.js';
import { handleInverterPortalSync, handleInverterPortalPing, setInverterEnv } from './inverter/cloudPortalSync.ts';

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
  async fetch(request, env = {}) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (url.pathname === '/') return json({ service: 'usc-lookup', status: 'running' });

    // Inverter cloud sync. Credentials arrive per request and are used only to log in
    // to the manufacturer portal. They are not stored or logged by the Worker.
    if (url.pathname === '/api/inverter/portal-sync' || url.pathname === '/api/inverter/portal-ping') {
      if (request.method !== 'POST') return json({ error: 'Use POST.' }, 405);
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ ok: false, error: 'Send the inverter login details as JSON.' }, 400);
      }
      setInverterEnv(env);
      const out = url.pathname.endsWith('portal-ping')
        ? await handleInverterPortalPing(body)
        : await handleInverterPortalSync(body);
      return json(out, 200);
    }

    // Captcha for DISCOMs that need one (TGSPDCL). Returns {captchaId, image}.
    if (url.pathname === '/api/usc/captcha' && request.method === 'GET') {
      const discom = (url.searchParams.get('discom') || '').trim();
      if (discom !== 'TGSPDCL') return json({ error: 'This DISCOM does not use a captcha.' }, 400);
      const captcha = await generateTgspdclCaptcha(env.TGSPDCL_API_KEY || '');
      if (!captcha) return json({ error: 'Could not load the security code from TGSPDCL. Try again.' }, 502);
      return json(captcha);
    }

    if (url.pathname === '/api/usc/fetch' && request.method === 'POST') {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: 'Send the USC number and DISCOM as JSON.' }, 400);
      }
      const usc = String(body.usc ?? '').trim();
      const discom = String(body.discom ?? '').trim();
      const spec = DISCOMS[discom];
      if (!spec) return json({ error: `Unknown DISCOM "${discom}".` }, 400);

      const bad = validateUsc(discom, usc);
      if (bad) return json({ error: bad }, 400);

      if (spec.route !== 'live') {
        return json(
          { error: `${discom} live lookup is not connected yet. No bill data was shown. Your bill or the ${discom} portal still works.` },
          501,
        );
      }

      try {
        let bill;
        if (discom === 'TGNPDCL') {
          bill = await fetchTgnpdclBill(usc, fetch, body.debug === true);
        } else if (discom === 'TGSPDCL') {
          bill = await fetchTgspdclBill(usc, {
            apiKey: env.TGSPDCL_API_KEY,
            captchaId: body.captchaId ? String(body.captchaId) : undefined,
            captchaAnswer: String(body.captcha ?? body.captchaAnswer ?? '').trim() || undefined,
          });
        } else {
          return json({ error: `${discom} live lookup is not connected yet.` }, 501);
        }
        return json({
          consumerName: bill.consumerName,
          address: bill.address,
          fetchedAt: new Date().toISOString(),
          months: bill.months,
          bill,
        });
      } catch (err) {
        const out = { error: err.message || 'Lookup failed. No bill data was shown.' };
        if (err.status === 409 && err.captcha) {
          out.captchaRequired = true;
          out.captchaId = err.captcha.captchaId;
          out.image = err.captcha.image;
        }
        if (err.debug) out.debug = err.debug;
        return json(out, err.status || 500);
      }
    }
    return json({ error: 'Not found' }, 404);
  },
};
