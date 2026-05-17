import type { Express, RequestHandler } from "express";
import multer from "multer";
import type pg from "pg";

import { isUuid } from "./validation.js";

type AdRow = {
  id: number;
  client_key: string;
  title: string;
  body: string;
  created_at: Date;
  gender: string;
  age: number;
  price_brl: string;
  has_location: boolean;
  is_professional: boolean;
  address: string;
  photo_urls: unknown;
  latitude: number | string | null;
  longitude: number | string | null;
};

function parseBool(value: unknown): boolean | undefined {
  if (value === "true" || value === "1") return true;
  if (value === "false" || value === "0") return false;
  return undefined;
}

function normalizePhotoUrls(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.filter((x): x is string => typeof x === "string" && x.length > 0);
  }
  return [];
}

function parseCoord(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value.trim());
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function adDto(r: AdRow) {
  const photos = normalizePhotoUrls(r.photo_urls);
  const cover = photos[0] ?? "";
  const latRaw = r.latitude;
  const lngRaw = r.longitude;
  const latNum =
    latRaw === null || latRaw === undefined ? null : typeof latRaw === "number" ? latRaw : Number(latRaw);
  const lngNum =
    lngRaw === null || lngRaw === undefined ? null : typeof lngRaw === "number" ? lngRaw : Number(lngRaw);
  const latitude = latNum !== null && Number.isFinite(latNum) ? latNum : null;
  const longitude = lngNum !== null && Number.isFinite(lngNum) ? lngNum : null;
  return {
    id: String(r.id),
    title: r.title,
    body: r.body,
    createdAt: r.created_at.toISOString(),
    gender: r.gender,
    age: r.age,
    priceBrl: Number(r.price_brl),
    hasLocation: r.has_location,
    isProfessional: r.is_professional,
    address: r.address,
    photoUrls: photos,
    photoUrl: cover,
    displayName: r.title,
    hourlyRateBrl: Number(r.price_brl),
    distanceKm: 0,
    bio: r.body,
    city: r.address,
    isUserAd: true,
    latitude,
    longitude,
  };
}

function publicAdListDto(r: AdRow) {
  return adDto(r);
}

export function registerAdsRoutes(app: Express, pool: pg.Pool, uploadMw: ReturnType<typeof multer>): void {
  const requireClientKeyQuery: RequestHandler = (req, res, next) => {
    const raw = typeof req.query.clientKey === "string" ? req.query.clientKey.trim() : "";
    if (!isUuid(raw)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }
    (req as Express.Request & { clientKey?: string }).clientKey = raw;
    next();
  };

  const getAds: RequestHandler = async (req, res) => {
    const clientKey = (req as Express.Request & { clientKey?: string }).clientKey!;
    try {
      const r = await pool.query<AdRow>(
        `SELECT id, client_key, title, body, created_at,
                gender, age, price_brl, has_location, is_professional, address, photo_urls,
                latitude, longitude
         FROM user_ads
         WHERE client_key = $1
         ORDER BY created_at DESC, id DESC`,
        [clientKey],
      );
      res.json(r.rows.map(adDto));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const postAd: RequestHandler = async (req, res) => {
    const body = req.body as {
      clientKey?: unknown;
      title?: unknown;
      body?: unknown;
      gender?: unknown;
      age?: unknown;
      priceBrl?: unknown;
      hasLocation?: unknown;
      isProfessional?: unknown;
      address?: unknown;
      photoUrls?: unknown;
      latitude?: unknown;
      longitude?: unknown;
    };
    const clientKey = typeof body.clientKey === "string" ? body.clientKey.trim() : "";
    const title = typeof body.title === "string" ? body.title.trim() : "";
    const text = typeof body.body === "string" ? body.body.trim() : "";
    const genderRaw = typeof body.gender === "string" ? body.gender.trim() : "";
    const address = typeof body.address === "string" ? body.address.trim() : "";

    if (!isUuid(clientKey)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }
    if (title.length < 2 || title.length > 200) {
      res.status(400).json({ error: "título deve ter entre 2 e 200 caracteres" });
      return;
    }
    if (text.length < 4 || text.length > 5000) {
      res.status(400).json({ error: "descrição deve ter entre 4 e 5000 caracteres" });
      return;
    }
    if (!["feminino", "masculino", "trans"].includes(genderRaw)) {
      res.status(400).json({ error: "gênero inválido" });
      return;
    }
    const age = typeof body.age === "number" ? body.age : Number(body.age);
    if (!Number.isInteger(age) || age < 18 || age > 99) {
      res.status(400).json({ error: "idade deve ser entre 18 e 99" });
      return;
    }
    const priceBrl = typeof body.priceBrl === "number" ? body.priceBrl : Number(body.priceBrl);
    if (!Number.isFinite(priceBrl) || priceBrl <= 0 || priceBrl > 1_000_000) {
      res.status(400).json({ error: "preço inválido" });
      return;
    }
    if (body.hasLocation !== true && body.hasLocation !== false) {
      res.status(400).json({ error: "hasLocation deve ser booleano" });
      return;
    }
    if (body.isProfessional !== true && body.isProfessional !== false) {
      res.status(400).json({ error: "isProfessional deve ser booleano" });
      return;
    }
    if (address.length < 3 || address.length > 300) {
      res.status(400).json({ error: "endereço deve ter entre 3 e 300 caracteres" });
      return;
    }

    let latitudeSql: number | null = null;
    let longitudeSql: number | null = null;
    if (body.hasLocation === true) {
      const lat = parseCoord(body.latitude);
      const lng = parseCoord(body.longitude);
      if (lat === null || lng === null) {
        res.status(400).json({
          error:
            "com tem local ativo, envie latitude e longitude válidas (marque no mapa no aplicativo)",
        });
        return;
      }
      if (lat < -90 || lat > 90) {
        res.status(400).json({ error: "latitude inválida" });
        return;
      }
      if (lng < -180 || lng > 180) {
        res.status(400).json({ error: "longitude inválida" });
        return;
      }
      latitudeSql = lat;
      longitudeSql = lng;
    }

    let photoUrls: string[] = [];
    if (Array.isArray(body.photoUrls)) {
      photoUrls = body.photoUrls.filter((x): x is string => typeof x === "string").map((u) => u.trim());
    }
    if (photoUrls.length < 1 || photoUrls.length > 8) {
      res.status(400).json({ error: "inclua entre 1 e 8 fotos (URLs após upload)" });
      return;
    }
    for (const u of photoUrls) {
      if (u.length < 10 || u.length > 1000) {
        res.status(400).json({ error: "URL de foto inválida" });
        return;
      }
    }

    try {
      const ins = await pool.query<AdRow>(
        `INSERT INTO user_ads (
           client_key, title, body, gender, age, price_brl,
           has_location, is_professional, address, photo_urls,
           latitude, longitude
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11, $12)
         RETURNING id, client_key, title, body, created_at,
                   gender, age, price_brl, has_location, is_professional, address, photo_urls,
                   latitude, longitude`,
        [
          clientKey,
          title,
          text,
          genderRaw,
          age,
          priceBrl,
          body.hasLocation,
          body.isProfessional,
          address,
          JSON.stringify(photoUrls),
          latitudeSql,
          longitudeSql,
        ],
      );
      const row = ins.rows[0];
      if (!row) {
        res.status(500).json({ error: "falha ao criar anúncio" });
        return;
      }
      res.status(201).json({ ad: adDto(row) });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const deleteAd: RequestHandler = async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      res.status(400).json({ error: "id inválido" });
      return;
    }
    const clientKey = (req as Express.Request & { clientKey?: string }).clientKey!;
    try {
      const r = await pool.query(`DELETE FROM user_ads WHERE id = $1 AND client_key = $2`, [
        id,
        clientKey,
      ]);
      if (r.rowCount === 0) {
        res.status(404).json({ error: "anúncio não encontrado" });
        return;
      }
      res.status(204).send();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const postPhoto: RequestHandler = async (req, res) => {
    const fk = typeof (req as { body?: { clientKey?: string } }).body?.clientKey === "string"
      ? (req as { body: { clientKey: string } }).body.clientKey.trim()
      : "";
    if (!isUuid(fk)) {
      res.status(400).json({ error: "clientKey inválido" });
      return;
    }
    const file = (req as Express.Request & { file?: Express.Multer.File }).file;
    if (!file) {
      res.status(400).json({ error: "envie o campo file com a imagem" });
      return;
    }
    const host = req.get("host") ?? "localhost:3000";
    const proto = req.protocol;
    const url = `${proto}://${host}/uploads/${file.filename}`;
    res.status(201).json({ url });
  };

  const getPublicAds: RequestHandler = async (req, res) => {
    const minAge = req.query.minAge;
    const maxAge = req.query.maxAge;
    const gender = req.query.gender;
    const hasLocation = parseBool(req.query.hasLocation);
    const isProfessional = parseBool(req.query.isProfessional);
    const minHourlyRate = req.query.minHourlyRate;
    const maxHourlyRate = req.query.maxHourlyRate;

    const conditions: string[] = ["1=1"];
    const params: unknown[] = [];
    let i = 1;

    if (minAge !== undefined && minAge !== "") {
      const n = Number(minAge);
      if (!Number.isInteger(n)) {
        res.status(400).json({ error: "minAge inválido" });
        return;
      }
      conditions.push(`age >= $${i++}`);
      params.push(n);
    }

    if (maxAge !== undefined && maxAge !== "") {
      const n = Number(maxAge);
      if (!Number.isInteger(n)) {
        res.status(400).json({ error: "maxAge inválido" });
        return;
      }
      conditions.push(`age <= $${i++}`);
      params.push(n);
    }

    if (gender !== undefined && gender !== "" && gender !== "todos") {
      const g = String(gender);
      if (!["feminino", "masculino", "trans"].includes(g)) {
        res.status(400).json({ error: "gender inválido" });
        return;
      }
      conditions.push(`gender = $${i++}`);
      params.push(g);
    }

    if (hasLocation !== undefined) {
      conditions.push(`has_location = $${i++}`);
      params.push(hasLocation);
    }

    if (isProfessional !== undefined) {
      conditions.push(`is_professional = $${i++}`);
      params.push(isProfessional);
    }

    if (minHourlyRate !== undefined && minHourlyRate !== "") {
      const n = Number(minHourlyRate);
      if (!Number.isFinite(n) || n < 0) {
        res.status(400).json({ error: "minHourlyRate inválido" });
        return;
      }
      conditions.push(`price_brl >= $${i++}`);
      params.push(n);
    }

    if (maxHourlyRate !== undefined && maxHourlyRate !== "") {
      const n = Number(maxHourlyRate);
      if (!Number.isFinite(n) || n < 0) {
        res.status(400).json({ error: "maxHourlyRate inválido" });
        return;
      }
      conditions.push(`price_brl <= $${i++}`);
      params.push(n);
    }

    try {
      const sql = `
        SELECT id, client_key, title, body, created_at,
               gender, age, price_brl, has_location, is_professional, address, photo_urls,
               latitude, longitude
        FROM user_ads
        WHERE ${conditions.join(" AND ")}
        ORDER BY created_at DESC, id DESC
      `;
      const r = await pool.query<AdRow>(sql, params);
      res.json(r.rows.map(publicAdListDto));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const getPublicAdById: RequestHandler = async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      res.status(400).json({ error: "id inválido" });
      return;
    }
    try {
      const r = await pool.query<AdRow>(
        `SELECT id, client_key, title, body, created_at,
                gender, age, price_brl, has_location, is_professional, address, photo_urls,
                latitude, longitude
         FROM user_ads WHERE id = $1`,
        [id],
      );
      if (r.rowCount === 0) {
        res.status(404).json({ error: "anúncio não encontrado" });
        return;
      }
      res.json(publicAdListDto(r.rows[0]!));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  app.get("/me/ads", requireClientKeyQuery, getAds);
  app.post("/me/ads", postAd);
  app.delete("/me/ads/:id", requireClientKeyQuery, deleteAd);
  app.post("/me/ads/photo", uploadMw.single("file"), postPhoto);
  app.get("/ads/public", getPublicAds);
  app.get("/ads/public/:id", getPublicAdById);
}
