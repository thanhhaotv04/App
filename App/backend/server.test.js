import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createUpdateServer } from './server.js';

test('serves only a verified update manifest and APK', async (context) => {
  const releasesDir = await fs.mkdtemp(path.join(os.tmpdir(), 'esp32-update-'));
  context.after(() => fs.rm(releasesDir, { recursive: true, force: true }));
  const apk = Buffer.from('PK\u0003\u0004test-apk');
  const apkFile = 'esp32-navride-261001.1.apk';
  await fs.writeFile(path.join(releasesDir, apkFile), apk);
  await fs.writeFile(
    path.join(releasesDir, 'latest.json'),
    JSON.stringify({
      applicationId: 'com.thanhhao.esp32_monitor',
      versionName: '261001.1',
      versionCode: 26100101,
      apkFile,
      notes: 'Test update.',
      sizeBytes: apk.length,
      sha256: createHash('sha256').update(apk).digest('hex'),
    }),
  );

  const server = createUpdateServer({ releasesDir });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => new Promise((resolve) => server.close(resolve)));
  const { port } = server.address();
  const base = `http://127.0.0.1:${port}`;

  const health = await fetch(`${base}/api/health`);
  assert.equal(health.status, 200);
  const healthBody = await health.json();
  assert.equal(healthBody.ok, true);
  assert.equal(healthBody.service, 'esp32-navride-update');

  const latest = await fetch(`${base}/api/update/latest`);
  assert.equal(latest.status, 200);
  const metadata = await latest.json();
  assert.equal(metadata.versionCode, 26100101);
  assert.equal(metadata.apkUrl, `/releases/${apkFile}`);
  assert.equal('apkFile' in metadata, false);

  const download = await fetch(`${base}${metadata.apkUrl}`);
  assert.equal(download.status, 200);
  assert.deepEqual(Buffer.from(await download.arrayBuffer()), apk);

  const post = await fetch(`${base}/api/update/latest`, { method: 'POST' });
  assert.equal(post.status, 405);

  await fs.appendFile(path.join(releasesDir, apkFile), 'corrupt');
  assert.equal((await fetch(`${base}/api/update/latest`)).status, 503);
});
