import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const defaultReleasesDir = path.join(directory, 'releases');
const maxApkBytes = 200 * 1024 * 1024;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function sha256(file) {
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(file)) digest.update(chunk);
  return digest.digest('hex');
}

async function publishedRelease(releasesDir) {
  let manifest;
  try {
    manifest = JSON.parse(
      await fs.readFile(path.join(releasesDir, 'latest.json'), 'utf8'),
    );
  } catch (error) {
    if (error.code === 'ENOENT') throw new HttpError(404, 'Chưa có bản cập nhật.');
    if (error instanceof SyntaxError) {
      throw new HttpError(503, 'Thông tin bản cập nhật chưa sẵn sàng.');
    }
    throw error;
  }

  if (
    manifest.applicationId !== 'com.thanhhao.esp32_navride' ||
    typeof manifest.apkFile !== 'string' ||
    !/^[A-Za-z0-9._-]+\.apk$/.test(manifest.apkFile) ||
    path.basename(manifest.apkFile) !== manifest.apkFile ||
    typeof manifest.versionName !== 'string' ||
    !/^\d{6}\.\d+$/.test(manifest.versionName) ||
    !Number.isSafeInteger(manifest.versionCode) ||
    manifest.versionCode <= 0 ||
    typeof manifest.notes !== 'string' ||
    manifest.notes.length > 4000 ||
    !Number.isSafeInteger(manifest.sizeBytes) ||
    manifest.sizeBytes <= 0 ||
    manifest.sizeBytes > maxApkBytes ||
    typeof manifest.sha256 !== 'string' ||
    !/^[a-f0-9]{64}$/.test(manifest.sha256)
  ) {
    throw new HttpError(503, 'Thông tin bản cập nhật chưa sẵn sàng.');
  }

  const apkPath = path.join(releasesDir, manifest.apkFile);
  let stat;
  try {
    stat = await fs.stat(apkPath);
  } catch (error) {
    if (error.code === 'ENOENT') throw new HttpError(404, 'Chưa có bản cập nhật.');
    throw error;
  }
  if (!stat.isFile() || stat.size !== manifest.sizeBytes) {
    throw new HttpError(503, 'APK đang được chuẩn bị.');
  }
  if ((await sha256(apkPath)) !== manifest.sha256) {
    throw new HttpError(503, 'APK không vượt qua kiểm tra toàn vẹn.');
  }
  return { manifest, apkPath };
}

function sendJson(response, status, value, headOnly = false) {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(headOnly ? undefined : body);
}

export function createUpdateServer({ releasesDir = defaultReleasesDir } = {}) {
  return http.createServer((request, response) => {
    void (async () => {
      const method = request.method ?? 'GET';
      const headOnly = method === 'HEAD';
      if (method !== 'GET' && !headOnly) {
        response.writeHead(405, { Allow: 'GET, HEAD' });
        response.end();
        return;
      }

      const url = new URL(request.url ?? '/', 'http://localhost');
      if (url.search || url.hash) throw new HttpError(404, 'Không tìm thấy.');
      if (url.pathname === '/api/health') {
        sendJson(response, 200, { ok: true, service: 'esp32-navride-update' }, headOnly);
        return;
      }

      const { manifest, apkPath } = await publishedRelease(releasesDir);
      if (url.pathname === '/api/update/latest') {
        const { apkFile, ...metadata } = manifest;
        sendJson(
          response,
          200,
          { ...metadata, apkUrl: `/releases/${apkFile}` },
          headOnly,
        );
        return;
      }
      if (url.pathname !== `/releases/${manifest.apkFile}`) {
        throw new HttpError(404, 'Không tìm thấy.');
      }

      response.writeHead(200, {
        'Content-Type': 'application/vnd.android.package-archive',
        'Content-Length': manifest.sizeBytes,
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      });
      if (headOnly) {
        response.end();
      } else {
        createReadStream(apkPath).pipe(response);
      }
    })().catch((error) => {
      if (response.headersSent) {
        response.destroy();
        return;
      }
      const status = error instanceof HttpError ? error.status : 500;
      if (status === 500) console.error('Update server error:', error);
      sendJson(response, status, {
        message: error instanceof HttpError ? error.message : 'Lỗi máy chủ.',
      });
    });
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT phải nằm trong khoảng 1-65535.');
  }
  createUpdateServer().listen(port, '0.0.0.0', () => {
    console.log(`ESP32-NavRide update server: http://0.0.0.0:${port}`);
  });
}
