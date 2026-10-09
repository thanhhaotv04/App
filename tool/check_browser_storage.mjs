// node tool/check_browser_storage.mjs <probe-origin> <playwright-index.mjs>
// Uses a fresh browser context and synthetic accounts only.
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { chromium } = await import(pathToFileURL(process.argv[3]).href);
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext();
  const a = await context.newPage(), b = await context.newPage();
  await Promise.all([a.goto(process.argv[2]), b.goto(process.argv[2])]);
  await Promise.all([a, b].map(page => page.waitForFunction(() => typeof globalThis.moneyManagerProbe === 'function')));
  const call = (page, command) => page.evaluate(input => globalThis.moneyManagerProbe(JSON.stringify(input)), command);
  const alice = { name: 'alice', id: 'alice-id', token: 'alice-token', backendUrl: 'https://server.example:3002' };
  await call(a, { op: 'login', session: alice });
  await Promise.all([call(a, { op: 'open' }), call(b, { op: 'open' })]);
  await Promise.all(Array.from({ length: 20 }, (_, i) => call(i % 2 ? a : b, { op: 'add', id: `tab-${i}` })));
  assert.equal(JSON.parse(await call(a, { op: 'read' })).length, 20);
  await call(a, { op: 'remove', id: 'tab-0' });
  await call(b, { op: 'add', id: 'after-delete' });
  const ids = JSON.parse(await call(a, { op: 'read' }));
  assert.equal(ids.length, 20); assert.ok(!ids.includes('tab-0'));
  await call(b, { op: 'login', session: { ...alice, name: 'bob', id: 'bob-id', token: 'bob-token' } });
  assert.equal(await call(a, { op: 'guard' }), 'blocked');
  await call(b, { op: 'open' });
  assert.deepEqual(JSON.parse(await call(b, { op: 'read' })), []);
  await call(b, { op: 'login', session: { ...alice, id: 'replacement-alice-id' } });
  await call(b, { op: 'open' });
  assert.deepEqual(JSON.parse(await call(b, { op: 'read' })), []);
  await call(a, { op: 'login', session: alice });
  await a.reload();
  await a.waitForFunction(() => typeof globalThis.moneyManagerProbe === 'function');
  await call(a, { op: 'open' });
  assert.equal(JSON.parse(await call(a, { op: 'read' })).length, 20);
  await call(a, { op: 'bulk' });
  await a.reload();
  await a.waitForFunction(() => typeof globalThis.moneyManagerProbe === 'function');
  await call(a, { op: 'open' });
  assert.equal(JSON.parse(await call(a, { op: 'read' })).length, 2420);
  console.log('PASS: two browser tabs preserve concurrent writes/deletion, block stale account, isolate replacement ID, and retain over 6 MB of financial data after reload.');
} finally { await browser.close(); }
