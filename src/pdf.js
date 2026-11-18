// Minimal PDF writer: embeds one or more JPEG pages (A4) into a valid PDF.
// Keeps the app dependency-free so the APK build never needs extra npm packages.

const enc = (s) => new TextEncoder().encode(s);

export function jpegPagesToPdf(pages /* [{bytes:Uint8Array,w:number,h:number}] */) {
  const W = 595.28, H = 841.89; // A4 in points
  const chunks = [];
  const offsets = [];
  let len = 0;
  const push = (b) => { const u = typeof b === 'string' ? enc(b) : b; chunks.push(u); len += u.length; };
  const obj = (n, body) => { offsets[n] = len; push(`${n} 0 obj\n`); push(body); push('\nendobj\n'); };

  push('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  const n = pages.length;
  // object ids: 1 catalog, 2 pages, then per page: page, content, image
  const kids = pages.map((_, k) => `${3 + k * 3} 0 R`).join(' ');
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, `<< /Type /Pages /Kids [${kids}] /Count ${n} >>`);
  pages.forEach((p, k) => {
    const pg = 3 + k * 3, ct = pg + 1, im = pg + 2;
    obj(pg, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /XObject << /Im0 ${im} 0 R >> >> /Contents ${ct} 0 R >>`);
    const stream = `q ${W} 0 0 ${H} 0 0 cm /Im0 Do Q`;
    obj(ct, `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
    offsets[im] = len;
    push(`${im} 0 obj\n<< /Type /XObject /Subtype /Image /Width ${p.w} /Height ${p.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.bytes.length} >>\nstream\n`);
    push(p.bytes);
    push('\nendstream\nendobj\n');
  });
  const total = 3 + n * 3;
  const xref = len;
  push(`xref\n0 ${total}\n0000000000 65535 f \n`);
  for (let i = 1; i < total; i++) push(String(offsets[i]).padStart(10, '0') + ' 00000 n \n');
  push(`trailer\n<< /Size ${total} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`);

  const out = new Uint8Array(len);
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}

export function dataUrlToBytes(url) {
  const b64 = url.split(',')[1];
  const bin = atob(b64);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u;
}

export function bytesToBase64(bytes) {
  let s = '';
  const step = 0x8000;
  for (let i = 0; i < bytes.length; i += step) s += String.fromCharCode.apply(null, bytes.subarray(i, i + step));
  return btoa(s);
}
