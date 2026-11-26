// USC lookup backend. Contract: see lib/core/usc_http.dart.
// Step 2 placeholder: the live DISCOM lookup is added after the portal captures arrive.
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
      return json({ error: 'The live DISCOM lookup is not connected yet. No bill data was shown.' }, 501);
    }
    return json({ error: 'Not found' }, 404);
  },
};
