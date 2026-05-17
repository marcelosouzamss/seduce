import type { Express } from "express";
import type pg from "pg";

type CompanionRow = {
  id: number;
  display_name: string;
  photo_url: string;
  gender: string;
  age: number;
  distance_km: string;
  has_location: boolean;
  is_professional: boolean;
  bio: string;
  city: string;
  hourly_rate_brl: string;
  latitude: number | string | null;
  longitude: number | string | null;
};

function toDto(row: CompanionRow) {
  const latRaw = row.latitude;
  const lngRaw = row.longitude;
  const lat =
    latRaw === null || latRaw === undefined ? null : typeof latRaw === "number" ? latRaw : Number(latRaw);
  const lng =
    lngRaw === null || lngRaw === undefined ? null : typeof lngRaw === "number" ? lngRaw : Number(lngRaw);
  return {
    id: row.id,
    displayName: row.display_name,
    photoUrl: row.photo_url,
    gender: row.gender,
    age: row.age,
    distanceKm: Number(row.distance_km),
    hasLocation: row.has_location,
    isProfessional: row.is_professional,
    bio: row.bio,
    city: row.city,
    hourlyRateBrl: Number(row.hourly_rate_brl),
    latitude: lat !== null && Number.isFinite(lat) ? lat : null,
    longitude: lng !== null && Number.isFinite(lng) ? lng : null,
  };
}

function parseBool(value: unknown): boolean | undefined {
  if (value === "true" || value === "1") return true;
  if (value === "false" || value === "0") return false;
  return undefined;
}

export function registerCompanionRoutes(app: Express, pool: pg.Pool): void {
  app.get("/companions", async (req, res) => {
    const maxDistance = req.query.maxDistance;
    const gender = req.query.gender;
    const minAge = req.query.minAge;
    const maxAge = req.query.maxAge;
    const hasLocation = parseBool(req.query.hasLocation);
    const isProfessional = parseBool(req.query.isProfessional);
    const minHourlyRate = req.query.minHourlyRate;
    const maxHourlyRate = req.query.maxHourlyRate;

    const conditions: string[] = ["1=1"];
    const params: unknown[] = [];
    let i = 1;

    if (maxDistance !== undefined && maxDistance !== "") {
      const n = Number(maxDistance);
      if (!Number.isFinite(n) || n < 0) {
        res.status(400).json({ error: "maxDistance inválido" });
        return;
      }
      conditions.push(`distance_km <= $${i++}`);
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
      conditions.push(`hourly_rate_brl >= $${i++}`);
      params.push(n);
    }

    if (maxHourlyRate !== undefined && maxHourlyRate !== "") {
      const n = Number(maxHourlyRate);
      if (!Number.isFinite(n) || n < 0) {
        res.status(400).json({ error: "maxHourlyRate inválido" });
        return;
      }
      conditions.push(`hourly_rate_brl <= $${i++}`);
      params.push(n);
    }

    const sql = `
      SELECT id, display_name, photo_url, gender, age, distance_km,
             has_location, is_professional, bio, city, hourly_rate_brl,
             latitude, longitude
      FROM companions
      WHERE ${conditions.join(" AND ")}
      ORDER BY distance_km ASC, id ASC
    `;

    try {
      const r = await pool.query<CompanionRow>(sql, params);
      res.json(r.rows.map(toDto));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  });

  app.get("/companions/:id", async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      res.status(400).json({ error: "id inválido" });
      return;
    }
    try {
      const r = await pool.query<CompanionRow>(
        `SELECT id, display_name, photo_url, gender, age, distance_km,
                has_location, is_professional, bio, city, hourly_rate_brl,
                latitude, longitude
         FROM companions WHERE id = $1`,
        [id],
      );
      if (r.rowCount === 0) {
        res.status(404).json({ error: "não encontrado" });
        return;
      }
      res.json(toDto(r.rows[0]!));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  });
}
