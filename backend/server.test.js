import assert from "node:assert/strict";
import { mkdtemp, rm, mkdir, writeFile, readFile } from "node:fs/promises";
import { createHash, randomBytes, scryptSync } from 'node:crypto';
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

process.env.DATA_DIR = await mkdtemp(path.join(tmpdir(), "task-reminder-"));
process.env.RELEASES_DIR = path.join(process.env.DATA_DIR, 'releases');
await mkdir(process.env.RELEASES_DIR);
const apkBytes = Buffer.from('PK test release fixture');
await writeFile(path.join(process.env.RELEASES_DIR, 'fixture.apk'), apkBytes);
await writeFile(path.join(process.env.RELEASES_DIR, 'latest.json'), JSON.stringify({versionName: '1.0.6', versionCode: 7, apkFile: 'fixture.apk'}));
process.env.ALLOWED_ORIGINS = "http://allowed.example";
process.env.ALLOW_INSECURE_PASSWORD_RESET = "1"; // Must not re-enable takeover.

const { createApp } = await import("./server.js");
test.beforeEach(async () => {
  await rm(path.join(process.env.DATA_DIR, 'rate-limits.json'), {force: true});
});

async function withServer(run) {
  const server = createApp().listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const { port } = server.address();
  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

test.after(async () => {
  await rm(process.env.DATA_DIR, { recursive: true, force: true });
});

test("sets security headers and only echoes allowed CORS origins", async () => {
  await withServer(async (baseUrl) => {
    const allowed = await fetch(`${baseUrl}/api/health`, {
      headers: { Origin: "http://allowed.example" },
    });
    assert.equal(allowed.headers.get("access-control-allow-origin"), "http://allowed.example");
    assert.equal(allowed.headers.get("x-content-type-options"), "nosniff");
    assert.equal(allowed.headers.get("x-frame-options"), "DENY");
    for (const endpoint of ['/api/health', '/API/HEALTH', '/API/TASK-REMINDER/DATA']) {
      const response = await fetch(`${baseUrl}${endpoint}`);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      if (endpoint.endsWith('/DATA')) assert.equal(response.status, 401);
    }

    const rejected = await fetch(`${baseUrl}/api/health`, {
      headers: { Origin: "http://evil.example" },
    });
    assert.equal(rejected.status, 403);
    assert.equal(rejected.headers.get("access-control-allow-origin"), null);
  });
});

test("rejects weak passwords and disables public reset by default", async () => {
  await withServer(async (baseUrl) => {
    const weak = await fetch(`${baseUrl}/api/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "hao", password: "1234" }),
    });
    assert.equal(weak.status, 400);

    const reset = await fetch(`${baseUrl}/api/auth/reset-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "hao", newPassword: "new-pass-123" }),
    });
    assert.equal(reset.status, 403);
  });
});

test('login does not reveal whether an account exists', async () => {
  await withServer(async (baseUrl) => {
    const headers = {"Content-Type": "application/json"};
    await fetch(`${baseUrl}/api/auth/register`, {method: 'POST', headers,
      body: JSON.stringify({name: 'enumeration-target', password: 'password-123'})});
    const known = await fetch(`${baseUrl}/api/auth/login`, {method: 'POST', headers,
      body: JSON.stringify({name: 'enumeration-target', password: 'wrong-password'})});
    const missing = await fetch(`${baseUrl}/api/auth/login`, {method: 'POST', headers,
      body: JSON.stringify({name: 'enumeration-missing', password: 'wrong-password'})});
    assert.equal(known.status, 401);
    assert.equal(missing.status, 401);
    assert.deepEqual(await known.json(), await missing.json());
  });
});

test('legacy password hashes are upgraded after a successful login', async () => {
  await withServer(async (baseUrl) => {
    const credentials = {name: 'legacy-hash', password: 'password-123'};
    assert.equal((await request(baseUrl, '/api/auth/register', credentials)).status, 201);
    const accountsPath = path.join(process.env.DATA_DIR, 'accounts.json');
    const accounts = JSON.parse(await readFile(accountsPath, 'utf8'));
    const account = accounts.find((item) => item.name === credentials.name);
    const salt = randomBytes(16).toString('hex');
    account.passwordHash = `${salt}:${scryptSync(credentials.password, salt, 32).toString('hex')}`;
    account.sessions = [];
    await writeFile(accountsPath, `${JSON.stringify(accounts, null, 2)}\n`);

    assert.equal((await request(baseUrl, '/api/auth/login', credentials)).status, 200);
    const upgraded = JSON.parse(await readFile(accountsPath, 'utf8'))
      .find((item) => item.name === credentials.name);
    assert.match(upgraded.passwordHash, /^scrypt:17:8:1:/);
  });
});

test("sync data is account scoped and rejects oversized payloads", async () => {
  await withServer(async (baseUrl) => {
    const headers = { "Content-Type": "application/json" };
    const credentials = { name: "hao", password: "release-pass-123" };
    const register = await fetch(`${baseUrl}/api/auth/register`, {
      method: "POST",
      headers,
      body: JSON.stringify(credentials),
    });
    assert.equal(register.status, 201);
    const session = await register.json();
    assert.match(session.token, /^[A-Za-z0-9_-]{40,}$/);

    const authHeaders = {
      ...headers,
      Authorization: `Bearer ${session.token}`,
    };
    const oversized = await fetch(`${baseUrl}/api/task-reminder/data`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        tasks: Array.from({ length: 1001 }, (_, index) => ({
          id: `task-${index}`,
          title: "Task",
        })),
        assignments: [],
      }),
    });
    assert.equal(oversized.status, 400);

    const save = await fetch(`${baseUrl}/api/task-reminder/data`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        tasks: [{
          id: "task-1",
          title: "Task",
          note: "<b>note</b>",
          priority: "normal",
          iconKind: "study",
          estimateMinutes: 15,
          createdAt: "2026-09-22T00:00:00.000Z",
          updatedAt: "2026-09-22T00:00:00.000Z",
          deletedAt: null,
        }],
        assignments: [],
      }),
    });
    assert.equal(save.status, 200);

    const load = await fetch(`${baseUrl}/api/task-reminder/data`, {
      headers: authHeaders,
    });
    const data = await load.json();
    assert.equal(data.tasks.length, 1);
    assert.equal(data.tasks[0].id, "task-1");

    const bobRegister = await fetch(`${baseUrl}/api/auth/register`, {
      method: "POST",
      headers,
      body: JSON.stringify({ name: "bob", password: "release-pass-456" }),
    });
    const bob = await bobRegister.json();
    const bobLoad = await fetch(`${baseUrl}/api/task-reminder/data`, {
      headers: { Authorization: `Bearer ${bob.token}` },
    });
    assert.deepEqual(await bobLoad.json(), { tasks: [], assignments: [] });

    const logout = await fetch(`${baseUrl}/api/auth/logout`, {
      method: "POST",
      headers: authHeaders,
      body: '{}',
    });
    assert.equal(logout.status, 200);
    const afterLogout = await fetch(`${baseUrl}/api/task-reminder/data`, {
      headers: authHeaders,
    });
    assert.equal(afterLogout.status, 401);
  });
});

test("serializes concurrent account writes without losing users", async () => {
  await withServer(async (baseUrl) => {
    const headers = { "Content-Type": "application/json" };
    const users = Array.from({ length: 6 }, (_, index) => ({
      name: `parallel-${index}`,
      password: `parallel-password-${index}`,
    }));
    const registrations = await Promise.all(users.map((credentials) =>
      fetch(`${baseUrl}/api/auth/register`, {
        method: "POST",
        headers,
        body: JSON.stringify(credentials),
      })
    ));
    assert.ok(registrations.every((response) => response.status === 201));

    const logins = await Promise.all(users.map((credentials) =>
      fetch(`${baseUrl}/api/auth/login`, {
        method: "POST",
        headers,
        body: JSON.stringify(credentials),
      })
    ));
    assert.ok(logins.every((response) => response.status === 200));
  });
});

test("update manifest includes APK integrity metadata", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/api/update/latest`);
    assert.equal(response.status, 200);
    const manifest = await response.json();
    assert.match(manifest.sha256, /^[a-f0-9]{64}$/);
    assert.equal(manifest.sha256, createHash('sha256').update(apkBytes).digest('hex'));
    assert.equal(manifest.size, apkBytes.length);
  });
});

async function request(base, endpoint, body, token) {
  return fetch(`${base}${endpoint}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
  });
}

const snapshotTask = (id, extra = {}) => ({id, title: id, note: '', priority: 'normal',
  iconKind: 'study', estimateMinutes: 15, createdAt: '2026-09-22T00:00:00.000Z',
  updatedAt: '2026-09-22T00:00:00.000Z', deletedAt: null, ...extra});

test('concurrent snapshots merge; stale edits cannot resurrect deleted tasks', async () => {
  await withServer(async (base) => {
    const account = await (await request(base, '/api/auth/register', {name: 'multi-device', password: 'password-123'})).json();
    const save = (tasks, assignments = []) => request(base, '/api/task-reminder/data', {tasks, assignments}, account.token);
    const results = await Promise.all([save([snapshotTask('a')]), save([snapshotTask('b')])]);
    assert.ok(results.every(r => r.status === 200));
    const assignment = {id: 'schedule-a', taskId: 'a', date: '2026-09-22T00:00:00.000',
      createdAt: '2026-09-22T00:00:00.000Z', updatedAt: '2026-09-22T00:00:00.000Z', reminderHour: 0, reminderMinute: 0};
    const midnight = await (await save([], [assignment])).json();
    assert.equal(midnight.assignments[0].reminderHour, 0);
    assert.equal((await save([snapshotTask('a', {deletedAt: '2026-09-22T01:00:00.000Z', updatedAt: '2026-09-22T01:00:00.000Z'})])).status, 200);
    const stale = await (await save([snapshotTask('a', {updatedAt: '2026-09-23T00:00:00.000Z'})])).json();
    assert.equal(stale.tasks.length, 2);
    assert.ok(stale.tasks.find(t => t.id === 'a').deletedAt);
    assert.ok(stale.assignments[0].deletedAt);
    for (const tasks of [[snapshotTask('invalid', {createdAt: '2026-02-30T00:00:00Z'})], [snapshotTask('x'), snapshotTask('x')]]) {
      assert.equal((await save(tasks)).status, 400);
    }
    assert.equal((await save([], [{...assignment, id: 'orphan', taskId: 'missing'}])).status, 400);
    const finalData = await (await request(base, '/api/task-reminder/data', undefined, account.token)).json();
    assert.equal(finalData.tasks.length, 2);
  });
});

test('password changes revoke previous sessions and require the current password', async () => {
  await withServer(async (base) => {
    const credentials = {name: 'password-change', password: 'password-123'};
    const first = await (await request(base, '/api/auth/register', credentials)).json();
    const second = await (await request(base, '/api/auth/login', credentials)).json();
    assert.equal((await request(base, '/api/auth/update', {currentPassword: 'incorrect', newPassword: 'password-456'}, first.token)).status, 401);
    const changed = await request(base, '/api/auth/update', {currentPassword: credentials.password, newPassword: 'password-456'}, first.token);
    assert.equal(changed.status, 200);
    const current = await changed.json();
    for (const token of [first.token, second.token]) {
      assert.equal((await request(base, '/api/task-reminder/data', undefined, token)).status, 401);
    }
    assert.equal((await request(base, '/api/task-reminder/data', undefined, current.token)).status, 200);
    assert.equal((await request(base, '/api/auth/login', credentials)).status, 401);
    assert.equal((await request(base, '/api/auth/login', {...credentials, password: 'password-456'})).status, 200);
    const accounts = await readFile(path.join(process.env.DATA_DIR, 'accounts.json'), 'utf8');
    assert.ok(!accounts.includes(current.token));
    assert.ok(!accounts.includes('password-456'));
  });
});

test('malformed JSON and corrupt account storage fail closed without replacing data', async () => {
  await withServer(async (base) => {
    const malformed = await fetch(`${base}/api/auth/login`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{broken'});
    assert.equal(malformed.status, 400);
    const file = path.join(process.env.DATA_DIR, 'accounts.json');
    const original = await readFile(file);
    try {
      await writeFile(file, '{broken');
      const response = await request(base, '/api/auth/register', {name: 'must-not-reset', password: 'password-123'});
      assert.equal(response.status, 500);
      assert.equal(await readFile(file, 'utf8'), '{broken');
    } finally {
      await writeFile(file, original);
    }
  });
});

test('auth rate limit persists when the server is recreated and cannot be bypassed by path casing', async () => {
  await withServer(async (base) => {
    for (let index = 0; index < 40; index++) {
      assert.equal((await request(base, '/api/auth/login', {name: 'missing', password: 'password-123'})).status, 401);
    }
  });
  await withServer(async (base) => {
    const limiterFile = path.join(process.env.DATA_DIR, 'rate-limits.json');
    const before = await readFile(limiterFile, 'utf8');
    const response = await request(base, '/API/AUTH/LOGIN', {name: 'missing', password: 'password-123'});
    assert.equal(response.status, 429);
    assert.ok(Number(response.headers.get('retry-after')) > 0);
    assert.equal(await readFile(limiterFile, 'utf8'), before);

    const other = await request(base, '/api/auth/register', {name: 'different-user', password: 'password-123'});
    assert.equal(other.status, 201);
  });
});
