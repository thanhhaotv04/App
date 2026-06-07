import express from "express";
import multer from "multer";
import path from "path";
import fs from "fs/promises";
import { randomUUID } from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
const preferredPort = Number(process.env.PORT || 3000);

const DATA_DIR = path.join(__dirname, "server-data");
const CHECKINS_FILE = path.join(DATA_DIR, "checkins.json");
const PHOTO_ROOT = path.join(__dirname, "user", "Picture", "thanhhao");
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

async function loadCheckins() {
  try {
    const raw = await fs.readFile(CHECKINS_FILE, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function saveCheckins(items) {
  await ensureDir(DATA_DIR);
  const tempFile = `${CHECKINS_FILE}.tmp`;
  await fs.writeFile(tempFile, JSON.stringify(items, null, 2), "utf8");
  await fs.rename(tempFile, CHECKINS_FILE);
}

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});
app.use(express.json({ limit: "2mb" }));
app.use(express.static(__dirname));

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "vietnam-map-backend" });
});

app.get("/api/checkins", async (_req, res) => {
  res.json(await loadCheckins());
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

app.post("/api/checkins", UPLOAD.single("photo"), async (req, res) => {
  try {
    const { id: incomingId, city, place, notes, source = "gps", synced, createdAt: incomingCreatedAt, lat, lng, photoPath } = req.body;
    if (!city) return res.status(400).json({ error: "city_required" });

    const checkins = await loadCheckins();
    const id = incomingId || randomUUID();
    const createdAt = Number(incomingCreatedAt) || Date.now();
    let savedPhotoPath = photoPath || "";

    if (req.file) {
      const cityFolder = cleanSegment(city);
      const destDir = path.join(PHOTO_ROOT, cityFolder);
      await ensureDir(destDir);
      const ext = path.extname(req.file.originalname || "").slice(0, 10) || ".jpg";
      const fileName = `${createdAt}-${safeFileName(path.basename(req.file.originalname || "photo", path.extname(req.file.originalname || "")))}${ext}`;
      const fullPath = path.join(destDir, fileName);
      await fs.writeFile(fullPath, req.file.buffer);
      savedPhotoPath = path.relative(__dirname, fullPath).replace(/\\/g, "/");
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
      photo: savedPhotoPath,
    };

    const existingIndex = checkins.findIndex((x) => x.id === id);
    if (existingIndex >= 0) {
      checkins[existingIndex] = { ...checkins[existingIndex], ...item, photo: savedPhotoPath || checkins[existingIndex].photo || "" };
    } else {
      checkins.unshift(item);
    }
    await saveCheckins(checkins);
    res.json(existingIndex >= 0 ? checkins[existingIndex] : item);
  } catch (err) {
    res.status(500).json({ error: err.message || "server_error" });
  }
});

app.delete("/api/checkins/:id", async (req, res) => {
  const checkins = await loadCheckins();
  const next = checkins.filter((item) => item.id !== req.params.id);
  await saveCheckins(next);
  res.json({ ok: true });
});

app.delete("/api/checkins", async (_req, res) => {
  await saveCheckins([]);
  res.json({ ok: true });
});

app.post("/api/seed", async (_req, res) => {
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
  await saveCheckins(items);
  res.json(items);
});

app.post("/api/checkins/:id/synced", async (req, res) => {
  const checkins = await loadCheckins();
  const item = checkins.find((x) => x.id === req.params.id);
  if (!item) return res.status(404).json({ error: "not_found" });
  item.synced = true;
  await saveCheckins(checkins);
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
