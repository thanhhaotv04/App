import express from 'express';
import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import https from 'node:https';
import { randomBytes, randomUUID, scrypt, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { openDatabase, normalizeName, nameKey } from './database.js';

const directory = path.dirname(fileURLToPath(import.meta.url));
const hash = (value) => createHash('sha256').update(value).digest('hex');
const derive = promisify(scrypt);
const passwordPrefix = 'scrypt-v2:';
// OWASP's 32 MiB profile avoids multiplying 128 MiB by concurrent logins.
const passwordOptions = { N: 32768, r: 8, p: 3, maxmem: 64 * 1024 * 1024 };
async function hashPassword(password, salt = randomBytes(16).toString('hex')) {
  return `${passwordPrefix}${salt}:${(await derive(password, salt, 32, passwordOptions)).toString('hex')}`;
}
async function matches(password, stored) {
  const modern = stored.startsWith(passwordPrefix);
  const value = modern ? stored.slice(passwordPrefix.length) : stored;
  if (!/^[a-f0-9]{32}:[a-f0-9]{64}$/.test(value)) return false;
  const [salt, digest] = value.split(':');
  const actual = await derive(typeof password === 'string' ? password : '', salt, 32, modern ? passwordOptions : {});
  const expected = Buffer.from(digest, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const validPassword = (password) => typeof password === 'string' && password.length >= 12 && password.length <= 128;
const invalidLogin = () => new ApiError(401, 'Username or password is incorrect.');
const emptyData = () => ({ transactions: [], recurring: [], deletedTransactions: [], deletedRecurring: [] });
const maxRecords = 20000;
function validateData(data) {
  const fail = () => { throw new ApiError(400, 'Invalid sync data. Nothing was changed.'); };
  if (!data || !['transactions', 'recurring', 'deletedTransactions', 'deletedRecurring'].every(k => Array.isArray(data[k]) && data[k].length <= maxRecords)) fail();
  const text = (v, max) => typeof v === 'string' && v.length > 0 && v.length <= max;
  const date = (v) => typeof v === 'string' && /^\d{4}-\d\d-\d\dT/.test(v) && Number.isFinite(Date.parse(v)) && Date.parse(v) >= Date.UTC(2000, 0, 1) && Date.parse(v) <= Date.now() + 366 * 86400000;
  for (const key of ['transactions', 'recurring']) {
    const ids = new Set();
    for (const item of data[key]) {
      if (!item || !text(item.id, 160) || ids.has(item.id) || !text(item.title, 500) || !text(item.category, 80) || !Number.isSafeInteger(item.amount) || item.amount <= 0 || item.amount > 999999999999) fail();
      if (Buffer.byteLength(JSON.stringify(item)) > 512 * 1024 - 256) fail();
      ids.add(item.id);
      if (key === 'transactions') {
        if (!date(item.date) || !['income', 'expense'].includes(item.type) || (item.note !== undefined && (typeof item.note !== 'string' || item.note.length > 2000)) || (item.icon !== undefined && (!Number.isInteger(item.icon) || item.icon < 0 || item.icon > 0x10ffff))) fail();
      } else if (!date(item.lastAppliedAt) || !['daily', 'monthly'].includes(item.frequency) || !Number.isInteger(item.dayOfMonth) || item.dayOfMonth < 1 || item.dayOfMonth > 31 || typeof item.active !== 'boolean') fail();
    }
  }
  for (const key of ['deletedTransactions', 'deletedRecurring']) if (data[key].some(id => !text(id, 160))) fail();
}
function mergeData(previous, incoming) {
  const merged = emptyData();
  for (const [key, deleted, stamp] of [['transactions', 'deletedTransactions', 'date'], ['recurring', 'deletedRecurring', 'lastAppliedAt']]) {
    const tombstones = new Set([...(previous[deleted] || []), ...incoming[deleted]]);
    const items = new Map();
    for (const item of [...previous[key], ...incoming[key]]) {
      const old = items.get(item.id);
      if (!tombstones.has(item.id) && (!old || Date.parse(item[stamp]) > Date.parse(old[stamp]))) items.set(item.id, item);
    }
    if (items.size > maxRecords || tombstones.size > maxRecords) throw new ApiError(413, 'Account storage limit reached. Export or archive older data before syncing.');
    merged[key] = [...items.values()];
    merged[deleted] = [...tombstones];
  }
  merged.updatedAt = Date.now();
  return merged;
}

function dataPage(value, query) {
  const revision = hash(JSON.stringify(value));
  if (query.revision !== undefined && query.revision !== revision) throw new ApiError(409, 'Data changed during sync. Retry the download.');
  if (typeof query.cursor !== 'string' || !/^\d{1,5}$/.test(query.cursor)) throw new ApiError(400, 'Invalid sync cursor.');
  const start = Number(query.cursor);
  const page = { ...emptyData(), protocol: 3, revision, nextCursor: null };
  let index = 0, size = 256;
  for (const key of ['transactions', 'recurring', 'deletedTransactions', 'deletedRecurring']) {
    for (const item of value[key] || []) {
      if (index++ < start) continue;
      const bytes = Buffer.byteLength(JSON.stringify(item)) + 1;
      if (bytes > 512 * 1024 - 256) throw new ApiError(413, 'A saved record is too large. Contact the server owner to recover it.');
      if (size + bytes > 512 * 1024) { page.nextCursor = index - 1; return page; }
      page[key].push(item); size += bytes;
    }
  }
  if (start > index) throw new ApiError(400, 'Invalid sync cursor.');
  return page;
}

async function publishedRelease(releasesDir) {
  let manifest;
  try { manifest = JSON.parse(await fs.readFile(path.join(releasesDir, 'latest.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') throw new ApiError(404, 'No update is available.'); throw error; }
  if (typeof manifest.apkFile !== 'string' || path.basename(manifest.apkFile) !== manifest.apkFile || !manifest.apkFile.endsWith('.apk') || !/^[a-f0-9]{64}$/.test(manifest.sha256 || '') || !Number.isSafeInteger(manifest.versionCode) || !Number.isSafeInteger(manifest.sizeBytes) || manifest.sizeBytes <= 0 || manifest.sizeBytes > 200 * 1024 * 1024) throw new ApiError(404, 'No verified update is available.');
  const file = path.join(releasesDir, manifest.apkFile);
  let stat;
  try { stat = await fs.stat(file); } catch (error) { if (error.code === 'ENOENT') throw new ApiError(404, 'No update is available.'); throw error; }
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(file)) digest.update(chunk);
  if (stat.size !== manifest.sizeBytes || digest.digest('hex') !== manifest.sha256) throw new ApiError(503, 'Update is being prepared. Try again later.');
  return manifest;
}

// Only public first-install files are exposed over HTTP. Auth and financial
// routes belong exclusively to the separate HTTPS application.
export function createInstaller({ releasesDir = path.join(directory, 'releases') } = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use((req, res, next) => {
    res.set({ 'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; base-uri 'none'; frame-ancestors 'none'" });
    if (!['GET', 'HEAD'].includes(req.method)) return res.sendStatus(405);
    next();
  });
  async function release() {
    const manifest = await publishedRelease(releasesDir);
    if (manifest.applicationId !== 'com.thanhhao.money_manager.lan' || !/^\d{6}\.\d+$/.test(manifest.versionName) || !/^[a-f0-9]{64}$/.test(manifest.signerSha256 || '')) throw new ApiError(503, 'Release is not ready.');
    return manifest;
  }
  app.get('/', async (_req, res) => {
    const manifest = await release();
    res.type('html').send(`<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Money Manager LAN</title><body><h1>Money Manager LAN</h1><p>Phiên bản ${manifest.versionName}</p><p><a href="/download">Tải APK và cài Money Manager LAN</a></p><p>Bản LAN cài song song với ứng dụng cũ. Không cần gỡ ứng dụng cũ.</p><p>Sau khi cài, mở Money Manager LAN và đăng nhập để lấy dữ liệu đã đồng bộ. Dữ liệu chỉ lưu trên ứng dụng cũ vẫn nằm trong ứng dụng đó.</p><p>Những lần sau: Account → Check for update.</p><p>SHA-256 APK: <code>${manifest.sha256}</code></p></body></html>`);
  });
  app.get('/download', async (_req, res) => {
    const manifest = await release();
    res.download(path.join(releasesDir, manifest.apkFile), `Money-Manager-LAN-${manifest.versionName}.apk`);
  });
  app.use((_req, res) => res.sendStatus(404));
  app.use((_error, _req, res, _next) => res.status(503).send('Bản cập nhật đang được chuẩn bị. Vui lòng thử lại sau.'));
  return app;
}

export async function createApp({ dataDir = process.env.DATA_DIR || path.join(directory, 'server-data'), releasesDir = process.env.RELEASES_DIR || path.join(directory, 'releases'), origins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean) } = {}) {
  const { db, transaction } = openDatabase(dataDir);
  const app = express();
  app.disable('x-powered-by');
  app.locals.db = db;
  const dummyHash = await hashPassword(randomBytes(32).toString('hex'));
  const accountByName = (name) => db.prepare('SELECT * FROM accounts WHERE name_key=?').get(nameKey(name));
  function issueSession(account) {
    const token = randomBytes(32).toString('hex');
    const expires = Date.now() + 90 * 86400000;
    db.prepare('DELETE FROM sessions WHERE expires<?').run(Date.now());
    db.prepare('INSERT INTO sessions VALUES (?, ?, ?)').run(hash(token), account.id, expires);
    return { ok: true, id: account.id, name: account.name, token, expires };
  }
  function authenticate(req) {
    const token = /^Bearer ([a-f0-9]{64})$/.exec(req.get('Authorization') || '')?.[1];
    const account = token && db.prepare('SELECT a.* FROM accounts a JOIN sessions s ON s.account_id=a.id WHERE s.hash=? AND s.expires>?').get(hash(token), Date.now());
    if (!account) throw new ApiError(401, 'Your session has expired. Sign in again; your local data is safe.');
    return account;
  }
  // SQLite counters persist across restarts and coordinate local worker processes.
  function limit(key, max, duration) {
    const now = Date.now();
    transaction(() => {
      db.prepare('DELETE FROM limits WHERE expires<=?').run(now);
      const row = db.prepare('SELECT * FROM limits WHERE key=?').get(key);
      if (row && row.count >= max) throw new ApiError(429, 'Too many attempts. Please wait a few minutes and try again.');
      db.prepare('INSERT INTO limits VALUES (?, 1, ?) ON CONFLICT(key) DO UPDATE SET count=count+1').run(key, now + duration);
    });
  }
  app.use((req, res, next) => {
    res.set({ 'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'no-referrer', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'" });
    if (req.secure) res.set('Strict-Transport-Security', 'max-age=31536000');
    const origin = req.get('Origin');
    if (origin && !origins.includes(origin)) return res.status(403).json({ message: 'This web origin is not allowed.' });
    if (origin) { res.set('Access-Control-Allow-Origin', origin); res.vary('Origin'); }
    res.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type,Authorization');
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    // Revocation is idempotent and must remain available after other limits fire.
    try { if (req.path !== '/api/auth/logout') limit(`api:${req.ip}`, 300, 60000); next(); } catch (e) { next(e); }
  });
  app.post('/api/auth/logout', (req, res) => {
    const token = /^Bearer ([a-f0-9]{64})$/.exec(req.get('Authorization') || '')?.[1];
    if (token) db.prepare('DELETE FROM sessions WHERE hash=?').run(hash(token));
    res.json({ ok: true });
  });
  app.use(express.json({ limit: '5mb' }));
  app.use('/api/auth', (req, _res, next) => {
    try {
      limit(`auth:${req.ip}`, 30, 60000);
      next();
    } catch (e) { next(e); }
  });
  app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'money-manager-backend', protocol: 3 }));
  app.post('/api/auth/register', async (req, res) => {
    const name = normalizeName(req.body?.name);
    const password = req.body?.password;
    if (!name || name.length > 80 || /[\p{Cc}\p{Cf}]/u.test(name) || !validPassword(password)) throw new ApiError(400, 'Use a username up to 80 characters and a password of 12–128 characters.');
    if (accountByName(name)) throw new ApiError(409, 'That username is unavailable. Choose another or sign in.');
    const passwordHash = await hashPassword(password);
    const result = transaction(() => {
      if (accountByName(name)) throw new ApiError(409, 'That username is unavailable. Choose another or sign in.');
      const account = { id: randomUUID(), name };
      db.prepare('INSERT INTO accounts VALUES (?, ?, ?, ?)').run(account.id, name, nameKey(name), passwordHash);
      return issueSession(account);
    });
    res.status(201).json(result);
  });
  app.post('/api/auth/login', async (req, res) => {
    const password = req.body?.password;
    if (typeof password !== 'string' || password.length > 128 || typeof req.body?.name !== 'string' || req.body.name.length > 80) throw invalidLogin();
    // Never let an untrusted username alone lock out its owner on other IPs.
    const attemptKey = `login:${req.ip}:${hash(nameKey(req.body.name))}`;
    limit(attemptKey, 15, 15 * 60000);
    const account = accountByName(req.body.name);
    const verified = await matches(password, account?.password_hash || dummyHash);
    if (!account || !verified) throw invalidLogin();
    const upgraded = account.password_hash.startsWith(passwordPrefix) ? null : await hashPassword(password);
    const result = transaction(() => {
      if (accountByName(account.name)?.password_hash !== account.password_hash) throw invalidLogin();
      if (upgraded) db.prepare('UPDATE accounts SET password_hash=? WHERE id=?').run(upgraded, account.id);
      db.prepare('DELETE FROM limits WHERE key=?').run(attemptKey);
      return issueSession(account);
    });
    res.json(result);
  });
  app.post('/api/auth/update', async (req, res) => {
    const account = authenticate(req);
    if (!validPassword(req.body?.newPassword)) throw new ApiError(400, 'New password must have 12–128 characters.');
    if (typeof req.body?.currentPassword !== 'string' || req.body.currentPassword.length > 128 || !await matches(req.body.currentPassword, account.password_hash)) throw invalidLogin();
    const passwordHash = await hashPassword(req.body.newPassword);
    const result = transaction(() => {
      const current = authenticate(req);
      if (current.password_hash !== account.password_hash) throw invalidLogin();
      db.prepare('UPDATE accounts SET password_hash=? WHERE id=?').run(passwordHash, account.id);
      db.prepare('DELETE FROM sessions WHERE account_id=?').run(account.id);
      db.prepare('DELETE FROM recovery WHERE account_id=?').run(account.id);
      return issueSession(account);
    });
    res.json(result);
  });
  app.post('/api/auth/reset-password', async (req, res) => {
    const code = req.body?.recoveryCode;
    if (typeof code !== 'string' || !/^[a-f0-9]{64}$/.test(code) || !validPassword(req.body?.newPassword)) throw new ApiError(400, 'Enter a valid recovery code and a new password of 12–128 characters.');
    const passwordHash = await hashPassword(req.body.newPassword);
    transaction(() => {
      const account = accountByName(req.body.name);
      const recovery = db.prepare('SELECT * FROM recovery WHERE hash=? AND expires>?').get(hash(code), Date.now());
      if (!account || !recovery || account.id !== recovery.account_id) throw new ApiError(400, 'Recovery code is invalid or expired.');
      db.prepare('UPDATE accounts SET password_hash=? WHERE id=?').run(passwordHash, account.id);
      db.prepare('DELETE FROM sessions WHERE account_id=?').run(account.id);
      db.prepare('DELETE FROM recovery WHERE account_id=?').run(account.id);
    });
    res.json({ ok: true });
  });
  app.get('/api/money-manager/data', (req, res) => {
    const account = authenticate(req);
    const row = db.prepare('SELECT data FROM money WHERE account_id=?').get(account.id);
    const value = row ? { ...emptyData(), ...JSON.parse(row.data) } : emptyData();
    if (req.query.cursor !== undefined) return res.json(dataPage(value, req.query));
    if (Buffer.byteLength(JSON.stringify(value)) > 4 * 1024 * 1024) throw new ApiError(426, 'Update the app to download this account in pages.');
    res.json(value);
  });
  app.post('/api/money-manager/data', (req, res) => {
    const account = authenticate(req);
    if (![2, 3].includes(req.body?.protocol)) throw new ApiError(426, 'Update the app before syncing. Your saved data has not changed.');
    validateData(req.body);
    const merged = transaction(() => {
      const row = db.prepare('SELECT data FROM money WHERE account_id=?').get(account.id);
      const value = mergeData(row ? JSON.parse(row.data) : emptyData(), req.body);
      if (req.body.protocol === 2 && Buffer.byteLength(JSON.stringify(value)) > 4 * 1024 * 1024) throw new ApiError(426, 'Update the app to sync this account in pages. Nothing was changed.');
      db.prepare('INSERT INTO money VALUES (?, ?) ON CONFLICT(account_id) DO UPDATE SET data=excluded.data').run(account.id, JSON.stringify(value));
      return value;
    });
    res.json(req.body.protocol === 3 ? { ok: true, protocol: 3 } : merged);
  });
  app.get('/api/update/latest', async (_req, res) => {
    const manifest = await publishedRelease(releasesDir);
    res.json({ ...manifest, apkUrl: `/releases/${encodeURIComponent(manifest.apkFile)}` });
  });
  app.use('/releases', (req, res, next) => {
    if (!req.path.endsWith('.apk')) return res.sendStatus(404);
    next();
  }, express.static(releasesDir, { dotfiles: 'deny', index: false }));
  app.use((error, _req, res, _next) => {
    const status = error instanceof ApiError ? error.status : error.type === 'entity.too.large' ? 413 : error instanceof SyntaxError && error.type === 'entity.parse.failed' ? 400 : 500;
    if (status === 429) res.set('Retry-After', '900');
    if (status === 500) console.error('Money Manager backend request failed.');
    res.status(status).json({ message: error instanceof ApiError ? error.message : status === 400 ? 'Invalid JSON request.' : status === 413 ? 'Request is too large.' : 'Server could not save your request. Please retry.' });
  });
  return app;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = await createApp();
  const port = Number(process.env.PORT || 3002);
  const cert = process.env.TLS_CERT;
  const key = process.env.TLS_KEY;
  if (Boolean(cert) !== Boolean(key)) throw new Error('Set both TLS_CERT and TLS_KEY.');
  // HTTP is restricted to loopback for a local TLS reverse proxy or development.
  const host = cert ? (process.env.HOST || '0.0.0.0') : '127.0.0.1';
  const server = cert ? https.createServer({ cert: await fs.readFile(cert), key: await fs.readFile(key), minVersion: 'TLSv1.2' }, app) : app;
  server.listen(port, host, () => console.log(`Money Manager backend: ${cert ? 'https' : 'http'}://${host}:${port}`));
  if (process.env.LAN_INSTALL_PORT) {
    if (!cert) throw new Error('The LAN installer requires the main API to use HTTPS.');
    createInstaller().listen(Number(process.env.LAN_INSTALL_PORT), '0.0.0.0', () => console.log(`Public LAN installer: port ${process.env.LAN_INSTALL_PORT}`));
  }
}
