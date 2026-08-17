import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

process.env.DATA_DIR = await mkdtemp(path.join(tmpdir(), "task-reminder-"));
process.env.ALLOWED_ORIGINS = "http://allowed.example";
process.env.ALLOW_INSECURE_PASSWORD_RESET = "0";

const { createApp } = await import("./server.js");

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

    const rejected = await fetch(`${baseUrl}/api/health`, {
      headers: { Origin: "http://evil.example" },
    });
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

    const authHeaders = {
      ...headers,
      "X-User-Name": credentials.name,
      "X-Password": credentials.password,
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
        tasks: [{ id: "task-1", title: "Task", note: "<b>note</b>" }],
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
  });
});
