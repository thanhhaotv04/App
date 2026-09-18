import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function freePort() {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

test('albums and photos stay scoped and survive account rename without changing check-ins', async () => {
  const temp = await mkdtemp(path.join(tmpdir(), 'vmc-album-test-'));
  const dataDir = path.join(temp, 'data');
  const photoRoot = path.join(temp, 'photos');
  const port = await freePort();
  const base = `http://127.0.0.1:${port}`;
  const server = spawn('node', ['backend/server.js'], {
    cwd: projectRoot,
    env: { ...process.env, PORT: String(port), DATA_DIR: dataDir, PHOTO_ROOT: photoRoot },
    stdio: 'ignore',
  });
  try {
    await mkdir(dataDir, { recursive: true });
    const originalCheckins = JSON.stringify({ untouched: [{ id: 'existing' }] });
    await writeFile(path.join(dataDir, 'checkins.json'), originalCheckins);
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      try {
        const response = await fetch(`${base}/api/health`);
        if (response.ok) { ready = true; break; }
      } catch { /* Server is starting. */ }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    assert.ok(ready, 'backend started');

    async function register(name) {
      const response = await fetch(`${base}/api/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, password: 'test-password' }),
      });
      assert.equal(response.status, 201);
      return { 'X-User-Name': name, 'X-Password': 'test-password' };
    }
    const alice = await register('Alice');
    const bob = await register('Bob');
    const unauthorized = await fetch(`${base}/api/albums`);
    assert.equal(unauthorized.status, 401);

    const created = await fetch(`${base}/api/albums`, {
      method: 'POST',
      headers: { ...alice, 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: 'album-1', name: 'Đà Lạt', createdAt: 100, updatedAt: 100, checkInIds: [], photos: [] }),
    });
    assert.equal(created.status, 200);
    assert.equal((await created.json()).name, 'Đà Lạt');

    const form = new FormData();
    form.set('photoId', 'photo-1');
    form.set('createdAt', '101');
    form.set('place', 'Hồ Xuân Hương');
    form.set('note', 'Buổi chiều bên hồ');
    form.set('photo', new Blob([Uint8Array.of(0xff, 0xd8, 0xff, 0xe0)], { type: 'image/jpeg' }), 'trip.jpg');
    const upload = await fetch(`${base}/api/albums/album-1/photos`, {
      method: 'POST', headers: alice, body: form,
    });
    assert.equal(upload.status, 200);
    const photo = await upload.json();
    assert.match(photo.photo, /^user\/Picture\/[a-f0-9-]+\/albums\/album-1\//);
    assert.equal(photo.place, 'Hồ Xuân Hương');
    assert.equal(photo.note, 'Buổi chiều bên hồ');
    assert.equal((await fetch(`${base}/${photo.photo}`)).status, 401);
    assert.equal((await fetch(`${base}/${photo.photo}`, { headers: bob })).status, 404);
    assert.equal((await fetch(`${base}/${photo.photo}`, { headers: alice })).status, 200);

    const aliceAlbums = await (await fetch(`${base}/api/albums`, { headers: alice })).json();
    const bobAlbums = await (await fetch(`${base}/api/albums`, { headers: bob })).json();
    assert.equal(aliceAlbums.length, 1);
    assert.equal(aliceAlbums[0].photos.length, 1);
    assert.deepEqual(bobAlbums, []);
    assert.equal(await readFile(path.join(dataDir, 'checkins.json'), 'utf8'), originalCheckins);
    assert.equal((await readdir(path.join(photoRoot, ...photo.photo.split('/').slice(2, -1)))).length, 1);

    const removed = await fetch(`${base}/api/albums`, {
      method: 'POST',
      headers: { ...alice, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: 'album-1', name: 'Đà Lạt', createdAt: 100, updatedAt: 200,
        checkInIds: [], photos: [], deletedPhotoIds: ['photo-1'],
      }),
    });
    assert.equal(removed.status, 200);
    assert.equal((await removed.json()).photos.length, 0);
    assert.equal((await fetch(`${base}/${photo.photo}`, { headers: alice })).status, 404);
    assert.equal(await readFile(path.join(dataDir, 'checkins.json'), 'utf8'), originalCheckins);
    assert.deepEqual((await (await fetch(`${base}/api/albums`, { headers: bob })).json()), []);

    const visit = await fetch(`${base}/api/checkins`, {
      method: 'POST',
      headers: { ...alice, 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: 'visit-1', city: 'Lâm Đồng', place: 'Hồ Xuân Hương', lat: 0, lng: 0 }),
    });
    assert.equal(visit.status, 200);
    const checkinsWithVisit = await readFile(path.join(dataDir, 'checkins.json'), 'utf8');
    async function setAlbumLinks(checkInIds, excludedCheckInIds, updatedAt) {
      const response = await fetch(`${base}/api/albums`, {
        method: 'POST',
        headers: { ...alice, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id: 'album-1', name: 'Đà Lạt', createdAt: 100, updatedAt,
          checkInIds, excludedCheckInIds, photos: [], deletedPhotoIds: ['photo-1'],
        }),
      });
      assert.equal(response.status, 200);
      return response.json();
    }
    const nextTime = Date.now() + 1000;
    assert.deepEqual((await setAlbumLinks(['visit-1'], [], nextTime)).checkInIds, ['visit-1']);
    const unlinked = await setAlbumLinks([], ['visit-1'], nextTime + 1);
    assert.deepEqual(unlinked.checkInIds, []);
    assert.deepEqual(unlinked.excludedCheckInIds, ['visit-1']);
    const relinked = await setAlbumLinks(['visit-1'], [], nextTime + 2);
    assert.deepEqual(relinked.checkInIds, ['visit-1']);
    assert.deepEqual(relinked.excludedCheckInIds, []);
    assert.equal(await readFile(path.join(dataDir, 'checkins.json'), 'utf8'), checkinsWithVisit);

    const secondForm = new FormData();
    secondForm.set('photoId', 'photo-2');
    secondForm.set('photo', new Blob([Uint8Array.of(0xff, 0xd8, 0xff, 0xe0)], { type: 'image/jpeg' }), 'second.jpg');
    const secondUpload = await fetch(`${base}/api/albums/album-1/photos`, {
      method: 'POST', headers: alice, body: secondForm,
    });
    assert.equal(secondUpload.status, 200);
    const secondPhoto = await secondUpload.json();
    assert.equal((await fetch(`${base}/${secondPhoto.photo}`, { headers: alice })).status, 200);

    const deleted = await fetch(`${base}/api/albums`, {
      method: 'POST',
      headers: { ...alice, 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: 'album-1', name: 'Đà Lạt', createdAt: 100,
        updatedAt: nextTime + 3, isDeleted: true, checkInIds: [], photos: [] }),
    });
    assert.equal(deleted.status, 200);
    assert.equal((await deleted.json()).isDeleted, true);
    assert.equal((await fetch(`${base}/${secondPhoto.photo}`, { headers: alice })).status, 404);
    const stale = await setAlbumLinks(['visit-1'], [], nextTime + 2);
    assert.equal(stale.isDeleted, true);
    assert.deepEqual(stale.checkInIds, []);
    const blockedUpload = new FormData();
    blockedUpload.set('photoId', 'photo-new');
    blockedUpload.set('photo', new Blob([Uint8Array.of(0xff, 0xd8, 0xff, 0xe0)], { type: 'image/jpeg' }), 'new.jpg');
    assert.equal((await fetch(`${base}/api/albums/album-1/photos`, {
      method: 'POST', headers: alice, body: blockedUpload,
    })).status, 409);
    assert.equal(await readFile(path.join(dataDir, 'checkins.json'), 'utf8'), checkinsWithVisit);

    const renamed = await fetch(`${base}/api/auth/update`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Password': 'test-password' },
      body: JSON.stringify({ name: 'Alice', newName: 'Alicia' }),
    });
    assert.equal(renamed.status, 200);
    const renamedAlbums = await fetch(`${base}/api/albums`, {
      headers: { 'X-User-Name': 'Alicia', 'X-Password': 'test-password' },
    });
    assert.equal(renamedAlbums.status, 200);
    const renamedAlbum = (await renamedAlbums.json())[0];
    assert.deepEqual(renamedAlbum.deletedPhotoIds, ['photo-1']);
    assert.equal(renamedAlbum.isDeleted, true);
    assert.equal(await readFile(path.join(dataDir, 'checkins.json'), 'utf8'), checkinsWithVisit);
  } finally {
    server.kill();
    await rm(temp, { recursive: true, force: true });
  }
});

test('renaming a legacy account keeps its check-ins available by account ID', async () => {
  const temp = await mkdtemp(path.join(tmpdir(), 'vmc-legacy-rename-test-'));
  const dataDir = path.join(temp, 'data');
  const port = await freePort();
  const base = `http://127.0.0.1:${port}`;
  const server = spawn('node', ['backend/server.js'], {
    cwd: projectRoot,
    env: { ...process.env, PORT: String(port), DATA_DIR: dataDir, PHOTO_ROOT: path.join(temp, 'photos') },
    stdio: 'ignore',
  });
  try {
    await mkdir(dataDir, { recursive: true });
    const legacy = [{ id: 'old-trip', city: 'Lâm Đồng', place: 'Hồ Xuân Hương' }];
    await writeFile(path.join(dataDir, 'checkins.json'), JSON.stringify(legacy));
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      try {
        if ((await fetch(`${base}/api/health`)).ok) { ready = true; break; }
      } catch { /* Server is starting. */ }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    assert.ok(ready, 'backend started');
    const registered = await fetch(`${base}/api/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'thanhhao', password: 'test-password' }),
    });
    assert.equal(registered.status, 201);
    const oldHeaders = { 'X-User-Name': 'thanhhao', 'X-Password': 'test-password' };
    assert.equal((await (await fetch(`${base}/api/checkins`, { headers: oldHeaders })).json()).length, 1);

    const renamed = await fetch(`${base}/api/auth/update`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Password': 'test-password' },
      body: JSON.stringify({ name: 'thanhhao', newName: 'new-name' }),
    });
    assert.equal(renamed.status, 200);
    const current = await fetch(`${base}/api/checkins`, {
      headers: { 'X-User-Name': 'new-name', 'X-Password': 'test-password' },
    });
    assert.equal(current.status, 200);
    assert.equal((await current.json())[0].id, 'old-trip');
    const stored = JSON.parse(await readFile(path.join(dataDir, 'checkins.json'), 'utf8'));
    assert.ok(Object.values(stored).some((items) => Array.isArray(items) && items[0]?.id === 'old-trip'));
  } finally {
    server.kill();
    await rm(temp, { recursive: true, force: true });
  }
});
