import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function freePort() {
  const socket = createServer();
  await new Promise((resolve) => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise((resolve) => socket.close(resolve));
  return port;
}

test('registration keeps normalized user names unique and existing passwords intact', async () => {
  const temp = await mkdtemp(path.join(tmpdir(), 'vmc-register-test-'));
  const dataDir = path.join(temp, 'data');
  const port = await freePort();
  const base = `http://127.0.0.1:${port}`;
  await mkdir(dataDir, { recursive: true });
  const server = spawn('node', ['backend/server.js'], {
    cwd: projectRoot,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_DIR: dataDir,
      PHOTO_ROOT: path.join(temp, 'photos'),
    },
    stdio: 'ignore',
  });
  try {
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      try {
        if ((await fetch(`${base}/api/health`)).ok) {
          ready = true;
          break;
        }
      } catch { /* Backend is starting. */ }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    assert.ok(ready, 'backend started');

    async function post(route, body, headers = {}) {
      return fetch(`${base}${route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers },
        body: JSON.stringify(body),
      });
    }
    assert.equal((await post('/api/auth/register', {
      name: 'Traveler', password: 'original-pass',
    })).status, 201);
    const duplicate = await post('/api/auth/register', {
      name: ' traveler ', password: 'other-pass',
    });
    assert.equal(duplicate.status, 409);
    assert.equal((await duplicate.json()).error, 'account_exists');

    const concurrent = await Promise.all([
      post('/api/auth/register', { name: 'Explorer', password: 'first-pass' }),
      post('/api/auth/register', { name: ' EXPLORER ', password: 'second-pass' }),
    ]);
    assert.deepEqual(concurrent.map((response) => response.status).sort(), [201, 409]);
    assert.equal((await post('/api/auth/register', {
      name: 'Café', password: 'cafe-pass',
    })).status, 201);
    assert.equal((await post('/api/auth/register', {
      name: 'Cafe\u0301', password: 'other-pass',
    })).status, 409);

    assert.equal((await post('/api/auth/login', {
      name: 'TRAVELER', password: 'original-pass',
    })).status, 200);
    assert.equal((await post('/api/auth/login', {
      name: 'Traveler', password: 'other-pass',
    })).status, 401);
    assert.equal((await post('/api/auth/reset-password', {
      name: 'Traveler', newPassword: 'hijacked-pass',
    })).status, 401);
    assert.equal((await post('/api/auth/login', {
      name: 'Traveler', password: 'original-pass',
    })).status, 200);
    assert.equal((await post('/api/auth/update', {
      name: 'Traveler', newName: 'explorer',
    }, { 'X-Password': 'original-pass' })).status, 409);

    const accounts = JSON.parse(await readFile(path.join(dataDir, 'accounts.json'), 'utf8'));
    assert.deepEqual(accounts.map((account) => account.name).sort(),
      ['Café', 'Explorer', 'Traveler']);
  } finally {
    server.kill();
    await rm(temp, { recursive: true, force: true });
  }
});
