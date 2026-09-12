import express from "express";
import multer from "multer";
import path from "path";
import fs from "fs/promises";
import { randomBytes, randomUUID, scryptSync, timingSafeEqual } from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const preferredPort = Number(process.env.PORT || 3000);

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "server-data");
const CHECKINS_FILE = path.join(DATA_DIR, "checkins.json");
const ACCOUNTS_FILE = path.join(DATA_DIR, "accounts.json");
const PHOTO_ROOT = process.env.PHOTO_ROOT || path.join(__dirname, "user", "Picture");
const LEGACY_CHECKINS_KEY = "__legacy";
const RELEASES_DIR = path.join(__dirname, "releases");
const UPDATE_MANIFEST = path.join(RELEASES_DIR, "latest.json");
const UPLOAD = multer({ storage: multer.memoryStorage(), limits: { fileSize: 12 * 1024 * 1024 } });

const ensureDir = async (dir) => {
  await fs.mkdir(dir, { recursive: true });
};

const cleanSegment = (s) =>
  String(s || "")
    .normalize("NFC")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_")
    .trim() || "Unknown";

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

async function loadAllCheckins() {
  try {
    const raw = await fs.readFile(CHECKINS_FILE, "utf8");
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return { [LEGACY_CHECKINS_KEY]: parsed };
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
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
  } catch {
    return [];
  }
}

async function saveAccounts(items) {
  await ensureDir(DATA_DIR);
  const tempFile = `${ACCOUNTS_FILE}.tmp`;
  await fs.writeFile(tempFile, JSON.stringify(items, null, 2), "utf8");
  await fs.rename(tempFile, ACCOUNTS_FILE);
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

function userCheckins(allCheckins, account) {
  if (Array.isArray(allCheckins[account.id])) return allCheckins[account.id];
  const legacyItems = allCheckins[LEGACY_CHECKINS_KEY];
  if (
    Array.isArray(legacyItems) &&
    cleanSegment(account.name).toLocaleLowerCase("vi") === "thanhhao"
  ) {
    return legacyItems;
  }
  return [];
}

function setUserCheckins(allCheckins, account, items) {
  allCheckins[account.id] = items;
  if (cleanSegment(account.name).toLocaleLowerCase("vi") === "thanhhao") {
    delete allCheckins[LEGACY_CHECKINS_KEY];
  }
}

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, X-User-Name, X-Password");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});
app.use(express.json({ limit: "2mb" }));
app.use("/user/Picture", express.static(PHOTO_ROOT));

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "vietnam-map-backend" });
});

app.get("/api/checkins", async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  res.json(userCheckins(await loadAllCheckins(), authenticated.account));
});

app.post("/api/auth/register", async (req, res) => {
  const name = normalizedName(req.body.name || req.body.userName || req.body.username);
  const password = String(req.body.password || "");
  if (!name || password.length < 4) {
    return res.status(400).json({ error: "invalid_account", message: "Enter a name and a password with at least 4 characters." });
  }
  const accounts = await loadAccounts();
  if (findAccount(accounts, name)) {
    return res.status(409).json({ error: "account_exists", message: "This device already has an account. Sign in or reset password." });
  }
  accounts.push({ id: randomUUID(), name, passwordHash: hashPassword(password), updatedAt: Date.now() });
  await saveAccounts(accounts);
  res.status(201).json({ ok: true, name });
});

app.post("/api/auth/login", async (req, res) => {
  const name = normalizedName(req.body.name || req.body.userName || req.body.username);
  const account = findAccount(await loadAccounts(), name);
  if (!account) return res.status(404).json({ error: "account_not_found", message: "Account not found. Please register first." });
  if (!passwordMatches(req.body.password, account.passwordHash)) {
    return res.status(401).json({ error: "incorrect_password", message: "Incorrect password for this user name." });
  }
  res.json({ ok: true, name: account.name });
});

app.post("/api/auth/reset-password", async (req, res) => {
  const accounts = await loadAccounts();
  const account = findAccount(accounts, req.body.name || req.body.userName || req.body.username);
  const newPassword = String(req.body.newPassword || req.body.password || "");
  if (!account) return res.status(404).json({ error: "account_not_found", message: "Account not found." });
  if (newPassword.length < 4) {
    return res.status(400).json({ error: "weak_password", message: "New password must have at least 4 characters." });
  }
  account.passwordHash = hashPassword(newPassword);
  account.updatedAt = Date.now();
  await saveAccounts(accounts);
  res.json({ ok: true, name: account.name });
});

app.post("/api/auth/update", async (req, res) => {
  const accounts = await loadAccounts();
  const account = findAccount(accounts, req.body.name || req.body.userName || req.body.username);
  const currentPassword = String(req.get("X-Password") || req.body.currentPassword || "");
  if (!account) return res.status(404).json({ error: "account_not_found", message: "Account not found." });
  if (!passwordMatches(currentPassword, account.passwordHash)) {
    return res.status(401).json({ error: "incorrect_password", message: "Current password is incorrect." });
  }
  const newName = normalizedName(req.body.newName);
  const newPassword = String(req.body.newPassword || "");
  if (newName && findAccount(accounts.filter((item) => item.id !== account.id), newName)) {
    return res.status(409).json({ error: "account_exists", message: "An account with that name already exists." });
  }
  if (newPassword && newPassword.length < 4) {
    return res.status(400).json({ error: "weak_password", message: "New password must have at least 4 characters." });
  }
  const oldName = account.name;
  if (newName) account.name = newName;
  if (newPassword) account.passwordHash = hashPassword(newPassword);
  account.updatedAt = Date.now();
  await saveAccounts(accounts);
  if (newName) {
    const oldDir = path.join(PHOTO_ROOT, cleanSegment(oldName));
    const newDir = path.join(PHOTO_ROOT, cleanSegment(newName));
    if (oldDir !== newDir) {
      await ensureDir(PHOTO_ROOT);
      await fs.rename(oldDir, newDir).catch(() => {});
    }
  }
  res.json({ ok: true, name: account.name });
});

app.get("/api/update/latest", async (req, res) => {
  try {
    const raw = await fs.readFile(UPDATE_MANIFEST, "utf8");
    const manifest = JSON.parse(raw);
    const apkFile = manifest.apkFile || "app-release.apk";
    const apkPath = path.join(RELEASES_DIR, apkFile);
    await fs.access(apkPath);
    res.json({
      versionName: manifest.versionName || "1.0.0",
      versionCode: Number(manifest.versionCode) || 1,
      notes: manifest.notes || "",
      apkUrl: `/releases/${encodeURIComponent(apkFile)}`,
    });
  } catch (err) {
    res.status(404).json({ error: "no_update_release_found" });
  }
});

app.get("/releases/:file", async (req, res) => {
  const fileName = path.basename(req.params.file);
  if (!fileName.endsWith(".apk")) return res.status(400).json({ error: "apk_required" });
  res.download(path.join(RELEASES_DIR, fileName));
});

app.post(
  "/api/checkins",
  UPLOAD.fields([
    { name: "photo", maxCount: 1 },
    { name: "photos", maxCount: 24 },
  ]),
  async (req, res) => {
  try {
    const authenticated = await authenticate(req, res);
    if (!authenticated) return;
    const { id: incomingId, city, place, notes, source = "gps", synced, createdAt: incomingCreatedAt, lat, lng, photoPath, favorite, rating, tags, album } = req.body;
    if (!city) return res.status(400).json({ error: "city_required" });

    const allCheckins = await loadAllCheckins();
    const checkins = userCheckins(allCheckins, authenticated.account);
    const id = incomingId || randomUUID();
    const createdAt = Number(incomingCreatedAt) || Date.now();
    const expectedPhotoPrefix = `user/Picture/${cleanSegment(authenticated.account.name)}/`;
    const requestedPhotoPath = String(photoPath || "")
      .replace(/\\/g, "/")
      .replace(/^\/+/, "");
    let savedPhotoPath = requestedPhotoPath.startsWith(expectedPhotoPrefix)
      ? requestedPhotoPath
      : "";

    const hasPhotoAlbum = Object.prototype.hasOwnProperty.call(req.body, "photos");
    const previous = checkins.find((entry) => entry.id === id);
    const previousPhotos = Array.isArray(previous?.photos)
      ? previous.photos.map((entry) => String(entry.photo || "")).filter(Boolean)
      : previous?.photo
        ? [previous.photo]
        : [];
    const uploadedPhotos = req.files?.photos || [];
    const legacyFile = req.files?.photo?.[0];
    const photoAssets = parsePhotoAssets(req.body.photos);
    const savedPhotos = [];
    const userFolder = cleanSegment(authenticated.account.name);
    const albumFolder = String(album || "").trim()
      ? `${cleanSegment(album)}/`
      : "";
    const cityFolder = cleanSegment(city);
    const destDir = path.join(PHOTO_ROOT, userFolder, albumFolder, cityFolder);
    const saveUploaded = async (file, name, assetCreatedAt) => {
      await ensureDir(destDir);
      const ext = path.extname(file.originalname || "").slice(0, 10) || ".jpg";
      const baseName = safeFileName(
        path.basename(file.originalname || name || "photo", path.extname(file.originalname || "")),
      );
      const fileName = `${assetCreatedAt || createdAt}-${Date.now()}-${randomUUID().slice(0, 8)}-${baseName}${ext}`;
      await fs.writeFile(path.join(destDir, fileName), file.buffer);
      return `${expectedPhotoPrefix}${albumFolder}${cityFolder}/${fileName}`;
    };

    if (hasPhotoAlbum) {
      let uploadIndex = 0;
      for (const asset of photoAssets) {
        let photo = asset.photo.startsWith(expectedPhotoPrefix) ? asset.photo : "";
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
      lat: Number(lat) || 0,
      lng: Number(lng) || 0,
      photo: savedPhotos[0]?.photo || savedPhotoPath || "",
      photos: savedPhotos,
      album: String(album || "").trim(),
      favorite: favorite === "true" || favorite === true,
      rating: Math.max(0, Math.min(5, Number(rating) || 0)),
      tags: parseTags(tags),
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
    res.status(500).json({ error: err.message || "server_error" });
  }
});

app.delete("/api/checkins/:id", async (req, res) => {
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
});

app.delete("/api/checkins/:id/photo", async (req, res) => {
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
});

app.delete("/api/checkins", async (req, res) => {
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
});

app.post("/api/seed", async (req, res) => {
  const authenticated = await authenticate(req, res);
  if (!authenticated) return;
  const items = [
    {
      id: randomUUID(),
      city: "Đà Nẵng",
      place: "Cầu Rồng",
      notes: "Hoàng hôn, trời nhiều gió.",
      source: "gps",
      synced: false,
      createdAt: Date.now() - 1000 * 60 * 60 * 26,
      lat: 16.0544,
      lng: 108.2022,
      photo: "",
    },
    {
      id: randomUUID(),
      city: "Hà Nội",
      place: "Hồ Hoàn Kiếm",
      notes: "Dạo quanh buổi sáng.",
      source: "gps",
      synced: true,
      createdAt: Date.now() - 1000 * 60 * 60 * 49,
      lat: 21.0285,
      lng: 105.8542,
      photo: "",
    },
    {
      id: randomUUID(),
      city: "Ninh Bình",
      place: "Tràng An",
      notes: "Đi thuyền 2 tiếng.",
      source: "ai",
      synced: false,
      createdAt: Date.now() - 1000 * 60 * 60 * 72,
      lat: 20.2506,
      lng: 105.9744,
      photo: "",
    },
  ];
  const allCheckins = await loadAllCheckins();
  setUserCheckins(allCheckins, authenticated.account, items);
  await saveAllCheckins(allCheckins);
  res.json(items);
});

app.post("/api/checkins/:id/synced", async (req, res) => {
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
});

app.use(async (req, res, next) => {
  if (req.path.startsWith("/api/")) return next();
  if (req.path === "/") {
    res.sendFile(path.join(__dirname, "index.html"));
    return;
  }
  next();
});

async function startServer(port) {
  return new Promise((resolve, reject) => {
    const server = app.listen(port, "0.0.0.0", () => resolve(server));
    server.on("error", reject);
  });
}

async function boot() {
  for (let port = preferredPort; port < preferredPort + 20; port += 1) {
    try {
      await startServer(port);
      console.log(`Server running at http://localhost:${port}`);

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
