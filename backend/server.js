import express from "express";
import fs from "fs/promises";
import path from "path";
import { randomBytes, randomUUID, scryptSync, timingSafeEqual } from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const port = Number(process.env.PORT || 3002);

const dataDir = path.join(__dirname, "server-data");
const accountsFile = path.join(dataDir, "accounts.json");
const moneyFile = path.join(dataDir, "money-manager.json");
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
  return (
    actual.length === expected.length && timingSafeEqual(actual, expected)
  );
}

async function authenticate(req, res) {
  const accounts = await readJson(accountsFile, []);
  const name =
    req.get("X-User-Name") ||
    req.body?.name ||
    req.body?.userName ||
    req.body?.username;
  const password =
    req.get("X-Password") || req.body?.currentPassword || req.body?.password;
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

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type,X-User-Name,X-Password",
  );
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});
app.use(express.json({ limit: "5mb" }));
app.use("/releases", express.static(releasesDir));

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "money-manager-backend" });
});

app.post("/api/auth/register", async (req, res) => {
  const name = normalizedName(
    req.body.name || req.body.userName || req.body.username,
  );
  const password = String(req.body.password || "");
  if (!name || password.length < 4) {
    return res.status(400).json({
      error: "invalid_account",
      message: "Enter a name and a password with at least 4 characters.",
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

app.post("/api/auth/login", async (req, res) => {
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

app.post("/api/auth/reset-password", async (req, res) => {
  const accounts = await readJson(accountsFile, []);
  const account = findAccount(
    accounts,
    req.body.name || req.body.userName || req.body.username,
  );
  const password = String(req.body.newPassword || req.body.password || "");
  if (!account) {
    return res
      .status(404)
      .json({ error: "account_not_found", message: "Account not found." });
  }
  if (password.length < 4) {
    return res.status(400).json({
      error: "weak_password",
      message: "New password must have at least 4 characters.",
    });
  }
  account.passwordHash = hashPassword(password);
  account.updatedAt = Date.now();
  await writeJson(accountsFile, accounts);
  res.json({ ok: true, name: account.name });
});

app.post("/api/auth/update", async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const { account, accounts } = authenticated;
  const nextPassword = String(req.body.newPassword || "");
  if (nextPassword && nextPassword.length < 4) {
    return res.status(400).json({
      error: "weak_password",
      message: "New password must have at least 4 characters.",
    });
  }
  if (nextPassword) account.passwordHash = hashPassword(nextPassword);
  account.updatedAt = Date.now();
  await writeJson(accountsFile, accounts);
  res.json({ ok: true, name: account.name });
});

app.get("/api/money-manager/data", async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const allData = await readJson(moneyFile, {});
  res.json(
    allData[authenticated.account.id] || {
      transactions: [],
      recurring: [],
    },
  );
});

app.post("/api/money-manager/data", async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const transactions = Array.isArray(req.body.transactions)
    ? req.body.transactions
    : [];
  const recurring = Array.isArray(req.body.recurring)
    ? req.body.recurring
    : [];
  const allData = await readJson(moneyFile, {});
  allData[authenticated.account.id] = {
    transactions,
    recurring,
    updatedAt: Date.now(),
  };
  await writeJson(moneyFile, allData);
  res.json({ ok: true, transactions: transactions.length, recurring: recurring.length });
});

app.get("/api/update/latest", async (_req, res) => {
  try {
    const manifest = await readJson(updateManifest, null);
    if (!manifest) throw new Error("missing manifest");
    const apkFile = path.basename(manifest.apkFile || "app-release.apk");
    await fs.access(path.join(releasesDir, apkFile));
    res.json({
      versionName: manifest.versionName || "1.0.8",
      versionCode: Number(manifest.versionCode) || 9,
      notes: manifest.notes || "",
      apkUrl: `/releases/${encodeURIComponent(apkFile)}`,
    });
  } catch {
    res.status(404).json({ error: "no_update_release_found" });
  }
});

app.listen(port, "0.0.0.0", () => {
  console.log(`Money Manager backend: http://0.0.0.0:${port}`);
});
