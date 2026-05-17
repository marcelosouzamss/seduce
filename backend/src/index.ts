import "dotenv/config";
import cors from "cors";
import express from "express";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { randomUUID } from "crypto";
import multer from "multer";
import { bootstrapDb } from "./bootstrapDb.js";
import { registerCompanionRoutes } from "./companionRoutes.js";
import { registerChatRoutes } from "./chatRoutes.js";
import { registerMeRoutes } from "./meRoutes.js";
import { registerAdsRoutes } from "./adsRoutes.js";
import { createPool } from "./db.js";

const __dirnameRoot = path.dirname(fileURLToPath(import.meta.url));
const uploadsDir = path.join(__dirnameRoot, "..", "uploads");
fs.mkdirSync(uploadsDir, { recursive: true });

const uploadMw = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadsDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase();
      const safe = [".jpg", ".jpeg", ".png", ".webp"].includes(ext) ? ext : ".jpg";
      cb(null, `${randomUUID()}${safe}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith("image/")) {
      cb(new Error("apenas imagens"));
      return;
    }
    cb(null, true);
  },
});

const app = express();
const pool = createPool();

app.use(cors());
app.use(express.json());
app.use("/uploads", express.static(uploadsDir));
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/health/db", async (_req, res) => {
  try {
    const r = await pool.query("SELECT 1 AS ok, NOW() AS server_time");
    res.json({
      connected: true,
      row: r.rows[0],
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(503).json({ connected: false, error: message });
  }
});

registerCompanionRoutes(app, pool);
registerChatRoutes(app, pool);
registerMeRoutes(app, pool);
registerAdsRoutes(app, pool, uploadMw);
const port = Number(process.env.PORT) || 3000;

async function start() {
  await bootstrapDb(pool);
  app.listen(port, () => {
    console.log(`API http://localhost:${port}`);
  });
}

void start().catch((err) => {
  console.error(err);
  process.exit(1);
});

process.on("SIGTERM", async () => {
  await pool.end();
  process.exit(0);
});
