import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const releasesDir = path.join(directory, 'releases');
const [source, versionName, versionCodeText, notes = 'Cập nhật ESP32-NavRide.'] =
  process.argv.slice(2);
const versionCode = Number(versionCodeText);

if (!source || !/^\d{6}\.\d+$/.test(versionName ?? '')) {
  throw new Error(
    'Dùng: node backend/publish.js <apk> <YYMMDD.N> <versionCode> [ghi chú]',
  );
}
if (!Number.isSafeInteger(versionCode) || versionCode <= 0) {
  throw new Error('versionCode phải là số nguyên dương.');
}
if (notes.length > 4000) throw new Error('Ghi chú tối đa 4000 ký tự.');

await fs.mkdir(releasesDir, { recursive: true });
const apkFile = `esp32-navride-${versionName}.apk`;
const target = path.join(releasesDir, apkFile);
const temporaryApk = `${target}.tmp`;
await fs.copyFile(path.resolve(source), temporaryApk);
const stat = await fs.stat(temporaryApk);
if (stat.size <= 0 || stat.size > 200 * 1024 * 1024) {
  await fs.rm(temporaryApk, { force: true });
  throw new Error('APK phải có dung lượng từ 1 byte đến 200 MB.');
}
const digest = createHash('sha256');
for await (const chunk of createReadStream(temporaryApk)) digest.update(chunk);
const manifest = {
  applicationId: 'com.thanhhao.esp32_monitor',
  versionName,
  versionCode,
  apkFile,
  notes,
  sizeBytes: stat.size,
  sha256: digest.digest('hex'),
};
const temporaryManifest = path.join(releasesDir, 'latest.json.tmp');
await fs.writeFile(temporaryManifest, `${JSON.stringify(manifest, null, 2)}\n`, {
  mode: 0o644,
});
await fs.rename(temporaryApk, target);
await fs.rename(temporaryManifest, path.join(releasesDir, 'latest.json'));
console.log(JSON.stringify(manifest, null, 2));
