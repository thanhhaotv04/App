import express from "express";
import fs from "fs/promises";
import path from "path";
import { randomBytes, randomUUID, scryptSync, timingSafeEqual } from "crypto";
import { fileURLToPath, pathToFileURL } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const port = Number(process.env.PORT || 3002);
const passwordMinLength = 8;
const maxNameLength = 80;
const maxTasks = 1000;
const maxAssignments = 5000;
const allowInsecurePasswordReset =
  process.env.ALLOW_INSECURE_PASSWORD_RESET === "1";
const allowedOrigins = (process.env.ALLOWED_ORIGINS || "")
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

const dataDir = process.env.DATA_DIR || path.join(__dirname, "server-data");
const accountsFile = path.join(dataDir, "accounts.json");
const taskFile = path.join(dataDir, "task-reminder.json");
const releasesDir = path.join(__dirname, "releases");
const updateManifest = path.join(releasesDir, "latest.json");

async function readJson(file, fallback) {
  try {
    return JSON.parse(await fs.readFile(file, "utf8"));
  } catch {
    return fallback;
  }
}

async function writeJson(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temp = `${file}.tmp`;
  await fs.writeFile(temp, JSON.stringify(value, null, 2), "utf8");
  await fs.rename(temp, file);
}

function normalizedName(value) {
  return String(value || "").normalize("NFC").trim();
}

function normalizedPassword(value) {
  return String(value || "");
}

function validateName(value) {
  const name = normalizedName(value);
  if (!name || name.length > maxNameLength) return null;
  return name;
}

function validatePassword(value) {
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
  const digest = scryptSync(String(password), salt, 32).toString("hex");
  return `${salt}:${digest}`;
}

function passwordMatches(password, stored) {
  const [salt, expectedHex] = String(stored || "").split(":");
  if (!salt || !expectedHex) return false;
  const actual = scryptSync(String(password), salt, 32);
  const expected = Buffer.from(expectedHex, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function authenticate(req, res) {
  const accounts = await readJson(accountsFile, []);
  const name = validateName(
    req.get("X-User-Name") ||
      req.body?.name ||
      req.body?.userName ||
      req.body?.username,
  );
  const password = normalizedPassword(
    req.get("X-Password") || req.body?.currentPassword || req.body?.password,
  );
  const account = findAccount(accounts, name);
  if (!account || !passwordMatches(password, account.passwordHash)) {
    res.status(401).json({
      error: "invalid_account",
      message: "Backend rejected this account. Sign in again or reset the password.",
    });
    return null;
  }
  return { account, accounts };
}

function securityHeaders(_req, res, next) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.setHeader("Cross-Origin-Resource-Policy", "same-site");
  next();
}

function cors(req, res, next) {
  const origin = req.get("Origin");
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type,X-User-Name,X-Password",
  );
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
}

function rateLimit({ windowMs, max }) {
  const hits = new Map();
  return (req, res, next) => {
    const key = `${req.ip}:${req.path}`;
    const now = Date.now();
    const entry = hits.get(key) || { count: 0, resetAt: now + windowMs };
    if (entry.resetAt <= now) {
      entry.count = 0;
      entry.resetAt = now + windowMs;
    }
    entry.count += 1;
    hits.set(key, entry);
    if (entry.count > max) {
      return res.status(429).json({
        error: "rate_limited",
        message: "Too many requests. Please wait and try again.",
      });
    }
    next();
  };
}

function validateTaskPayload(items) {
  if (!Array.isArray(items) || items.length > maxTasks) return null;
  return items.map((item) => {
    const value = item && typeof item === "object" ? item : {};
    return {
      id: String(value.id || "").slice(0, 120),
      title: String(value.title || "").slice(0, 200),
      note: String(value.note || "").slice(0, 2000),
      priority: String(value.priority || "normal").slice(0, 20),
      iconKind: String(value.iconKind || "study").slice(0, 20),
      estimateMinutes: Number(value.estimateMinutes) || 15,
      createdAt: String(value.createdAt || ""),
      updatedAt: String(value.updatedAt || ""),
    };
  });
}

function validateAssignmentPayload(items) {
  if (!Array.isArray(items) || items.length > maxAssignments) return null;
  return items.map((item) => {
    const value = item && typeof item === "object" ? item : {};
    return {
      id: String(value.id || "").slice(0, 120),
      taskId: String(value.taskId || "").slice(0, 120),
      date: String(value.date || ""),
      createdAt: String(value.createdAt || ""),
      updatedAt: String(value.updatedAt || ""),
      reminderHour: Number(value.reminderHour) || 8,
      reminderMinute: Number(value.reminderMinute) || 0,
      completedAt: value.completedAt ? String(value.completedAt) : null,
    };
  });
}

export function createApp() {
  const app = express();
  const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 40 });

  app.disable("x-powered-by");
  app.use(securityHeaders);
  app.use(cors);
  app.use(express.json({ limit: "1mb" }));
  app.use("/releases", express.static(releasesDir, { dotfiles: "deny" }));

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
    const accounts = await readJson(accountsFile, []);
    if (findAccount(accounts, name)) {
      return res.status(409).json({
        error: "account_exists",
        message: "This username is already registered.",
      });
    }
    accounts.push({
      id: randomUUID(),
      name,
      passwordHash: hashPassword(password),
      updatedAt: Date.now(),
    });
    await writeJson(accountsFile, accounts);
    res.status(201).json({ ok: true, name });
  });

  app.post("/api/auth/login", authLimiter, async (req, res) => {
    const accounts = await readJson(accountsFile, []);
    const account = findAccount(
      accounts,
      req.body.name || req.body.userName || req.body.username,
    );
    if (!account) {
      return res.status(404).json({
        error: "account_not_found",
        message: "Account not found. Please register first.",
      });
    }
    if (!passwordMatches(req.body.password, account.passwordHash)) {
      return res.status(401).json({
        error: "incorrect_password",
        message: "Incorrect password. Please try again.",
      });
    }
    res.json({ ok: true, name: account.name });
  });

  app.post("/api/auth/reset-password", authLimiter, async (req, res) => {
    if (!allowInsecurePasswordReset) {
      return res.status(403).json({
        error: "password_reset_disabled",
        message:
          "Password reset is disabled for release builds. Sign in and change your password from Account.",
      });
    }
    const accounts = await readJson(accountsFile, []);
    const account = findAccount(
      accounts,
      req.body.name || req.body.userName || req.body.username,
    );
    const password = validatePassword(req.body.newPassword || req.body.password);
    if (!account) {
      return res
        .status(404)
        .json({ error: "account_not_found", message: "Account not found." });
    }
    if (!password) {
      return res.status(400).json({
        error: "weak_password",
        message: `New password must have at least ${passwordMinLength} characters.`,
      });
    }
    account.passwordHash = hashPassword(password);
    account.updatedAt = Date.now();
    await writeJson(accountsFile, accounts);
    res.json({ ok: true, name: account.name });
  });

  app.post("/api/auth/update", authLimiter, async (req, res) => {
    const authenticated = await authenticate(req, res);
    if (!authenticated) return;
    const { account, accounts } = authenticated;
    const nextPassword = req.body.newPassword
      ? validatePassword(req.body.newPassword)
      : "";
    if (req.body.newPassword && !nextPassword) {
      return res.status(400).json({
        error: "weak_password",
        message: `New password must have at least ${passwordMinLength} characters.`,
      });
    }
    if (nextPassword) account.passwordHash = hashPassword(nextPassword);
    account.updatedAt = Date.now();
    await writeJson(accountsFile, accounts);
    res.json({ ok: true, name: account.name });
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
    const authenticated = await authenticate(req, res);
    if (!authenticated) return;
    const tasks = validateTaskPayload(req.body.tasks);
    const assignments = validateAssignmentPayload(req.body.assignments);
    if (!tasks || !assignments) {
      return res.status(400).json({
        error: "invalid_sync_payload",
        message: "Sync payload is invalid or too large.",
      });
    }
    const allData = await readJson(taskFile, {});
    allData[authenticated.account.id] = {
      tasks,
      assignments,
      updatedAt: Date.now(),
    };
    await writeJson(taskFile, allData);
    res.json({
      ok: true,
      tasks: tasks.length,
      assignments: assignments.length,
    });
  });

  app.get("/api/update/latest", async (_req, res) => {
    try {
      const manifest = await readJson(updateManifest, null);
      if (!manifest) throw new Error("missing manifest");
      const apkFile = path.basename(manifest.apkFile || "app-release.apk");
      await fs.access(path.join(releasesDir, apkFile));
      res.json({
        versionName: manifest.versionName || "1.0.0",
        versionCode: Number(manifest.versionCode) || 1,
        notes: manifest.notes || "",
        apkUrl: `/releases/${encodeURIComponent(apkFile)}`,
      });
    } catch {
      res.status(404).json({ error: "no_update_release_found" });
    }
  });

  return app;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  createApp().listen(port, "0.0.0.0", () => {
    console.log(`Task Reminder backend: http://0.0.0.0:${port}`);
  });
}
