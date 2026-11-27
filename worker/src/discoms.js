// Registry of every DISCOM the app knows. Rules come from the reference project's
// src/data/uscPortals.ts (formatHint, uscLabel) and server.ts validation.
// route: 'live'    = the Worker can fetch this DISCOM's bill today
// route: 'planned' = the USC rules are known but no verified portal route exists yet.
//                    The Worker says so instead of inventing data.

export const DISCOMS = {
  TGNPDCL: {
    name: 'Northern Power Distribution Company of Telangana',
    state: 'Telangana',
    lengths: [8],
    digitsOnly: true,
    hint: '8-digit TGNPDCL USCNO (e.g. 10223902)',
    route: 'live',
    captcha: false,
  },
  TGSPDCL: {
    name: 'Southern Power Distribution Company of Telangana',
    state: 'Telangana',
    lengths: [9, 10, 11, 12],
    digitsOnly: true,
    hint: '9 to 12 digit USC Number (e.g. 102603120)',
    route: 'live',
    captcha: true,
  },
  APSPDCL: {
    name: 'Southern Power Distribution Company of A.P.',
    state: 'Andhra Pradesh',
    lengths: [8, 13],
    hint: '8-digit or 13-character USC/UKSC number (e.g. 1321104005678)',
    route: 'planned',
    captcha: false,
  },
  APCPDCL: {
    name: 'Central Power Distribution Corporation of A.P.',
    state: 'Andhra Pradesh',
    lengths: [13],
    digitsOnly: true,
    hint: '13-digit USC number starting 21, 22 or 52',
    route: 'planned',
    captcha: false,
  },
  APEPDCL: {
    name: 'Eastern Power Distribution Company of A.P.',
    state: 'Andhra Pradesh',
    lengths: [8, 9, 10, 11, 12, 13, 14, 15, 16],
    hint: '8 to 16 character USC/UKSCNO number',
    route: 'planned',
    captcha: false,
  },
  TPCODL: {
    name: 'TP Central Odisha Distribution',
    state: 'Odisha',
    lengths: [11, 12],
    digitsOnly: true,
    hint: '11 or 12 digit CA number (e.g. 80014589231)',
    route: 'planned',
    captcha: false,
  },
  TPWODL: {
    name: 'TP Western Odisha Distribution',
    state: 'Odisha',
    lengths: [11, 12],
    digitsOnly: true,
    hint: '11 or 12 digit CA number (e.g. 20045678912)',
    route: 'planned',
    captcha: false,
  },
  TPNODL: {
    name: 'TP Northern Odisha Distribution',
    state: 'Odisha',
    lengths: [11, 12],
    digitsOnly: true,
    hint: '11 or 12 digit CA number (e.g. 30067891234)',
    route: 'planned',
    captcha: false,
  },
  TPSODL: {
    name: 'TP Southern Odisha Distribution',
    state: 'Odisha',
    lengths: [11, 12],
    digitsOnly: true,
    hint: '11 or 12 digit CA number (e.g. 40023456789)',
    route: 'planned',
    captcha: false,
  },
  CSPDCL: {
    name: 'Chhattisgarh State Power Distribution',
    state: 'Chhattisgarh',
    lengths: [7, 10],
    digitsOnly: true,
    hint: '10-digit BP number (7-digit legacy number; confirm on a bill before going live)',
    route: 'planned',
    captcha: false,
  },
  CED: {
    name: 'Chandigarh Electricity Department',
    state: 'Chandigarh (UT)',
    lengths: [5, 6, 7, 8, 9, 10],
    hint: 'Account number of 5 to 10 characters',
    route: 'planned',
    captcha: false,
  },
};

/** Returns an error message for a bad USC number, or null when it is valid for that DISCOM. */
export function validateUsc(code, usc) {
  const d = DISCOMS[code];
  if (!d) return `Unknown DISCOM "${code}".`;
  if (!usc) return 'Enter the USC number from your bill.';
  if (d.digitsOnly && !/^\d+$/.test(usc)) return `${code} USC numbers contain digits only.`;
  if (!d.lengths.includes(usc.length)) {
    const allowed = d.lengths.length === 1 ? `${d.lengths[0]}` : `${d.lengths[0]} to ${d.lengths[d.lengths.length - 1]}`;
    return `${code} USC numbers are ${allowed} characters. ${d.hint}.`;
  }
  return null;
}
