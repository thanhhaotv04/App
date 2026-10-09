import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

async function backend(t, { unclaimedLegacy = false } = {}) {
  const temp = await mkdtemp(path.join(tmpdir(), 'vmc-privacy-'));
  if (unclaimedLegacy) await writeFile(path.join(temp, 'checkins.json'), JSON.stringify([{ id: 'private-legacy-trip' }]));
  const socket = createServer();
  await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  const base = `http://127.0.0.1:${port}`;
  const server = spawn('node', [process.env.VMC_TEST_SERVER || 'backend/server.js'], {
    env: { ...process.env, PORT: String(port), DATA_DIR: temp, PHOTO_ROOT: path.join(temp, 'photos') },
    stdio: 'ignore',
  });
  t.after(async () => {
    server.kill();
    await new Promise(resolve => server.once('exit', resolve));
    await rm(temp, { recursive: true, force: true });
  });
  let ready = false;
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`${base}/api/health`)).ok) { ready = true; break; } } catch { /* Starting. */ }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.ok(ready, 'backend started');
  const post = (route, body, token) => fetch(`${base}${route}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  const register = async name => {
    const response = await post('/api/auth/register', { name, password: 'private-password' });
    assert.equal(response.status, 201);
    return (await response.json()).token;
  };
  const get = (route, token) => fetch(`${base}${route}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  return { temp, base, post, register, get };
}

test('photo paths cannot grant another account access, including username/ID collisions and traversal', async t => {
  const { temp, base, post, register, get } = await backend(t);
  const owner = await register('Photo owner');
  const accounts = JSON.parse(await readFile(path.join(temp, 'accounts.json'), 'utf8'));
  const intruder = await register(accounts[0].id);
  const createAlbum = token => post('/api/albums', { id: 'trip', name: 'Trip', updatedAt: 1, photos: [] }, token);
  assert.equal((await createAlbum(owner)).status, 200);
  assert.equal((await createAlbum(intruder)).status, 200);
  const form = new FormData();
  form.set('photoId', 'private-photo');
  form.set('photo', new Blob([Uint8Array.of(0xff, 0xd8, 0xff, 0xe0)], { type: 'image/jpeg' }), 'private.jpg');
  const upload = await fetch(`${base}/api/albums/trip/photos`, {
    method: 'POST', headers: { Authorization: `Bearer ${owner}` }, body: form,
  });
  assert.equal(upload.status, 200);
  const photo = await upload.json();
  const forged = await post('/api/albums', {
    id: 'trip', name: 'Trip', updatedAt: 2, photos: [photo],
  }, intruder);
  assert.deepEqual((await forged.json()).photos, []);
  assert.equal((await get(`/${photo.photo}`, intruder)).status, 404);
  assert.equal((await get(`/${photo.photo}`)).status, 401);

  for (const borrowed of [photo.photo, `user/Picture/${accounts[0].id}/../${photo.photo.slice('user/Picture/'.length)}`]) {
    const result = await post('/api/checkins', {
      id: 'forged', city: 'Huế', lat: 0, lng: 0, photoPath: borrowed,
      photos: [{ photo: borrowed, name: 'borrowed.jpg' }],
    }, intruder);
    const item = await result.json();
    assert.equal(item.photo, '');
    assert.deepEqual(item.photos, []);
  }
  assert.equal((await get(`/${photo.photo}`, owner)).status, 200);
  assert.equal((await get(`/${photo.photo}`, owner)).headers.get('cache-control'), 'no-store');
  // An owner can still retain uploaded photos when editing an album.
  const retained = await post('/api/albums', { id: 'trip', name: 'Renamed trip', photos: [photo], updatedAt: Date.now() }, owner);
  assert.equal((await retained.json()).photos[0].photo, photo.photo);
});

test('hidden coordinates are removed by the server, and private responses forbid caching', async t => {
  const { post, register, get, temp } = await backend(t);
  const token = await register('Coordinates');
  const response = await post('/api/checkins', {
    id: 'hidden', city: 'Đà Nẵng', lat: 16.06, lng: 108.22, hideLocation: true,
  }, token);
  assert.equal(response.status, 200);
  const item = await response.json();
  assert.equal(item.lat, 0);
  assert.equal(item.lng, 0);
  const persisted = await readFile(path.join(temp, 'checkins.json'), 'utf8');
  assert.ok(!persisted.includes('16.06') && !persisted.includes('108.22'));
  const privateData = await get('/api/checkins', token);
  assert.equal(privateData.headers.get('cache-control'), 'no-store');
  assert.equal((await get('/api/checkins')).status, 401);
  assert.equal((await get('/server-data/accounts.json')).status, 404);
});

test('legacy password headers cannot bypass rate limits via data and photo routes', async t => {
  const { register, base } = await backend(t);
  await register('Limited user');
  // Legacy installations can still load large galleries with valid credentials.
  for (let i = 0; i < 101; i++) {
    assert.equal((await fetch(`${base}/api/checkins`, { headers: { 'X-User-Name': 'Limited user', 'X-Password': 'private-password' } })).status, 200);
  }
  for (let i = 0; i < 20; i++) {
    assert.equal((await fetch(`${base}/api/checkins`, { headers: { 'X-User-Name': 'Limited user', 'X-Password': 'wrong-password' } })).status, 401);
  }
  const blocked = await fetch(`${base}/api/checkins`, { headers: { 'X-User-Name': 'Limited user', 'X-Password': 'wrong-password' } });
  assert.equal(blocked.status, 429);
  assert.ok(blocked.headers.has('retry-after'));
});

test('rotating user names does not bypass the per-IP authentication limit', async t => {
  const { post } = await backend(t);
  for (let i = 0; i < 100; i++) {
    assert.equal((await post('/api/auth/login', { name: `unknown-${i}`, password: 'wrong-password' })).status, 401);
  }
  assert.equal((await post('/api/auth/login', { name: 'another-name', password: 'wrong-password' })).status, 429);
});

test('concurrent logout and login preserve fresh sessions and revoke each old session', async t => {
  const { post, register, get } = await backend(t);
  const first = await register('Multi device');
  const second = (await (await post('/api/auth/login', { name: 'Multi device', password: 'private-password' })).json()).token;
  const [logout1, logout2, login] = await Promise.all([
    post('/api/auth/logout', {}, first), post('/api/auth/logout', {}, second),
    post('/api/auth/login', { name: 'Multi device', password: 'private-password' }),
  ]);
  assert.equal(logout1.status, 200);
  assert.equal(logout2.status, 200);
  const fresh = (await login.json()).token;
  assert.equal((await get('/api/checkins', first)).status, 401);
  assert.equal((await get('/api/checkins', second)).status, 401);
  assert.equal((await get('/api/checkins', fresh)).status, 200);
});

test('registering the old owner name cannot claim unowned legacy travel data', async t => {
  const { temp, register, get } = await backend(t, { unclaimedLegacy: true });
  const token = await register('thanhhao');
  assert.deepEqual(await (await get('/api/checkins', token)).json(), []);
  const stored = JSON.parse(await readFile(path.join(temp, 'checkins.json'), 'utf8'));
  assert.equal(stored.__legacy[0].id, 'private-legacy-trip');
  assert.equal(stored.__legacyOwnerId, '');
});
