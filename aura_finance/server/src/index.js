// Aura API — Cloudflare Worker kecil yang memegang secret Pusher.
//
// Endpoint (semuanya butuh header `Authorization: Bearer <JWT Neon Auth>`):
//   POST /pusher/auth   {socket_id, channel_name}    -> tanda tangan channel privat Pusher
//   GET  /beams/token?user_id=...                    -> token Pusher Beams untuk push ke user ini
//   POST /notify        {household_id, kind, title, body, socket_id?, tables?, changes?}
//        -> event realtime ke anggota lain + push notification ke HP mereka.
//           `changes` (baris yang baru disimpan, sudah disaring pengirim) diteruskan
//           supaya HP penerima bisa langsung menampilkannya sebelum menarik dari Neon.
//
// Keanggotaan rumah tangga dicek lewat Neon Data API memakai JWT pengguna,
// jadi aturan RLS di Postgres tetap menjadi satu-satunya sumber kebenaran.

import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });

let jwks;
async function verifyUser(request, env) {
  const auth = request.headers.get('authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) throw new HttpError(401, 'missing token');
  jwks ??= createRemoteJWKSet(new URL(`${env.NEON_AUTH_URL.replace(/\/$/, '')}/.well-known/jwks.json`));
  try {
    const { payload } = await jwtVerify(token, jwks);
    if (!payload.sub) throw new Error('no sub');
    return { userId: String(payload.sub), token };
  } catch {
    throw new HttpError(401, 'invalid token');
  }
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** Anggota rumah tangga yang terlihat oleh pengguna ini (RLS memastikan hanya sesama anggota). */
async function householdMembers(env, token, householdId) {
  const url = `${env.NEON_DATA_API_URL.replace(/\/$/, '')}/household_members?household_id=eq.${encodeURIComponent(householdId)}&select=user_id`;
  const res = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) throw new HttpError(502, `data api ${res.status}`);
  return (await res.json()).map((r) => String(r.user_id));
}

// Cache keanggotaan per isolate (60 detik): menghindari satu perjalanan ke Neon
// (us-east-2) di setiap sinyal. Keluar/dikeluarkan dari rumah tangga berlaku paling lambat 60 detik.
const memberCache = new Map();
const MEMBER_TTL_MS = 60_000;

async function requireMember(env, user, householdId) {
  if (!/^[0-9a-f-]{36}$/i.test(householdId || '')) throw new HttpError(400, 'bad household_id');
  const key = `${user.userId}|${householdId}`;
  const hit = memberCache.get(key);
  if (hit && hit.exp > Date.now()) return hit.members;
  const members = await householdMembers(env, user.token, householdId);
  if (!members.includes(user.userId)) throw new HttpError(403, 'not a member');
  memberCache.set(key, { members, exp: Date.now() + MEMBER_TTL_MS });
  return members;
}

const SYNC_TABLES = ['wallets', 'categories', 'transactions', 'budgets', 'goals', 'goal_contributions', 'recurring_rules', 'bills'];
const MAX_CHANGES_BYTES = 8000; // batas event Pusher 10 KB, sisakan ruang untuk field lain

/** Hanya tabel yang dikenal dan baris milik rumah tangga ini yang diteruskan. */
function sanitizeChanges(changes, householdId) {
  if (!changes || typeof changes !== 'object') return undefined;
  const out = {};
  for (const [table, rows] of Object.entries(changes)) {
    if (!SYNC_TABLES.includes(table) || !Array.isArray(rows)) continue;
    const ok = rows.filter((r) => r && typeof r === 'object' && r.household_id === householdId && typeof r.id === 'string');
    if (ok.length) out[table] = ok;
  }
  if (!Object.keys(out).length) return undefined;
  return JSON.stringify(out).length <= MAX_CHANGES_BYTES ? out : undefined;
}

// --- Kriptografi kecil untuk Pusher -------------------------------------------------

const enc = new TextEncoder();
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

async function hmacSha256Hex(secret, message) {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', key, enc.encode(message)));
}

async function md5Hex(text) {
  return hex(await crypto.subtle.digest('MD5', enc.encode(text)));
}

/** Memicu event Pusher Channels lewat REST API (https://pusher.com/docs/channels/library_auth_reference/rest-api/). */
async function triggerChannel(env, channel, event, data, socketId) {
  const body = JSON.stringify({ name: event, channel, data: JSON.stringify(data), ...(socketId ? { socket_id: socketId } : {}) });
  const path = `/apps/${env.PUSHER_APP_ID}/events`;
  const params = new URLSearchParams({
    auth_key: env.PUSHER_KEY,
    auth_timestamp: String(Math.floor(Date.now() / 1000)),
    auth_version: '1.0',
    body_md5: await md5Hex(body),
  });
  params.sort();
  const signature = await hmacSha256Hex(env.PUSHER_SECRET, `POST\n${path}\n${params.toString()}`);
  params.set('auth_signature', signature);
  const res = await fetch(`https://api-${env.PUSHER_CLUSTER}.pusher.com${path}?${params}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body,
  });
  if (!res.ok) console.log('pusher trigger failed', res.status, await res.text());
}

/** Push notification ke user tertentu lewat Pusher Beams. */
async function publishToUsers(env, users, title, body, data) {
  if (!users.length || !env.BEAMS_INSTANCE_ID) return;
  const id = env.BEAMS_INSTANCE_ID;
  const res = await fetch(`https://${id}.pushnotifications.pusher.com/publish_api/v1/instances/${id}/publishes/users`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${env.BEAMS_SECRET_KEY}` },
    body: JSON.stringify({
      users,
      fcm: { notification: { title, body }, data },
    }),
  });
  if (!res.ok) console.log('beams publish failed', res.status, await res.text());
}

// --- Rute ------------------------------------------------------------------------------

async function handle(request, env, ctx) {
  const url = new URL(request.url);

  if (url.pathname === '/health') return json({ ok: true });

  if (url.pathname === '/pusher/auth' && request.method === 'POST') {
    const user = await verifyUser(request, env);
    const form = request.headers.get('content-type')?.includes('json')
      ? await request.json()
      : Object.fromEntries(new URLSearchParams(await request.text()));
    const { socket_id: socketId, channel_name: channel } = form;
    const m = /^private-household-([0-9a-f-]{36})$/i.exec(channel || '');
    if (!socketId || !m) throw new HttpError(400, 'bad channel');
    await requireMember(env, user, m[1]);
    const signature = await hmacSha256Hex(env.PUSHER_SECRET, `${socketId}:${channel}`);
    return json({ auth: `${env.PUSHER_KEY}:${signature}` });
  }

  if (url.pathname === '/beams/token' && request.method === 'GET') {
    const user = await verifyUser(request, env);
    if (url.searchParams.get('user_id') !== user.userId) throw new HttpError(403, 'user mismatch');
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(user.userId)
      .setIssuer(`https://${env.BEAMS_INSTANCE_ID}.pushnotifications.pusher.com`)
      .setExpirationTime('24h')
      .sign(enc.encode(env.BEAMS_SECRET_KEY));
    return json({ token });
  }

  if (url.pathname === '/notify' && request.method === 'POST') {
    const user = await verifyUser(request, env);
    const { household_id: householdId, kind, title, body, socket_id: socketId, tables, changes } = await request.json();
    if (!['tx', 'budget', 'goal', 'bill', 'sync', 'test'].includes(kind)) throw new HttpError(400, 'bad kind');
    const members = await requireMember(env, user, householdId);
    const clip = (s, n) => String(s || '').slice(0, n);

    // Uji push: hanya ke pengirim sendiri, ditunda beberapa detik supaya
    // pengguna sempat keluar dari aplikasi (push FCM tidak tampil saat aplikasi di layar).
    if (kind === 'test') {
      ctx.waitUntil(
        new Promise((r) => setTimeout(r, 6000)).then(() =>
          publishToUsers(env, [user.userId], clip(title, 80), clip(body, 160), { kind, household_id: householdId })),
      );
      return json({ ok: true });
    }

    // Realtime: kirim isi perubahan (bila muat) + daftar tabel yang perlu ditarik.
    const event = { by: user.userId, kind, title: clip(title, 80), body: clip(body, 160) };
    const t = Array.isArray(tables) ? tables.filter((x) => SYNC_TABLES.includes(x)) : [];
    if (t.length) event.tables = t;
    const c = sanitizeChanges(changes, householdId);
    if (c) event.changes = c;
    await triggerChannel(env, `private-household-${householdId}`, 'changed', event, socketId);

    // Push: ke anggota lain saja (bukan pengirim), kecuali "sync" yang hanya realtime.
    // Dikirim di latar supaya balasan ke pengirim tidak menunggu Beams.
    if (kind !== 'sync' && title) {
      const others = members.filter((id) => id !== user.userId);
      ctx.waitUntil(publishToUsers(env, others, clip(title, 80), clip(body, 160), { kind, household_id: householdId }));
    }
    return json({ ok: true });
  }

  return json({ error: 'not found' }, 404);
}

export default {
  async fetch(request, env, ctx) {
    try {
      return await handle(request, env, ctx);
    } catch (e) {
      const status = e instanceof HttpError ? e.status : 500;
      if (status === 500) console.log('error', e?.stack || e);
      return json({ error: status === 500 ? 'internal error' : e.message }, status);
    }
  },
};
