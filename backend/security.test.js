import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createHash, scryptSync } from 'node:crypto';
import { createApp, createInstaller } from './server.js';
import { openDatabase } from './database.js';

const password = 'a-good-test-password';

test('public installer serves verified APK only and never exposes account APIs', async t => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'mm-installer-'));
  const app = createInstaller({ releasesDir: directory });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(async () => { await new Promise(resolve => server.close(resolve)); await fs.rm(directory, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const bytes = Buffer.from('PK-test-fixture');
  const manifest = { applicationId: 'com.thanhhao.money_manager.lan', signerSha256: 'a'.repeat(64), versionCode: 260919001, versionName: '260919.1', apkFile: 'money_manager-260919.1.apk', sizeBytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
  await fs.writeFile(path.join(directory, manifest.apkFile), bytes);
  await fs.writeFile(path.join(directory, 'latest.json'), JSON.stringify(manifest));
  assert.equal((await fetch(base)).status, 200);
  assert.deepEqual(Buffer.from(await (await fetch(`${base}/download`)).arrayBuffer()), bytes);
  for (const route of ['/api/auth/login', '/api/money-manager/data', '/latest.json', '/server-data/accounts.json']) {
    assert.equal((await fetch(`${base}${route}`)).status, 404);
    assert.equal((await fetch(`${base}${route}`, { method: 'POST' })).status, 405);
  }
  await fs.appendFile(path.join(directory, manifest.apkFile), 'tamper');
  assert.equal((await fetch(`${base}/download`)).status, 503);
});
const tx = (id) => ({ id, title: 'Expense', category: 'Food', amount: 10000, date: '2026-09-19T00:00:00.000Z', type: 'expense' });
const payload = (transactions = [], extra = {}) => ({ protocol: 2, transactions, recurring: [], deletedTransactions: [], deletedRecurring: [], ...extra });
async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'mm-security-'));
  const app = await createApp({ dataDir: directory, releasesDir: path.join(directory, 'releases'), origins: ['https://allowed.example'] });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  t.after(async () => { await new Promise(resolve => server.close(resolve)); app.locals.db.close(); await fs.rm(directory, { recursive: true, force: true }); });
  async function request(route, body, token, extra = {}) {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${route}`, { method: body === undefined ? 'GET' : 'POST', headers: { ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...extra }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await response.text();
    let data; try { data = JSON.parse(text); } catch { data = text; }
    return { status: response.status, data, headers: response.headers };
  }
  const register = async (name) => { const r = await request('/api/auth/register', { name, password }); assert.equal(r.status, 201); return r.data; };
  return { directory, app, server, request, register };
}

test('unauthenticated reset and legacy credentials cannot take over an account', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice');
  assert.equal((await request('/api/auth/reset-password', { name: 'alice', newPassword: 'attacker-password' })).status, 400);
  assert.equal((await request('/api/auth/login', { name: 'alice', password: 'attacker-password' })).status, 401);
  assert.equal((await request('/api/auth/login', { name: 'alice', password })).status, 200);
  assert.equal((await request('/api/money-manager/data')).status, 401);
  assert.equal((await request('/api/money-manager/data', undefined, undefined, { 'X-User-Name': 'alice', 'X-Password': password })).status, 401);
  assert.equal((await request('/api/money-manager/data', undefined, alice.token)).status, 200);
});

test('data is scoped to authenticated account and cannot be selected with a query', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice'), bob = await register('bob');
  assert.equal((await request('/api/money-manager/data', payload([tx('private')]), alice.token)).status, 200);
  assert.deepEqual((await request(`/api/money-manager/data?accountId=${alice.id}`, undefined, bob.token)).data.transactions, []);
  for (const route of ['/server-data/accounts.json', '/server-data/money-manager.sqlite', '/server.js', '/releases/%2e%2e/server-data/accounts.json']) assert.equal((await request(route)).status, 404);
});

test('parallel writes retain every transaction for same and different accounts', async t => {
  const { request, register } = await fixture(t);
  const users = await Promise.all(['alice', 'bob', 'charlie', 'dana'].map(register));
  const responses = await Promise.all(users.flatMap((user, i) => Array.from({ length: 6 }, (_, n) => request('/api/money-manager/data', payload([tx(`${i}-${n}`)]), user.token))));
  assert.ok(responses.every(r => r.status === 200));
  for (const user of users) assert.equal((await request('/api/money-manager/data', undefined, user.token)).data.transactions.length, 6);
});

test('concurrent duplicate registration creates only one account', async t => {
  const { request, app } = await fixture(t);
  const results = await Promise.all(Array.from({ length: 4 }, () => request('/api/auth/register', { name: 'same', password })));
  assert.equal(results.filter(r => r.status === 201).length, 1);
  assert.equal(results.filter(r => r.status === 409).length, 3);
  assert.equal(app.locals.db.prepare('SELECT count(*) n FROM accounts').get().n, 1);
});

test('deletions survive an old device syncing stale transactions and schedules', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice');
  const rule = { id: 'schedule', title: 'Lunch', category: 'Food', amount: 10000, frequency: 'daily', dayOfMonth: 19, active: true, lastAppliedAt: '2026-09-19T00:00:00.000Z' };
  const stale = payload([tx('old')], { recurring: [rule] });
  await request('/api/money-manager/data', stale, alice.token);
  await request('/api/money-manager/data', payload([], { deletedTransactions: ['old'], deletedRecurring: ['schedule'] }), alice.token);
  const result = await request('/api/money-manager/data', stale, alice.token);
  assert.deepEqual(result.data.transactions, []);
  assert.deepEqual(result.data.recurring, []);
  assert.deepEqual(result.data.deletedTransactions, ['old']);
  const undo = await request('/api/money-manager/data', payload([tx('restored-new-id')]), alice.token);
  assert.equal(undo.data.transactions[0].id, 'restored-new-id');
});

test('invalid sync data cannot overwrite saved data', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice');
  await request('/api/money-manager/data', payload([tx('saved')]), alice.token);
  for (const value of [payload([null]), payload([{ ...tx('bad'), amount: -1 }]), payload([{ ...tx('bad'), date: 'wrong' }]), payload([tx('same'), tx('same')]), { protocol: 2 }, payload([], { recurring: [false] })]) assert.equal((await request('/api/money-manager/data', value, alice.token)).status, 400);
  assert.equal((await request('/api/money-manager/data', {}, alice.token)).status, 426);
  assert.equal((await request('/api/money-manager/data', payload(), alice.token)).data.transactions.length, 1);
});

test('login errors are uniform and attempts are throttled persistently', async t => {
  const { request, register, app } = await fixture(t);
  await register('alice');
  const wrong = await request('/api/auth/login', { name: 'alice', password: 'wrong' });
  const absent = await request('/api/auth/login', { name: 'absent', password: 'wrong' });
  assert.equal(wrong.status, absent.status); assert.deepEqual(wrong.data, absent.data);
  const results = [];
  for (let i = 0; i < 16; i++) results.push(await request('/api/auth/login', { name: 'alice', password: 'wrong' }));
  assert.ok(results.some(r => r.status === 429 && r.headers.has('retry-after')));
  assert.ok(app.locals.db.prepare('SELECT count(*) n FROM limits').get().n > 0);
  assert.equal((await request('/api/auth/register', { name: 'weak', password: '1234' })).status, 400);
});

test('password change checks current password, rotates session and revokes old sessions', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice');
  assert.equal((await request('/api/auth/update', { currentPassword: password, newPassword: 'another-good-password' })).status, 401);
  assert.equal((await request('/api/auth/update', { currentPassword: 'wrong', newPassword: 'another-good-password' }, alice.token)).status, 401);
  const update = await request('/api/auth/update', { currentPassword: password, newPassword: 'another-good-password' }, alice.token);
  assert.equal(update.status, 200);
  assert.equal((await request('/api/money-manager/data', undefined, alice.token)).status, 401);
  assert.equal((await request('/api/money-manager/data', undefined, update.data.token)).status, 200);
  await request('/api/auth/logout', {}, update.data.token);
  assert.equal((await request('/api/money-manager/data', undefined, update.data.token)).status, 401);
});

test('recovery code is account-bound, expiring and single-use', async t => {
  const { request, register, app } = await fixture(t);
  const alice = await register('alice'); await register('bob');
  const code = 'a'.repeat(64);
  const hash = createHash('sha256').update(code).digest('hex');
  app.locals.db.prepare('INSERT INTO recovery VALUES (?, ?, ?)').run(hash, alice.id, Date.now() + 60000);
  const body = { name: 'bob', recoveryCode: code, newPassword: 'new-long-password' };
  assert.equal((await request('/api/auth/reset-password', body)).status, 400);
  body.name = 'alice';
  assert.equal((await request('/api/auth/reset-password', body)).status, 200);
  assert.equal((await request('/api/auth/reset-password', body)).status, 400);
  assert.equal((await request('/api/money-manager/data', undefined, alice.token)).status, 401);
  app.locals.db.prepare('INSERT INTO recovery VALUES (?, ?, ?)').run(hash, alice.id, Date.now() - 1);
  assert.equal((await request('/api/auth/reset-password', body)).status, 400);
});

test('bad JSON returns a generic error and CORS allows only configured web origins', async t => {
  const { request, server } = await fixture(t);
  const malformed = await fetch(`http://127.0.0.1:${server.address().port}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{bad' });
  assert.equal(malformed.status, 400); assert.deepEqual(await malformed.json(), { message: 'Invalid JSON request.' });
  assert.equal((await request('/api/health', undefined, undefined, { Origin: 'https://evil.example' })).status, 403);
  assert.equal((await request('/api/health', undefined, undefined, { Origin: 'https://allowed.example' })).headers.get('access-control-allow-origin'), 'https://allowed.example');
});

test('update metadata requires and verifies size and digest', async t => {
  const { directory, request } = await fixture(t);
  const releases = path.join(directory, 'releases'); await fs.mkdir(releases);
  const bytes = Buffer.from('PK\x03\x04test-only');
  const manifest = { versionCode: 10, versionName: 'test', apkFile: 'app.apk', sha256: createHash('sha256').update(bytes).digest('hex'), sizeBytes: bytes.length };
  await fs.writeFile(path.join(releases, 'app.apk'), bytes);
  await fs.writeFile(path.join(releases, 'latest.json'), JSON.stringify(manifest));
  assert.equal((await request('/api/update/latest')).status, 200);
  await fs.appendFile(path.join(releases, 'app.apk'), 'corruption');
  assert.equal((await request('/api/update/latest')).status, 503);
});

test('legacy JSON imports once and corrupt JSON is preserved without empty fallback', async t => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'mm-migration-'));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const salt = 'a'.repeat(32);
  const accounts = [{ id: 'legacy', name: 'Alice', passwordHash: `${salt}:${scryptSync(password, salt, 32).toString('hex')}` }];
  await fs.writeFile(path.join(dir, 'accounts.json'), JSON.stringify(accounts));
  const oldMoney = JSON.stringify({ legacy: { transactions: [tx('old')], recurring: [] } });
  await fs.writeFile(path.join(dir, 'money-manager.json'), oldMoney);
  let opened = openDatabase(dir);
  assert.equal(JSON.parse(opened.db.prepare('SELECT data FROM money').get().data).transactions[0].id, 'old');
  opened.db.close();
  assert.equal(await fs.readFile(path.join(dir, 'money-manager.json'), 'utf8'), oldMoney);
  opened = openDatabase(dir); assert.equal(opened.db.prepare('SELECT count(*) n FROM accounts').get().n, 1); opened.db.close();
  const bad = path.join(dir, 'bad'); await fs.mkdir(bad); await fs.writeFile(path.join(bad, 'money-manager.json'), '{broken');
  assert.throws(() => openDatabase(bad));
  assert.equal(await fs.readFile(path.join(bad, 'money-manager.json'), 'utf8'), '{broken');
});

test('logout revokes tokens even when both authentication and API limits are exhausted', async t => {
  const { request, register, app } = await fixture(t);
  const alice = await register('alice');
  for (let i = 0; i < 31; i++) await request('/api/auth/login', { name: `absent-${i}`, password: 'wrong' });
  assert.equal((await request('/api/auth/login', { name: 'alice', password })).status, 429);
  app.locals.db.prepare("UPDATE limits SET count=300 WHERE key LIKE 'api:%'").run();
  assert.equal((await request('/api/auth/logout', {}, alice.token)).status, 200);
  app.locals.db.prepare("DELETE FROM limits WHERE key LIKE 'api:%'").run();
  assert.equal((await request('/api/money-manager/data', undefined, alice.token)).status, 401);
  assert.equal((await request('/api/auth/logout', {}, alice.token)).status, 200);
});

test('failed attempts cannot lock an account globally and success resets its IP pair counter', async t => {
  const { request, register, app } = await fixture(t);
  await register('alice');
  const nameHash = createHash('sha256').update('alice').digest('hex');
  app.locals.db.prepare('INSERT INTO limits VALUES (?, 15, ?)').run(`login:192.0.2.10:${nameHash}`, Date.now() + 900000);
  // Existing global name counters from the previous version must not lock users.
  app.locals.db.prepare('INSERT INTO limits VALUES (?, 15, ?)').run(`name:${nameHash}`, Date.now() + 900000);
  for (let i = 0; i < 14; i++) assert.equal((await request('/api/auth/login', { name: 'alice', password: 'wrong' })).status, 401);
  assert.equal((await request('/api/auth/login', { name: 'alice', password })).status, 200);
  assert.equal((await request('/api/auth/login', { name: 'alice', password })).status, 200);
});

test('large accounts upload and download in bounded pages without rejecting valid data', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice'), bob = await register('bob');
  const transactions = Array.from({ length: 2400 }, (_, i) => ({ ...tx(`big-${i}`), title: 't'.repeat(500), note: 'n'.repeat(2000) }));
  for (let start = 0; start < 2400; start += 1200) {
    const result = await request('/api/money-manager/data', payload(transactions.slice(start, start + 1200), { protocol: 3 }), alice.token);
    assert.equal(result.status, 200);
    assert.deepEqual(result.data, { ok: true, protocol: 3 });
  }
  let cursor = 0, revision, downloaded = [];
  do {
    const result = await request(`/api/money-manager/data?cursor=${cursor}${revision ? `&revision=${revision}` : ''}`, undefined, alice.token);
    assert.equal(result.status, 200);
    assert.ok(Buffer.byteLength(JSON.stringify(result.data)) < 512 * 1024);
    if (revision) assert.equal(result.data.revision, revision);
    revision = result.data.revision;
    downloaded.push(...result.data.transactions);
    cursor = result.data.nextCursor;
  } while (cursor !== null);
  assert.deepEqual(downloaded, transactions);
  assert.equal((await request('/api/money-manager/data?cursor=0', undefined, bob.token)).data.transactions.length, 0);
  assert.equal((await request('/api/money-manager/data', payload(), alice.token)).status, 426);
  assert.equal((await request('/api/money-manager/data', undefined, alice.token)).status, 426);
  await request('/api/money-manager/data', payload([tx('concurrent')], { protocol: 3 }), alice.token);
  assert.equal((await request(`/api/money-manager/data?cursor=1&revision=${revision}`, undefined, alice.token)).status, 409);
  for (const invalid of ['-1', '1.5', '90000', 'wrong']) assert.equal((await request(`/api/money-manager/data?cursor=${invalid}`, undefined, bob.token)).status, 400);
});

test('legacy sync cannot commit a snapshot too large for legacy readers', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice');
  const big = (prefix) => Array.from({ length: 1200 }, (_, i) => ({ ...tx(`${prefix}-${i}`), title: 't'.repeat(500), note: 'n'.repeat(2000) }));
  assert.equal((await request('/api/money-manager/data', payload(big('first')), alice.token)).status, 200);
  assert.equal((await request('/api/money-manager/data', payload(big('second')), alice.token)).status, 426);
  assert.equal((await request('/api/money-manager/data', undefined, alice.token)).data.transactions.length, 1200);
});

test('transaction conflict keeps newer date and keeps server content on ties', async t => {
  const { request, register } = await fixture(t);
  const alice = await register('alice');
  const newer = { ...tx('same'), date: '2026-09-20T00:00:00.000Z', amount: 20000 };
  await request('/api/money-manager/data', payload([tx('same')]), alice.token);
  assert.equal((await request('/api/money-manager/data', payload([newer]), alice.token)).data.transactions[0].amount, 20000);
  assert.equal((await request('/api/money-manager/data', payload([tx('same')]), alice.token)).data.transactions[0].amount, 20000);
  assert.equal((await request('/api/money-manager/data', payload([{ ...newer, amount: 30000 }]), alice.token)).data.transactions[0].amount, 20000);
});


test('legacy password hashes upgrade on verified login without exposing credentials', async t => {
  const { request, register, app, directory } = await fixture(t);
  const alice = await register('alice');
  const salt = 'b'.repeat(32);
  const legacy = `${salt}:${scryptSync(password, salt, 32).toString('hex')}`;
  app.locals.db.prepare('UPDATE accounts SET password_hash=? WHERE id=?').run(legacy, alice.id);
  await request('/api/money-manager/data', payload([tx('retained')]), alice.token);
  assert.equal((await request('/api/auth/login', { name: 'alice', password: 'wrong' })).status, 401);
  assert.equal(app.locals.db.prepare('SELECT password_hash FROM accounts WHERE id=?').get(alice.id).password_hash, legacy);
  const signed = await request('/api/auth/login', { name: 'alice', password });
  assert.equal(signed.status, 200);
  assert.match(app.locals.db.prepare('SELECT password_hash FROM accounts WHERE id=?').get(alice.id).password_hash, /^scrypt-v2:[a-f0-9]{32}:[a-f0-9]{64}$/);
  assert.deepEqual(Object.keys(signed.data).sort(), ['expires', 'id', 'name', 'ok', 'token']);
  const data = await request('/api/money-manager/data', undefined, signed.data.token);
  assert.equal(data.data.transactions[0].id, 'retained');
  assert.equal(data.headers.get('cache-control'), 'no-store');
  assert.equal(data.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(app.locals.db.prepare('SELECT count(*) n FROM sessions WHERE hash=?').get(signed.data.token).n, 0);
  assert.equal((await fs.stat(path.join(directory, 'money-manager.sqlite'))).mode & 0o777, 0o600);
});
