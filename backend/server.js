import express from "express";
import fs from "fs/promises";
import path from "path";
import https from "node:https";
import {
  createHash,
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from "crypto";
import { fileURLToPath, pathToFileURL } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const port = Number(process.env.PORT || 3002);
const passwordMinLength = 8;
const maxNameLength = 80;
const maxTasks = 1000;
const maxAssignments = 5000;
const sessionTtlMs = 30 * 24 * 60 * 60 * 1000;
const maxSessionsPerAccount = 10;
const scryptOptions = { N: 2 ** 17, r: 8, p: 1, maxmem: 256 * 1024 * 1024 };
const allowedOrigins = (process.env.ALLOWED_ORIGINS || "")
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

const dataDir = process.env.DATA_DIR || path.join(__dirname, "server-data");
const accountsFile = path.join(dataDir, "accounts.json");
const taskFile = path.join(dataDir, "task-reminder.json");
const releasesDir = process.env.RELEASES_DIR || path.join(__dirname, "releases");
const updateManifest = path.join(releasesDir, "latest.json");
let writeQueue = Promise.resolve();
let releaseDigestCache = null;

async function readJson(file, fallback) {
  try {
    const value = JSON.parse(await fs.readFile(file, "utf8"));
    if ((Array.isArray(fallback) && !Array.isArray(value)) ||
        (fallback && !Array.isArray(fallback) && (!value || typeof value !== 'object' || Array.isArray(value)))) {
      throw new Error('Invalid stored data shape');
    }
    return value;
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }
}

async function writeJson(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temp, `${JSON.stringify(value, null, 2)}\n`, {encoding: "utf8", mode: 0o600, flush: true});
    await fs.rename(temp, file);
  } catch (error) {
    await fs.rm(temp, { force: true });
    throw error;
  }
}

async function withWriteLock(operation) {
  // ponytail: one backend process per DATA_DIR; use a database before replicas.
  const pending = writeQueue.catch(() => {}).then(operation);
  writeQueue = pending.catch(() => {});
  return pending;
}

async function apkIntegrity(apkPath) {
  const stat = await fs.stat(apkPath);
  if (
    releaseDigestCache?.apkPath === apkPath &&
    releaseDigestCache.mtimeMs === stat.mtimeMs &&
    releaseDigestCache.size === stat.size
  ) return releaseDigestCache;
  const sha256 = createHash("sha256")
    .update(await fs.readFile(apkPath))
    .digest("hex");
  releaseDigestCache = {
    apkPath,
    mtimeMs: stat.mtimeMs,
    size: stat.size,
    sha256,
  };
  return releaseDigestCache;
}

function normalizedName(value) {
  return String(value || "").normalize("NFC").trim();
}

function normalizedPassword(value) {
  return String(value || "");
}

function validateName(value) {
  if (typeof value !== 'string') return null;
  const name = normalizedName(value);
  if (!name || name.length > maxNameLength || /[\x00-\x1f\x7f]/.test(name)) return null;
  return name;
}

function validatePassword(value) {
  if (typeof value !== 'string') return null;
  const password = normalizedPassword(value);
  if (password.length < passwordMinLength || password.length > 256) return null;
  return password;
}

function findAccount(accounts, value) {
  const key = normalizedName(value).toLocaleLowerCase("vi");
  return accounts.find(
    (item) => normalizedName(item.name).toLocaleLowerCase("vi") === key,
  );
}

function hashPassword(password, salt = randomBytes(16).toString("hex")) {
  const digest = scryptSync(String(password), salt, 32, scryptOptions).toString("hex");
  return `scrypt:17:8:1:${salt}:${digest}`;
}

function passwordMatches(password, stored) {
  if (typeof password !== 'string' || password.length > 256) return false;
  const parts = String(stored || "").split(":");
  const modern = parts.length === 6 && parts[0] === 'scrypt' &&
    parts[1] === '17' && parts[2] === '8' && parts[3] === '1';
  const legacy = parts.length === 2;
  if (!modern && !legacy) return false;
  const salt = modern ? parts[4] : parts[0];
  const expectedHex = modern ? parts[5] : parts[1];
  if (!salt || !/^[a-f0-9]{64}$/i.test(expectedHex || "")) return false;
  try {
    const actual = modern
      ? scryptSync(String(password), salt, 32, scryptOptions)
      : scryptSync(String(password), salt, 32);
    const expected = Buffer.from(expectedHex, "hex");
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

function passwordNeedsRehash(stored) {
  return !String(stored || '').startsWith('scrypt:17:8:1:');
}

// Missing accounts still perform the same password work as existing accounts,
// reducing username discovery through response timing.
const unavailableAccountHash = hashPassword(randomBytes(32).toString('hex'));

function tokenHash(token) {
  return createHash("sha256").update(String(token || "")).digest("hex");
}

function activeSessions(account) {
  const now = Date.now();
  return (Array.isArray(account.sessions) ? account.sessions : []).filter(
    (session) =>
      session &&
      /^[a-f0-9]{64}$/i.test(String(session.hash || "")) &&
      Number(session.expiresAt) > now,
  );
}

function issueSession(account) {
  const token = randomBytes(32).toString("base64url");
  account.sessions = [
    ...activeSessions(account),
    { hash: tokenHash(token), expiresAt: Date.now() + sessionTtlMs },
  ].slice(-maxSessionsPerAccount);
  account.updatedAt = Date.now();
  return token;
}

async function authenticate(req, res) {
  const accounts = await readJson(accountsFile, []);
  const authorization = String(req.get("Authorization") || "");
  const bearer = /^Bearer [A-Za-z0-9_-]{43}$/.test(authorization) ? authorization.slice(7) : '';
  if (bearer) {
    const hash = tokenHash(bearer);
    const account = accounts.find((item) =>
      activeSessions(item).some((session) => session.hash === hash),
    );
    if (account) return { account, accounts, tokenHash: hash };
  }
  res.status(401).json({
    error: "invalid_session",
    message: "Your backend session expired. Sign in again, then retry.",
  });
  return null;
}

function securityHeaders(req, res, next) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.setHeader("Cross-Origin-Resource-Policy", "same-site");
  res.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
  if (/^\/api(?:\/|$)/i.test(req.path)) res.setHeader("Cache-Control", "no-store");
  if (req.secure) res.setHeader('Strict-Transport-Security', 'max-age=31536000');
  next();
}

function cors(req, res, next) {
  const origin = req.get("Origin");
  if (origin && !allowedOrigins.includes(origin)) {
    return res.status(403).json({ error: "origin_not_allowed" });
  }
  if (origin) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization,Content-Type",
  );
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
}

const volatileRateLimits = new Map();

function rateLimit({ windowMs, max, scope, keyFor = (req) => req.ip, persistent = true }) {
  const file = path.join(dataDir, "rate-limits.json");
  return async (req, res, next) => {
    const identity = keyFor(req);
    const key = `${scope}:${identity}`;
    if (!persistent) {
      const now = Date.now();
      const value = volatileRateLimits.get(key);
      if (!value || value.resetAt <= now) {
        volatileRateLimits.set(key, {count: 1, resetAt: now + windowMs});
        return next();
      }
      if (value.count >= max) {
        res.setHeader("Retry-After", Math.max(1, Math.ceil((value.resetAt - now) / 1000)));
        return res.status(429).json({error: "rate_limited", message: "Too many requests. Please wait and try again."});
      }
      value.count += 1;
      return next();
    }
    const entry = await withWriteLock(async () => {
      const now = Date.now();
      const hits = await readJson(file, {});
      var changed = false;
      for (const key of Object.keys(hits)) {
        if (hits[key].resetAt <= now) {
          delete hits[key];
          changed = true;
        }
      }
      if (!hits[key] && Object.keys(hits).length >= 10000) {
        return { count: max, resetAt: now + windowMs, blocked: true };
      }
      const value = hits[key] || { count: 0, resetAt: now + windowMs };
      if (value.count >= max) {
        if (changed) await writeJson(file, hits);
        return {...value, blocked: true};
      }
      value.count = Math.min(max + 1, value.count + 1);
      hits[key] = value;
      await writeJson(file, hits);
      return value;
    });
    if (entry.blocked || entry.count > max) {
      res.setHeader("Retry-After", Math.max(1, Math.ceil((entry.resetAt - Date.now()) / 1000)));
      return res.status(429).json({error: "rate_limited",
        message: "Too many requests. Please wait and try again."});
    }
    next();
  };
}

function validText(value, max, { required = false } = {}) {
  if (typeof value !== "string") return required ? null : "";
  const text = value.normalize("NFC").trim();
  if ((required && !text) || text.length > max) return null;
  return text;
}

function validIsoDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})?$/.test(value)) return null;
  const [year, month, day] = value.slice(0, 10).split('-').map(Number);
  if (month < 1 || month > 12 || day < 1 || day > new Date(Date.UTC(year, month, 0)).getUTCDate()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : value;
}

function validInteger(value, min, max) {
  const number = value;
  return Number.isInteger(number) && number >= min && number <= max
    ? number
    : null;
}

function validateTaskPayload(items) {
  if (!Array.isArray(items) || items.length > maxTasks) return null;
  const result = [];
  const ids = new Set();
  for (const item of items) {
    if (!item || typeof item !== "object") return null;
    const id = validText(item.id, 120, { required: true });
    const title = validText(item.title, 200, { required: true });
    const note = validText(item.note ?? "", 2000);
    const createdAt = validIsoDate(item.createdAt);
    const updatedAt = validIsoDate(item.updatedAt);
    const deletedAt = item.deletedAt == null ? null : validIsoDate(item.deletedAt);
    const estimateMinutes = validInteger(item.estimateMinutes ?? 15, 5, 240);
    if (
      !id ||
      !title ||
      note == null ||
      !createdAt ||
      !updatedAt ||
      (item.deletedAt != null && !deletedAt) ||
      estimateMinutes == null
    ) return null;
    if (ids.has(id)) return null;
    ids.add(id);
    result.push({
      id,
      title,
      note,
      priority: ["none", "low", "normal", "high"].includes(item.priority)
        ? item.priority
        : "normal",
      iconKind: ["study", "fitness", "health", "laptop", "smile", "travel"].includes(item.iconKind)
        ? item.iconKind
        : "study",
      estimateMinutes,
      createdAt,
      updatedAt,
      deletedAt,
    });
  }
  return result;
}

function validateAssignmentPayload(items) {
  if (!Array.isArray(items) || items.length > maxAssignments) return null;
  const result = [];
  const ids = new Set();
  for (const item of items) {
    if (!item || typeof item !== "object") return null;
    const id = validText(item.id, 120, { required: true });
    const taskId = validText(item.taskId, 120, { required: true });
    const date = validIsoDate(item.date);
    const createdAt = validIsoDate(item.createdAt);
    const updatedAt = validIsoDate(item.updatedAt);
    const completedAt = item.completedAt == null ? null : validIsoDate(item.completedAt);
    const deletedAt = item.deletedAt == null ? null : validIsoDate(item.deletedAt);
    const reminderHour = validInteger(item.reminderHour ?? 8, 0, 23);
    const reminderMinute = validInteger(item.reminderMinute ?? 0, 0, 59);
    if (
      !id ||
      !taskId ||
      !date ||
      !createdAt ||
      !updatedAt ||
      (item.completedAt != null && !completedAt) ||
      (item.deletedAt != null && !deletedAt) ||
      reminderHour == null ||
      reminderMinute == null
    ) return null;
    if (ids.has(id)) return null;
    ids.add(id);
    result.push({
      id,
      taskId,
      date,
      createdAt,
      updatedAt,
      reminderHour,
      reminderMinute,
      completedAt,
      deletedAt,
    });
  }
  return result;
}

function mergeRecords(previous, incoming, permanentDeletion = false) {
  const byId = new Map(previous.map(item => [item.id, item]));
  for (const item of incoming) {
    const old = byId.get(item.id);
    if (permanentDeletion && old?.deletedAt && !item.deletedAt) continue;
    if (!old || (permanentDeletion && !old.deletedAt && item.deletedAt) ||
        Date.parse(item.updatedAt) > Date.parse(old.updatedAt) ||
        (Date.parse(item.updatedAt) === Date.parse(old.updatedAt) && item.deletedAt)) {
      byId.set(item.id, item);
    }
  }
  return [...byId.values()];
}

export function createApp() {
  const app = express();
  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 40,
    scope: 'auth',
    keyFor: (req) => {
      const name = normalizedName(req.body?.name || req.body?.userName || req.body?.username)
        .toLocaleLowerCase('vi');
      const accountKey = createHash('sha256').update(name || 'unknown').digest('hex').slice(0, 24);
      return `${req.ip}:${accountKey}`;
    },
  });
  const apiLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 300,
    scope: 'api',
    persistent: false,
  });

  app.disable("x-powered-by");
  app.set("trust proxy", false);
  app.use(securityHeaders);
  app.use(cors);
  app.use("/api/", apiLimiter);
  app.use(express.json({ limit: "1mb", strict: true }));
  app.use('/api/', (req, res, next) => {
    if (req.method === 'POST' && (!req.body || Array.isArray(req.body))) {
      return res.status(400).json({error: 'invalid_request', message: 'A JSON object is required.'});
    }
    next();
  });
  app.use(
    "/releases",
    express.static(releasesDir, {
      dotfiles: "deny",
      fallthrough: false,
      index: false,
      maxAge: 0,
    }),
  );

  app.get("/api/health", (_req, res) => {
    res.json({ ok: true, service: "task-reminder-backend" });
  });

  app.post("/api/auth/register", authLimiter, async (req, res) => {
    const name = validateName(
      req.body.name || req.body.userName || req.body.username,
    );
    const password = validatePassword(req.body.password);
    if (!name || !password) {
      return res.status(400).json({
        error: "invalid_account",
        message: `Enter a name and a password with at least ${passwordMinLength} characters.`,
      });
    }
    return withWriteLock(async () => {
      const accounts = await readJson(accountsFile, []);
      if (findAccount(accounts, name)) {
        return res.status(409).json({
          error: "account_unavailable",
          message: "This name cannot be registered.",
        });
      }
      const account = {
        id: randomUUID(),
        name,
        passwordHash: hashPassword(password),
        sessions: [],
        updatedAt: Date.now(),
      };
      const token = issueSession(account);
      accounts.push(account);
      await writeJson(accountsFile, accounts);
      res.status(201).json({ ok: true, name, token });
    });
  });

  app.post("/api/auth/login", authLimiter, async (req, res) => {
    return withWriteLock(async () => {
      const accounts = await readJson(accountsFile, []);
      const account = findAccount(
        accounts,
        req.body.name || req.body.userName || req.body.username,
      );
      const passwordMatchesAccount = passwordMatches(
        req.body.password,
        account?.passwordHash ?? unavailableAccountHash,
      );
      if (!account || !passwordMatchesAccount) {
        return res.status(401).json({
          error: "invalid_credentials",
          message: "Name or password is incorrect.",
        });
      }
      if (passwordNeedsRehash(account.passwordHash)) {
        account.passwordHash = hashPassword(req.body.password);
      }
      const token = issueSession(account);
      await writeJson(accountsFile, accounts);
      res.json({ ok: true, name: account.name, token });
    });
  });

  app.post("/api/auth/reset-password", authLimiter, (_req, res) => {
    res.status(403).json({error: "password_reset_disabled",
      message: "Sign in and change your password from Account."});
  });

  app.post("/api/auth/update", authLimiter, async (req, res) => {
    return withWriteLock(async () => {
      const authenticated = await authenticate(req, res);
      if (!authenticated) return;
      const nextPassword = validatePassword(req.body.newPassword);
      if (!passwordMatches(req.body.currentPassword, authenticated.account.passwordHash)) {
        return res.status(401).json({error: 'incorrect_password', message: 'Current password is incorrect.'});
      }
      if (!nextPassword) {
        return res.status(400).json({
          error: "weak_password",
          message: `New password must have at least ${passwordMinLength} characters.`,
        });
      }
      authenticated.account.passwordHash = hashPassword(nextPassword);
      authenticated.account.sessions = [];
      const token = issueSession(authenticated.account);
      await writeJson(accountsFile, authenticated.accounts);
      res.json({ ok: true, name: authenticated.account.name, token });
    });
  });

  app.post("/api/auth/logout", async (req, res) => {
    return withWriteLock(async () => {
      const authenticated = await authenticate(req, res);
      if (!authenticated) return;
      authenticated.account.sessions = activeSessions(authenticated.account).filter(
        (session) => session.hash !== authenticated.tokenHash,
      );
      authenticated.account.updatedAt = Date.now();
      await writeJson(accountsFile, authenticated.accounts);
      res.json({ ok: true });
    });
  });

  app.get("/api/task-reminder/data", async (req, res) => {
    const authenticated = await authenticate(req, res);
    if (!authenticated) return;
    const allData = await readJson(taskFile, {});
    res.json(
      allData[authenticated.account.id] || {
        tasks: [],
        assignments: [],
      },
    );
  });

  app.post("/api/task-reminder/data", async (req, res) => {
    const tasks = validateTaskPayload(req.body.tasks);
    const assignments = validateAssignmentPayload(req.body.assignments);
    if (!tasks || !assignments) {
      return res.status(400).json({
        error: "invalid_sync_payload",
        message: "Sync payload is invalid or too large.",
      });
    }
    return withWriteLock(async () => {
      const authenticated = await authenticate(req, res);
      if (!authenticated) return;
      const allData = await readJson(taskFile, {});
      const previous = allData[authenticated.account.id] || {tasks: [], assignments: []};
      const mergedTasks = mergeRecords(previous.tasks, tasks, true);
      const mergedAssignments = mergeRecords(previous.assignments, assignments);
      const parents = new Map(mergedTasks.map(item => [item.id, item]));
      if (mergedTasks.length > maxTasks || mergedAssignments.length > maxAssignments ||
          mergedAssignments.some(item => !parents.has(item.taskId))) {
        return res.status(400).json({error: 'invalid_sync_payload', message: 'Sync exceeds the record limit or references a missing task.'});
      }
      for (const item of mergedAssignments) {
        const parent = parents.get(item.taskId);
        if (parent.deletedAt && !item.deletedAt) {
          item.deletedAt = parent.deletedAt;
          item.updatedAt = parent.updatedAt;
        }
      }
      allData[authenticated.account.id] = {
        tasks: mergedTasks,
        assignments: mergedAssignments,
        updatedAt: Date.now(),
      };
      await writeJson(taskFile, allData);
      res.json({
        ok: true,
        ...allData[authenticated.account.id],
      });
    });
  });

  app.get("/api/update/latest", async (_req, res) => {
    try {
      const manifest = await readJson(updateManifest, null);
      if (!manifest) throw new Error("missing manifest");
      const apkFile = path.basename(manifest.apkFile || "app-release.apk");
      const apkPath = path.join(releasesDir, apkFile);
      const integrity = await apkIntegrity(apkPath);
      res.json({
        versionName: manifest.versionName || "1.0.0",
        versionCode: Number(manifest.versionCode) || 1,
        notes: manifest.notes || "",
        apkUrl: `/releases/${encodeURIComponent(apkFile)}`,
        sha256: integrity.sha256,
        size: integrity.size,
      });
    } catch {
      res.status(404).json({ error: "no_update_release_found" });
    }
  });

  app.use((error, _req, res, _next) => {
    const status = Number(error?.status || error?.statusCode) || 500;
    console.error("Task Reminder backend error", {
      name: error?.name,
      status,
      code: error?.code,
    });
    res.status(status >= 400 && status < 600 ? status : 500).json({
      error: status === 413 ? "payload_too_large" : "internal_error",
      message:
        status === 413
          ? "Request payload is too large."
          : "The backend could not complete this request.",
    });
  });

  return app;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const cert = process.env.TLS_CERT_FILE;
  const key = process.env.TLS_KEY_FILE;
  if (Boolean(cert) !== Boolean(key)) throw new Error('Configure both TLS_CERT_FILE and TLS_KEY_FILE.');
  if (process.env.NODE_ENV === 'production' && !cert && process.env.TLS_TERMINATED_BY_PROXY !== '1') {
    throw new Error('Production requires TLS or TLS_TERMINATED_BY_PROXY=1 behind an HTTPS proxy.');
  }
  const app = createApp();
  const server = cert ? https.createServer({cert: await fs.readFile(cert), key: await fs.readFile(key)}, app) : app;
  server.listen(port, process.env.HOST || '127.0.0.1', () => {
    console.log(`Task Reminder backend listening on port ${port} (${cert ? 'HTTPS' : 'HTTP'})`);
  });
}
