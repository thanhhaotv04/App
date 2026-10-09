import express from "express";
import multer from "multer";
import path from "path";
import fs from "fs/promises";
import { createHash, randomBytes, randomUUID, scryptSync, timingSafeEqual } from "crypto";
import https from "https";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const preferredPort = Number(process.env.PORT || 3000);

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "server-data");
const CHECKINS_FILE = path.join(DATA_DIR, "checkins.json");
const ACCOUNTS_FILE = path.join(DATA_DIR, "accounts.json");
const ALBUMS_FILE = path.join(DATA_DIR, "albums.json");
const PHOTO_ROOT = process.env.PHOTO_ROOT || path.join(__dirname, "user", "Picture");
const LEGACY_CHECKINS_KEY = "__legacy";
const LEGACY_OWNER_KEY = "__legacyOwnerId";
const RELEASES_DIR = path.join(__dirname, "releases");
const UPDATE_MANIFEST = path.join(RELEASES_DIR, "latest.json");
const MAX_PHOTO_BYTES = 12 * 1024 * 1024;
const MAX_ACCOUNT_PHOTO_BYTES = Number(process.env.MAX_ACCOUNT_PHOTO_BYTES || 500 * 1024 * 1024);
const SESSION_TTL_MS = Number(process.env.SESSION_TTL_MS || 30 * 24 * 60 * 60 * 1000);
const TLS_CERT_FILE = String(process.env.TLS_CERT_FILE || "");
const TLS_KEY_FILE = String(process.env.TLS_KEY_FILE || "");
const UPLOAD = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_PHOTO_BYTES, files: 24, fields: 64 },
});
const configuredOrigins = String(process.env.CORS_ORIGINS || "http://localhost:8080,http://127.0.0.1:8080")
  .split(",").map((value) => value.trim()).filter(Boolean);

const asyncRoute = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

const ensureDir = async (dir) => {
  await fs.mkdir(dir, { recursive: true });
};

const cleanSegment = (s) =>
  String(s || "")
    .normalize("NFC")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_")
    .trim() || "Unknown";

function safeSegment(value) {
  const segment = cleanSegment(value);
  return /^\.+$/.test(segment) ? "Unknown" : segment;
}

function assertInside(root, target) {
  const absoluteRoot = path.resolve(root);
  const absoluteTarget = path.resolve(target);
  if (absoluteTarget !== absoluteRoot && !absoluteTarget.startsWith(`${absoluteRoot}${path.sep}`)) {
    const error = new Error("invalid_storage_path");
    error.statusCode = 400;
    throw error;
  }
  return absoluteTarget;
}

const safeFileName = (name) =>
  String(name || "photo")
    .normalize("NFC")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_")
    .trim() || `photo-${Date.now()}`;

function parseTags(value) {
  if (Array.isArray(value)) return value.map((item) => String(item).trim()).filter(Boolean);
  if (!value) return [];
  try {
    const parsed = JSON.parse(value);
    if (Array.isArray(parsed)) return parsed.map((item) => String(item).trim()).filter(Boolean);
  } catch {
    // Fall through to comma-separated tags.
  }
  return String(value).split(",").map((item) => item.trim()).filter(Boolean);
}

function parsePhotoAssets(value) {
  if (!value) return [];
  try {
    const parsed = typeof value === "string" ? JSON.parse(value) : value;
    if (!Array.isArray(parsed)) return [];
    return parsed.map((item) => ({
      photo: String(item?.photo || "").replace(/\\/g, "/").replace(/^\/+/, ""),
      name: String(item?.name || ""),
      createdAt: Number(item?.createdAt) || 0,
    }));
  } catch {
    return [];
  }
}

async function removeStoredPhoto(photo) {
  const value = String(photo || "").replace(/\\/g, "/");
  if (!value.startsWith("user/Picture/")) return;
  const relative = value.slice("user/Picture/".length);
  const absoluteRoot = path.resolve(PHOTO_ROOT);
  const absolutePhoto = path.resolve(PHOTO_ROOT, relative);
  if (!absolutePhoto.startsWith(`${absoluteRoot}${path.sep}`)) return;
  await fs.unlink(absolutePhoto).catch(() => {});
}

async function directorySize(directory) {
  let total = 0;
  try {
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      const value = path.join(directory, entry.name);
      total += entry.isDirectory() ? await directorySize(value) : (await fs.stat(value)).size;
    }
  } catch {
    return total;
  }
  return total;
}

async function ensurePhotoQuota(account, incomingBytes) {
  const usedBytes = await directorySize(path.join(PHOTO_ROOT, safeSegment(account.id)));
  if (usedBytes + incomingBytes > MAX_ACCOUNT_PHOTO_BYTES) {
    const error = new Error("photo_quota_exceeded");
    error.statusCode = 413;
    throw error;
  }
}

async function loadAllCheckins() {
  try {
    const raw = await fs.readFile(CHECKINS_FILE, "utf8");
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return { [LEGACY_CHECKINS_KEY]: parsed };
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (error) {
    if (error.code === "ENOENT") return {};
    console.error("Could not read checkins store:", error);
    throw new Error("data_store_unavailable");
  }
}

async function saveAllCheckins(items) {
  await ensureDir(DATA_DIR);
  const tempFile = `${CHECKINS_FILE}.tmp`;
  await fs.writeFile(tempFile, JSON.stringify(items, null, 2), "utf8");
  await fs.rename(tempFile, CHECKINS_FILE);
}

async function loadAccounts() {
  try {
    const raw = await fs.readFile(ACCOUNTS_FILE, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error.code === "ENOENT") return [];
    console.error("Could not read accounts store:", error);
    throw new Error("data_store_unavailable");
  }
}

async function saveAccounts(items) {
  await ensureDir(DATA_DIR);
  const tempFile = `${ACCOUNTS_FILE}.tmp`;
  await fs.writeFile(tempFile, JSON.stringify(items, null, 2), "utf8");
  await fs.rename(tempFile, ACCOUNTS_FILE);
}

let accountWriteQueue = Promise.resolve();
function runAccountWrite(res, action) {
  const result = accountWriteQueue.then(action);
  accountWriteQueue = result.catch(() => {});
  return result.catch((error) => {
    console.error("Account write failed:", error);
    if (!res.headersSent) res.status(500).json({ error: "account_write_failed" });
  });
}

async function loadAllAlbums() {
  try {
    const parsed = JSON.parse(await fs.readFile(ALBUMS_FILE, "utf8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch (error) {
    if (error.code === "ENOENT") return {};
    console.error("Could not read albums store:", error);
    throw new Error("data_store_unavailable");
  }
}

async function saveAllAlbums(albums) {
  await ensureDir(DATA_DIR);
  const tempFile = `${ALBUMS_FILE}.tmp`;
  await fs.writeFile(tempFile, JSON.stringify(albums, null, 2), "utf8");
  await fs.rename(tempFile, ALBUMS_FILE);
}

const validAlbumId = (value) => /^[a-zA-Z0-9_-]{1,100}$/.test(String(value || ""));

function albumPhotos(value, ownedPaths) {
  if (!Array.isArray(value)) return [];
  return value.filter((photo) => validAlbumId(photo?.id))
    .map((photo) => ({
      id: String(photo.id),
      photo: String(photo.photo || "").replace(/\\/g, "/"),
      name: String(photo.name || "").slice(0, 200),
      place: String(photo.place || "").slice(0, 200),
      note: String(photo.note || "").slice(0, 4000),
      createdAt: Number(photo.createdAt) || 0,
    }))
    .filter((photo) => ownedPaths.has(photo.photo));
}

function imageType(file) {
  const bytes = file?.buffer;
  if (!bytes || bytes.length < 4) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { extension: ".jpg", mime: "image/jpeg" };
  }
  if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return { extension: ".png", mime: "image/png" };
  }
  if (bytes.subarray(0, 6).toString("ascii") === "GIF87a" || bytes.subarray(0, 6).toString("ascii") === "GIF89a") {
    return { extension: ".gif", mime: "image/gif" };
  }
  if (bytes.subarray(0, 4).toString("ascii") === "RIFF" && bytes.subarray(8, 12).toString("ascii") === "WEBP") {
    return { extension: ".webp", mime: "image/webp" };
  }
  return null;
}

function validatePhoto(file) {
  const type = imageType(file);
  if (!type) {
    const error = new Error("invalid_image_file");
    error.statusCode = 415;
    throw error;
  }
  return type;
}

function cleanText(value, maxLength) {
  return String(value || "").normalize("NFC").trim().slice(0, maxLength);
}

function tokenHash(token) {
  return createHash("sha256").update(String(token || "")).digest("hex");
}

function issueSession(account) {
  const token = randomBytes(32).toString("base64url");
  const hashed = tokenHash(token);
  const now = Date.now();
  const existing = Array.isArray(account.sessions)
    ? account.sessions.filter((session) => session && Number(session.expiresAt) > now)
    : (Array.isArray(account.tokenHashes) ? account.tokenHashes.map((hash) => ({
      hash,
      expiresAt: Number(account.tokenUpdatedAt || now) + SESSION_TTL_MS,
    })) : []);
  account.sessions = [...existing, { hash: hashed, expiresAt: now + SESSION_TTL_MS }].slice(-10);
  account.tokenHashes = account.sessions.map((session) => session.hash);
  account.tokenHash = hashed;
  account.tokenUpdatedAt = now;
  account.tokenExpiresAt = now + SESSION_TTL_MS;
  return token;
}

function revokeSessions(account) {
  account.sessions = [];
  account.tokenHashes = [];
  delete account.tokenHash;
  delete account.tokenExpiresAt;
}

function hashPassword(password, salt = randomBytes(16).toString("hex")) {
  return `${salt}:${scryptSync(String(password), salt, 32).toString("hex")}`;
}

function passwordMatches(password, stored) {
  const [salt, expectedHex] = String(stored || "").split(":");
  if (!salt || !expectedHex) return false;
  const actual = scryptSync(String(password), salt, 32);
  const expected = Buffer.from(expectedHex, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function normalizedName(value) {
  return String(value || "").normalize("NFC").trim();
}

function findAccount(accounts, name) {
  const key = normalizedName(name).toLocaleLowerCase("vi");
  return accounts.find((item) => normalizedName(item.name).toLocaleLowerCase("vi") === key);
}

async function authenticate(req, res) {
  const accounts = await loadAccounts();
  const authorization = String(req.get("Authorization") || "");
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (bearer) {
    const hashed = tokenHash(bearer);
    const now = Date.now();
    const account = accounts.find((item) => {
      const sessions = Array.isArray(item.sessions) ? item.sessions : [];
      const current = sessions.find((session) => session?.hash === hashed);
      if (current) return Number(current.expiresAt) > now;
      // Legacy accounts are accepted only during the one-release migration window.
      const legacyExpiry = Number(item.tokenExpiresAt || (Number(item.tokenUpdatedAt || 0) + SESSION_TTL_MS));
      return item.tokenHash === hashed && legacyExpiry > now;
    });
    if (account) return { account, accounts };
  }
  const name =
    req.get("X-User-Name") ||
    req.body?.name ||
    req.body?.userName ||
    req.body?.username;
  const password =
    req.get("X-Password") ||
    req.body?.currentPassword ||
    req.body?.password;
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

async function requireAuthenticated(req, res, next) {
  try {
    const authenticated = await authenticate(req, res);
    if (!authenticated) return;
    req.authenticated = authenticated;
    return next();
  } catch (error) {
    return next(error);
  }
}

function userCheckins(allCheckins, account) {
  if (Array.isArray(allCheckins[account.id])) return allCheckins[account.id];
  const legacyItems = allCheckins[LEGACY_CHECKINS_KEY];
  if (
    Array.isArray(legacyItems) &&
    allCheckins[LEGACY_OWNER_KEY] === account.id
  ) {
    return legacyItems;
  }
  return [];
}

function setUserCheckins(allCheckins, account, items) {
  allCheckins[account.id] = items;
  if (allCheckins[LEGACY_OWNER_KEY] === account.id) {
    delete allCheckins[LEGACY_CHECKINS_KEY];
    delete allCheckins[LEGACY_OWNER_KEY];
  }
}

app.use((req, res, next) => {
  const origin = req.get("Origin");
  if (origin && configuredOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, X-User-Name, X-Password");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  // Tokens, travel history and private photos must never enter shared caches.
  if (!req.path.startsWith("/releases/") && req.path !== "/api/health") {
    res.setHeader("Cache-Control", "no-store");
  }
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});
app.use(express.json({ limit: "2mb" }));

let dataMutationQueue = Promise.resolve();
function serializeDataMutation(req, res, next) {
  if (req.method === "GET" || req.method === "OPTIONS") return next();
  const previous = dataMutationQueue;
  let release;
  dataMutationQueue = new Promise((resolve) => { release = resolve; });
  previous.then(() => {
    let released = false;
    const done = () => {
      if (released) return;
      released = true;
      release();
    };
    res.once("finish", done);
    res.once("close", done);
    next();
  });
}
app.use("/api/checkins", serializeDataMutation);
app.use("/api/albums", serializeDataMutation);
app.use("/api/account", serializeDataMutation);

const authAttempts = new Map();
function authRateLimit(req, res, next) {
  const now = Date.now();
  if (authAttempts.size > 10000) {
    for (const [key, attempts] of authAttempts) {
      const recent = attempts.filter((time) => now - time < 15 * 60 * 1000);
      if (recent.length === 0) authAttempts.delete(key);
      else authAttempts.set(key, recent);
    }
  }
  const name = normalizedName(req.get("X-User-Name") || req.body?.name || req.body?.userName || req.body?.username).toLocaleLowerCase("vi");
  const key = `${req.ip}:${name}`;
  const ipKey = `ip:${req.ip}`;
  const ipRecent = (authAttempts.get(ipKey) || []).filter((time) => now - time < 15 * 60 * 1000);
  const recent = (authAttempts.get(key) || []).filter((time) => now - time < 15 * 60 * 1000);
  if (recent.length >= 20 || ipRecent.length >= 100) {
    res.setHeader("Retry-After", "900");
    return res.status(429).json({ error: "too_many_attempts", message: "Too many attempts. Try again later." });
  }
  recent.push(now);
  ipRecent.push(now);
  authAttempts.set(ipKey, ipRecent);
  authAttempts.set(key, recent);
  res.once("finish", () => {
    if (res.statusCode < 400) {
      authAttempts.delete(key);
      const attempts = authAttempts.get(ipKey) || [];
      const index = attempts.indexOf(now);
      if (index >= 0) attempts.splice(index, 1);
    }
  });
  next();
}

// Legacy password headers are accepted on data routes too. Apply the same
// attempt limit there so they cannot bypass the sign-in endpoint's protection.
app.use((req, res, next) => {
  if (!req.path.startsWith("/api/auth/") &&
      (req.get("X-Password") || req.body?.password || req.body?.currentPassword)) {
    return authRateLimit(req, res, next);
  }
  return next();
});

function ownedPhotoPaths(checkins, albums) {
  const paths = new Set();
  for (const item of [...checkins, ...albums]) {
    for (const photo of [...(item.photos || []), { photo: item.photo }]) {
      const value = String(photo?.photo || "");
      if (value.startsWith("user/Picture/") &&
          !value.split("/").some((part) => !part || part === "." || part === "..") &&
          !/[\\\u0000-\u001f]/.test(value)) paths.add(value);
    }
  }
  return paths;
}

async function accountOwnsPhoto(account, logicalPath) {
  const checkins = userCheckins(await loadAllCheckins(), account);
  const albums = await loadAllAlbums();
  return ownedPhotoPaths(checkins, albums[account.id] || []).has(logicalPath);
}

app.get(/^\/user\/Picture\/(.+)$/, asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const relative = String(req.params[0] || "").replace(/\\/g, "/");
  const logicalPath = `user/Picture/${relative}`;
  if (!await accountOwnsPhoto(authenticated.account, logicalPath)) {
    return res.status(404).json({ error: "photo_not_found" });
  }
  const absoluteRoot = path.resolve(PHOTO_ROOT);
  const absolutePhoto = path.resolve(PHOTO_ROOT, relative);
  if (!absolutePhoto.startsWith(`${absoluteRoot}${path.sep}`)) {
    return res.status(400).json({ error: "invalid_photo_path" });
  }
  res.sendFile(absolutePhoto, (error) => {
    if (error && !res.headersSent) res.status(error.statusCode || 404).json({ error: "photo_not_found" });
  });
}));

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "vietnam-map-backend" });
});

app.get("/api/checkins", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  res.json(userCheckins(await loadAllCheckins(), authenticated.account));
}));

app.get("/api/albums", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const allAlbums = await loadAllAlbums();
  res.json(Array.isArray(allAlbums[authenticated.account.id]) ? allAlbums[authenticated.account.id] : []);
}));

app.get("/api/account/storage", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const usedBytes = await directorySize(path.join(PHOTO_ROOT, safeSegment(authenticated.account.id)));
  res.json({ usedBytes, limitBytes: MAX_ACCOUNT_PHOTO_BYTES });
}));

app.delete("/api/account", (req, res) => runAccountWrite(res, async () => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const confirmation = normalizedName(req.body?.confirmation);
  if (confirmation.toLocaleLowerCase("vi") !== normalizedName(authenticated.account.name).toLocaleLowerCase("vi")) {
    return res.status(400).json({ error: "confirmation_required" });
  }
  const allCheckins = await loadAllCheckins();
  const allAlbums = await loadAllAlbums();
  const checkins = userCheckins(allCheckins, authenticated.account);
  const albums = allAlbums[authenticated.account.id] || [];
  const photos = new Set();
  for (const item of checkins) {
    for (const photo of Array.isArray(item.photos) ? item.photos : [{ photo: item.photo }]) {
      if (photo?.photo) photos.add(photo.photo);
    }
  }
  for (const album of albums) {
    for (const photo of album.photos || []) if (photo?.photo) photos.add(photo.photo);
  }
  delete allCheckins[authenticated.account.id];
  if (allCheckins[LEGACY_OWNER_KEY] === authenticated.account.id) {
    delete allCheckins[LEGACY_CHECKINS_KEY];
    delete allCheckins[LEGACY_OWNER_KEY];
  }
  delete allAlbums[authenticated.account.id];
  await saveAllCheckins(allCheckins);
  await saveAllAlbums(allAlbums);
  await saveAccounts(authenticated.accounts.filter((item) => item.id !== authenticated.account.id));
  for (const photo of photos) await removeStoredPhoto(photo);
  await fs.rm(path.join(PHOTO_ROOT, safeSegment(authenticated.account.id)), { recursive: true, force: true });
  res.json({ ok: true });
}));

app.post("/api/albums", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const id = String(req.body?.id || "");
  const name = String(req.body?.name || "").trim();
  if (!validAlbumId(id) || !name || name.length > 120) {
    return res.status(400).json({ error: "invalid_album" });
  }
  const allAlbums = await loadAllAlbums();
  const albums = Array.isArray(allAlbums[authenticated.account.id]) ? allAlbums[authenticated.account.id] : [];
  const index = albums.findIndex((album) => album.id === id);
  const previous = index < 0 ? null : albums[index];
  const isDeleted = previous?.isDeleted === true || req.body.isDeleted === true;
  const visibleCheckins = userCheckins(await loadAllCheckins(), authenticated.account);
  const ownedCheckins = new Set(visibleCheckins.map((item) => item.id));
  if (!isDeleted && albums.some((album) => album.id !== id && !album.isDeleted &&
      normalizedName(album.name).toLocaleLowerCase("vi") === name.toLocaleLowerCase("vi"))) {
    return res.status(409).json({ error: "album_exists", message: "An album with that name already exists." });
  }
  const deletedPhotoIds = new Set([...(previous?.deletedPhotoIds || []), ...(Array.isArray(req.body.deletedPhotoIds) ? req.body.deletedPhotoIds : [])]
    .map(String).filter(validAlbumId));
  const incomingExclusions = Array.isArray(req.body.excludedCheckInIds) ? req.body.excludedCheckInIds : null;
  const excludedCheckInIds = new Set(((Number(req.body.updatedAt) || 0) >= (previous?.updatedAt || 0) && incomingExclusions !== null
    ? incomingExclusions
    : previous?.excludedCheckInIds || [])
    .map(String).filter((value) => ownedCheckins.has(value)));
  const incomingIds = Array.isArray(req.body.checkInIds) ? req.body.checkInIds : [];
  const legacyLinkedIds = previous && (Number(req.body.updatedAt) || 0) >= (previous.updatedAt || 0)
    ? visibleCheckins.filter((item) => normalizedName(item.album).toLocaleLowerCase("vi") === normalizedName(previous.name).toLocaleLowerCase("vi")).map((item) => item.id)
    : [];
  const checkInIds = [...new Set([...(previous?.checkInIds || []), ...incomingIds, ...legacyLinkedIds]
    .map((value) => String(value)).filter((value) => ownedCheckins.has(value) && !excludedCheckInIds.has(value)))];
  const removedPhotos = (previous?.photos || []).filter((photo) => isDeleted || deletedPhotoIds.has(photo.id));
  const photos = new Map((previous?.photos || []).filter((photo) => !deletedPhotoIds.has(photo.id)).map((photo) => [photo.id, photo]));
  const ownedPaths = ownedPhotoPaths(visibleCheckins, albums);
  for (const photo of albumPhotos(req.body.photos, ownedPaths)) {
    if (!deletedPhotoIds.has(photo.id)) photos.set(photo.id, photo);
  }
  let orderedPhotos = [...photos.values()];
  if ((Number(req.body.updatedAt) || 0) >= (previous?.updatedAt || 0) && Array.isArray(req.body.photos)) {
    const order = new Map(req.body.photos.map((photo, position) => [String(photo?.id || ""), position]));
    orderedPhotos.sort((left, right) =>
      (order.get(left.id) ?? Number.MAX_SAFE_INTEGER) - (order.get(right.id) ?? Number.MAX_SAFE_INTEGER));
  }
  const album = {
    id,
    name: (Number(req.body.updatedAt) || 0) >= (previous?.updatedAt || 0) ? name : previous.name,
    createdAt: previous?.createdAt || Number(req.body.createdAt) || Date.now(),
    updatedAt: Math.max(previous?.updatedAt || 0, Number(req.body.updatedAt) || 0),
    checkInIds: isDeleted ? [] : checkInIds,
    photos: isDeleted ? [] : orderedPhotos,
    deletedPhotoIds: [...deletedPhotoIds],
    excludedCheckInIds: [...excludedCheckInIds],
    isDeleted,
    coverPhotoId: validAlbumId(req.body.coverPhotoId) ? String(req.body.coverPhotoId) : previous?.coverPhotoId || "",
    localOnly: false,
  };
  if (index < 0) albums.push(album);
  else albums[index] = album;
  allAlbums[authenticated.account.id] = albums;
  await saveAllAlbums(allAlbums);
  for (const photo of removedPhotos) await removeStoredPhoto(photo.photo);
  res.json(album);
}));

app.post("/api/albums/:id/photos", requireAuthenticated, UPLOAD.single("photo"), asyncRoute(async (req, res) => {
  const authenticated = req.authenticated;
  const id = String(req.params.id || "");
  const photoId = String(req.body.photoId || "");
  if (!validAlbumId(id) || !validAlbumId(photoId) || !req.file) {
    return res.status(400).json({ error: "invalid_album_photo" });
  }
  const allAlbums = await loadAllAlbums();
  const album = (allAlbums[authenticated.account.id] || []).find((item) => item.id === id);
  if (!album) return res.status(404).json({ error: "album_not_found" });
  if (album.isDeleted) return res.status(409).json({ error: "album_was_deleted" });
  const existing = album.photos.find((photo) => photo.id === photoId);
  if (existing) return res.json(existing);
  if ((album.deletedPhotoIds || []).includes(photoId)) {
    return res.status(409).json({ error: "photo_was_deleted" });
  }
  const userFolder = safeSegment(authenticated.account.id);
  const directory = assertInside(PHOTO_ROOT, path.join(PHOTO_ROOT, userFolder, "albums", id));
  await ensureDir(directory);
  const type = imageType(req.file);
  if (!type) return res.status(415).json({ error: "invalid_image_file" });
  try {
    await ensurePhotoQuota(authenticated.account, req.file.buffer.length);
  } catch (error) {
    return res.status(error.statusCode || 413).json({ error: "photo_quota_exceeded" });
  }
  const fileName = `${Date.now()}-${randomUUID().slice(0, 8)}${type.extension}`;
  const destination = assertInside(directory, path.join(directory, fileName));
  await fs.writeFile(destination, req.file.buffer, { flag: "wx" });
  const photo = {
    id: photoId,
    photo: `user/Picture/${userFolder}/albums/${id}/${fileName}`,
    name: String(req.file.originalname || "photo").slice(0, 200),
    place: String(req.body.place || "").slice(0, 200),
    note: String(req.body.note || "").slice(0, 4000),
    createdAt: Number(req.body.createdAt) || Date.now(),
  };
  album.photos.push(photo);
  album.updatedAt = Math.max(album.updatedAt || 0, Date.now());
  try {
    await saveAllAlbums(allAlbums);
  } catch (error) {
    await fs.unlink(destination).catch(() => {});
    throw error;
  }
  res.json(photo);
}));

app.post("/api/auth/register", authRateLimit, (req, res) => runAccountWrite(res, async () => {
  const name = normalizedName(req.body.name || req.body.userName || req.body.username);
  const password = String(req.body.password || "");
  if (!/^[\p{L}\p{N}_. -]{3,40}$/u.test(name) || password.length < 8 || password.length > 128) {
    return res.status(400).json({ error: "invalid_account", message: "Use a 3-40 character user name and a password with at least 8 characters." });
  }
  const accounts = await loadAccounts();
  if (findAccount(accounts, name)) {
    return res.status(409).json({ error: "account_exists", message: "This user name is already registered. Sign in or choose another name." });
  }
  const account = { id: randomUUID(), name, passwordHash: hashPassword(password), updatedAt: Date.now() };
  const token = issueSession(account);
  accounts.push(account);
  await saveAccounts(accounts);
  res.status(201).json({ ok: true, name, token });
}));

app.post("/api/auth/login", authRateLimit, (req, res) => runAccountWrite(res, async () => {
  const name = normalizedName(req.body.name || req.body.userName || req.body.username);
  const accounts = await loadAccounts();
  const account = findAccount(accounts, name);
  if (!account) return res.status(401).json({ error: "invalid_credentials", message: "Incorrect user name or password." });
  if (!passwordMatches(req.body.password, account.passwordHash)) {
    return res.status(401).json({ error: "invalid_credentials", message: "Incorrect user name or password." });
  }
  const token = issueSession(account);
  await saveAccounts(accounts);
  res.json({ ok: true, name: account.name, token });
}));

app.post("/api/auth/reset-password", authRateLimit, (req, res) => runAccountWrite(res, async () => {
  const accounts = await loadAccounts();
  const account = findAccount(accounts, req.body.name || req.body.userName || req.body.username);
  const newPassword = String(req.body.newPassword || req.body.password || "");
  if (!account) return res.status(404).json({ error: "account_not_found", message: "Account not found." });
  if (!passwordMatches(req.get("X-Password") || req.body.currentPassword, account.passwordHash)) {
    return res.status(401).json({ error: "incorrect_password", message: "Current password is incorrect." });
  }
  if (newPassword.length < 8 || newPassword.length > 128) {
    return res.status(400).json({ error: "weak_password", message: "New password must have at least 8 characters." });
  }
  account.passwordHash = hashPassword(newPassword);
  revokeSessions(account);
  const token = issueSession(account);
  account.updatedAt = Date.now();
  await saveAccounts(accounts);
  res.json({ ok: true, name: account.name, token });
}));

app.post("/api/auth/update", authRateLimit, (req, res) => runAccountWrite(res, async () => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const { accounts, account } = authenticated;
  const currentPassword = String(req.get("X-Password") || req.body.currentPassword || "");
  if (!passwordMatches(currentPassword, account.passwordHash)) {
    return res.status(401).json({ error: "incorrect_password", message: "Current password is incorrect." });
  }
  const newName = normalizedName(req.body.newName);
  const newPassword = String(req.body.newPassword || "");
  if (newName && !/^[\p{L}\p{N}_. -]{3,40}$/u.test(newName)) {
    return res.status(400).json({ error: "invalid_name", message: "User name must contain 3-40 safe characters." });
  }
  if (newName && findAccount(accounts.filter((item) => item.id !== account.id), newName)) {
    return res.status(409).json({ error: "account_exists", message: "An account with that name already exists." });
  }
  if (newPassword && (newPassword.length < 8 || newPassword.length > 128)) {
    return res.status(400).json({ error: "weak_password", message: "New password must have at least 8 characters." });
  }
  if (newName && newName !== account.name) {
    const allCheckins = await loadAllCheckins();
    if (!Array.isArray(allCheckins[account.id])) {
      const legacy = userCheckins(allCheckins, account);
      if (legacy.length > 0) {
        setUserCheckins(allCheckins, account, legacy);
        await saveAllCheckins(allCheckins);
      }
    }
  }
  if (newName) account.name = newName;
  if (newPassword) account.passwordHash = hashPassword(newPassword);
  revokeSessions(account);
  const token = issueSession(account);
  account.updatedAt = Date.now();
  await saveAccounts(accounts);
  // Keep existing photo paths valid after a rename. New uploads use the new name.
  res.json({ ok: true, name: account.name, token });
}));

app.post("/api/auth/logout", (req, res) => runAccountWrite(res, async () => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const { account, accounts } = authenticated;
  const bearer = String(req.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  const hashed = tokenHash(bearer);
  account.sessions = (account.sessions || []).filter((session) => session?.hash !== hashed);
  account.tokenHashes = account.sessions.map((session) => session.hash);
  if (account.tokenHash === hashed) {
    account.tokenHash = account.sessions.at(-1)?.hash || "";
    account.tokenExpiresAt = account.sessions.at(-1)?.expiresAt || 0;
  }
  await saveAccounts(accounts);
  res.json({ ok: true });
}));

app.get("/api/update/latest", asyncRoute(async (req, res) => {
  try {
    const raw = await fs.readFile(UPDATE_MANIFEST, "utf8");
    const manifest = JSON.parse(raw);
    const apkFile = manifest.apkFile || "app-release.apk";
    const apkPath = path.join(RELEASES_DIR, apkFile);
    await fs.access(apkPath);
    const sha256 = createHash("sha256").update(await fs.readFile(apkPath)).digest("hex");
    res.json({
      versionName: manifest.versionName || "1.0.0",
      versionCode: Number(manifest.versionCode) || 1,
      notes: manifest.notes || "",
      apkUrl: `/releases/${encodeURIComponent(apkFile)}`,
      sha256,
    });
  } catch (err) {
    res.status(404).json({ error: "no_update_release_found" });
  }
}));

app.get("/releases/:file", asyncRoute(async (req, res) => {
  const fileName = path.basename(req.params.file);
  if (!fileName.endsWith(".apk")) return res.status(400).json({ error: "apk_required" });
  res.download(path.join(RELEASES_DIR, fileName));
}));

app.post(
  "/api/checkins",
  requireAuthenticated,
  UPLOAD.fields([
    { name: "photo", maxCount: 1 },
    { name: "photos", maxCount: 24 },
  ]),
  asyncRoute(async (req, res) => {
  try {
    const authenticated = req.authenticated;
    const { id: incomingId, source = "gps", synced, createdAt: incomingCreatedAt, favorite, rating, tags, photoPath } = req.body;
    const city = cleanText(req.body.city, 120);
    const place = cleanText(req.body.place, 200);
    const notes = cleanText(req.body.notes, 4000);
    const album = cleanText(req.body.album, 120);
    const hideLocation = req.body.hideLocation === "true" || req.body.hideLocation === true;
    const lat = hideLocation ? 0 : Number(req.body.lat);
    const lng = hideLocation ? 0 : Number(req.body.lng);
    if (!city) return res.status(400).json({ error: "city_required" });
    if (incomingId && !/^[a-zA-Z0-9_-]{1,100}$/.test(String(incomingId))) {
      return res.status(400).json({ error: "invalid_checkin_id" });
    }
    if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
      return res.status(400).json({ error: "invalid_coordinates" });
    }

    const allCheckins = await loadAllCheckins();
    const checkins = userCheckins(allCheckins, authenticated.account);
    const id = incomingId || randomUUID();
    const createdAt = Number(incomingCreatedAt) || Date.now();
    const expectedPhotoPrefix = `user/Picture/${safeSegment(authenticated.account.id)}/`;
    const allAlbums = await loadAllAlbums();
    const ownedPaths = ownedPhotoPaths(checkins, allAlbums[authenticated.account.id] || []);
    const previous = checkins.find((entry) => entry.id === id);
    const baseUpdatedAt = Number(req.body.baseUpdatedAt) || 0;
    if (previous && req.body.force !== "true" && baseUpdatedAt > 0 && Number(previous.updatedAt || previous.createdAt || 0) > baseUpdatedAt) {
      return res.status(409).json({ error: "sync_conflict", remote: previous });
    }
    const previousPhotos = Array.isArray(previous?.photos)
      ? previous.photos.map((entry) => String(entry.photo || "")).filter(Boolean)
      : previous?.photo
        ? [previous.photo]
        : [];
    const requestedPhotoPath = String(photoPath || "")
      .replace(/\\/g, "/")
      .replace(/^\/+/, "");
    let savedPhotoPath = ownedPaths.has(requestedPhotoPath)
      ? requestedPhotoPath
      : "";

    const hasPhotoAlbum = Object.prototype.hasOwnProperty.call(req.body, "photos");
    const uploadedPhotos = req.files?.photos || [];
    const legacyFile = req.files?.photo?.[0];
    const photoAssets = parsePhotoAssets(req.body.photos);
    const savedPhotos = [];
    const userFolder = safeSegment(authenticated.account.id);
    const albumFolder = String(album || "").trim()
      ? `${safeSegment(album)}/`
      : "";
    const cityFolder = safeSegment(city);
    const destDir = assertInside(PHOTO_ROOT, path.join(PHOTO_ROOT, userFolder, albumFolder, cityFolder));
    const saveUploaded = async (file, name, assetCreatedAt) => {
      await ensurePhotoQuota(authenticated.account, file.buffer.length);
      await ensureDir(destDir);
      const type = validatePhoto(file);
      const baseName = safeFileName(
        path.basename(file.originalname || name || "photo", path.extname(file.originalname || "")),
      );
      const fileName = `${assetCreatedAt || createdAt}-${Date.now()}-${randomUUID().slice(0, 8)}-${baseName}${type.extension}`;
      const destination = assertInside(destDir, path.join(destDir, fileName));
      await fs.writeFile(destination, file.buffer, { flag: "wx" });
      return `${expectedPhotoPrefix}${albumFolder}${cityFolder}/${fileName}`;
    };

    if (hasPhotoAlbum) {
      let uploadIndex = 0;
      for (const asset of photoAssets) {
        let photo = ownedPaths.has(asset.photo)
          ? asset.photo
          : "";
        if (!photo && uploadIndex < uploadedPhotos.length) {
          const file = uploadedPhotos[uploadIndex++];
          photo = await saveUploaded(file, asset.name, asset.createdAt);
        }
        if (photo) savedPhotos.push({ photo, name: asset.name, createdAt: asset.createdAt || createdAt });
      }
      while (uploadIndex < uploadedPhotos.length) {
        const file = uploadedPhotos[uploadIndex++];
        const photo = await saveUploaded(file, file.originalname, createdAt);
        savedPhotos.push({ photo, name: file.originalname || "photo", createdAt });
      }
    } else {
      if (legacyFile) {
        savedPhotoPath = await saveUploaded(legacyFile, legacyFile.originalname, createdAt);
      }
      if (savedPhotoPath) savedPhotos.push({ photo: savedPhotoPath, name: legacyFile?.originalname || "", createdAt });
    }

    if (previous && hasPhotoAlbum) {
      const nextPaths = new Set(savedPhotos.map((entry) => entry.photo));
      for (const oldPhoto of previousPhotos) {
        if (!nextPaths.has(oldPhoto)) await removeStoredPhoto(oldPhoto);
      }
    }

    const item = {
      id,
      city,
      place: place || city,
      notes: notes || "",
      source,
      synced: synced === "true" || synced === true,
      createdAt,
      updatedAt: Date.now(),
      lat,
      lng,
      photo: savedPhotos[0]?.photo || savedPhotoPath || "",
      photos: savedPhotos,
      album: String(album || "").trim(),
      favorite: favorite === "true" || favorite === true,
      rating: Math.max(0, Math.min(5, Number(rating) || 0)),
      tags: parseTags(tags),
      localOnly: false,
      hideLocation,
    };

    const existingIndex = checkins.findIndex((x) => x.id === id);
    if (existingIndex >= 0) {
      checkins[existingIndex] = {
        ...checkins[existingIndex],
        ...item,
        photo: hasPhotoAlbum ? item.photo : savedPhotoPath || checkins[existingIndex].photo || "",
        photos: hasPhotoAlbum ? savedPhotos : (savedPhotos.length ? savedPhotos : checkins[existingIndex].photos || []),
        album: hasPhotoAlbum ? item.album : checkins[existingIndex].album || item.album,
      };
    } else {
      checkins.unshift(item);
    }
    setUserCheckins(allCheckins, authenticated.account, checkins);
    await saveAllCheckins(allCheckins);
    res.json(existingIndex >= 0 ? checkins[existingIndex] : item);
  } catch (err) {
    console.error("Check-in write failed:", err);
    res.status(err.statusCode || 500).json({ error: err.statusCode ? err.message : "server_error" });
  }
}));

app.delete("/api/checkins/:id", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const allCheckins = await loadAllCheckins();
  const checkins = userCheckins(allCheckins, authenticated.account);
  const removed = checkins.find((item) => item.id === req.params.id);
  const next = checkins.filter((item) => item.id !== req.params.id);
  setUserCheckins(allCheckins, authenticated.account, next);
  await saveAllCheckins(allCheckins);
  const removedPhotos = Array.isArray(removed?.photos)
    ? removed.photos.map((entry) => entry.photo).filter(Boolean)
    : removed?.photo
      ? [removed.photo]
      : [];
  for (const photo of removedPhotos) await removeStoredPhoto(photo);
  res.json({ ok: true });
}));

app.delete("/api/checkins/:id/photo", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const allCheckins = await loadAllCheckins();
  const checkins = userCheckins(allCheckins, authenticated.account);
  const item = checkins.find((entry) => entry.id === req.params.id);
  if (!item) return res.status(404).json({ error: "not_found" });
  const previousPhotos = Array.isArray(item.photos)
    ? item.photos.map((entry) => entry.photo).filter(Boolean)
    : item.photo
      ? [item.photo]
      : [];
  const requestedPhoto = String(req.query.photo || "").replace(/\\/g, "/");
  if (requestedPhoto) {
    const remaining = previousPhotos.filter((photo) => photo !== requestedPhoto);
    if (remaining.length === previousPhotos.length) {
      return res.status(404).json({ error: "photo_not_found" });
    }
    const existingAssets = Array.isArray(item.photos) ? item.photos : [];
    item.photos = existingAssets.filter((entry) => entry.photo !== requestedPhoto);
    item.photo = item.photos[0]?.photo || remaining[0] || "";
    await removeStoredPhoto(requestedPhoto);
  } else {
    item.photo = "";
    item.photos = [];
    for (const previousPhoto of previousPhotos) {
      await removeStoredPhoto(previousPhoto);
    }
  }
  item.synced = true;
  setUserCheckins(allCheckins, authenticated.account, checkins);
  await saveAllCheckins(allCheckins);
  res.json(item);
}));

app.delete("/api/checkins", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const allCheckins = await loadAllCheckins();
  const existing = userCheckins(allCheckins, authenticated.account);
  setUserCheckins(allCheckins, authenticated.account, []);
  await saveAllCheckins(allCheckins);
  for (const item of existing) {
    const photos = Array.isArray(item.photos)
      ? item.photos.map((entry) => entry.photo).filter(Boolean)
      : item.photo
        ? [item.photo]
        : [];
    for (const photo of photos) await removeStoredPhoto(photo);
  }
  res.json({ ok: true });
}));

app.post("/api/checkins/:id/synced", asyncRoute(async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const allCheckins = await loadAllCheckins();
  const checkins = userCheckins(allCheckins, authenticated.account);
  const item = checkins.find((x) => x.id === req.params.id);
  if (!item) return res.status(404).json({ error: "not_found" });
  item.synced = true;
  setUserCheckins(allCheckins, authenticated.account, checkins);
  await saveAllCheckins(allCheckins);
  res.json(item);
}));

app.use((error, _req, res, _next) => {
  if (error instanceof multer.MulterError) {
    return res.status(413).json({ error: "upload_limit_exceeded" });
  }
  console.error("Unhandled request error:", error);
  return res.status(error?.statusCode || 500).json({ error: "server_error" });
});

async function startServer(port) {
  const tls = TLS_CERT_FILE && TLS_KEY_FILE
    ? { cert: await fs.readFile(TLS_CERT_FILE), key: await fs.readFile(TLS_KEY_FILE) }
    : null;
  if (!tls && process.env.NODE_ENV === "production" && process.env.ALLOW_INSECURE_HTTP !== "1") {
    throw new Error("TLS_CERT_FILE and TLS_KEY_FILE are required in production (or explicitly set ALLOW_INSECURE_HTTP=1 for a trusted LAN test).");
  }
  return new Promise((resolve, reject) => {
    const server = tls
      ? https.createServer(tls, app).listen(port, "0.0.0.0", () => resolve(server))
      : app.listen(port, "0.0.0.0", () => resolve(server));
    server.on("error", reject);
  });
}

async function boot() {
  const checkins = await loadAllCheckins();
  if (Array.isArray(checkins[LEGACY_CHECKINS_KEY]) &&
      !Object.prototype.hasOwnProperty.call(checkins, LEGACY_OWNER_KEY)) {
    // Bind once, before accepting registrations. An unclaimed legacy store
    // stays private until its owner is recovered by the server operator.
    const accounts = await loadAccounts();
    checkins[LEGACY_OWNER_KEY] = findAccount(accounts, "thanhhao")?.id || "";
    await saveAllCheckins(checkins);
  }
  for (let port = preferredPort; port < preferredPort + 20; port += 1) {
    try {
      await startServer(port);
      const protocol = TLS_CERT_FILE && TLS_KEY_FILE ? "https" : "http";
      console.log(`Server running at ${protocol}://localhost:${port}`);

      return;
    } catch (err) {
      if (err.code !== "EADDRINUSE") throw err;
    }
  }
  throw new Error(`No free port found starting from ${preferredPort}`);
}

boot().catch((err) => {
  console.error(err);
  process.exit(1);
});
