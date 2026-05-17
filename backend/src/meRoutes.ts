import type { Express, RequestHandler } from "express";
import type pg from "pg";

import { isUuid } from "./validation.js";

type PayRow = {
  pix_key: string | null;
  bitcoin_address: string | null;
  credit_card_note: string | null;
  updated_at: Date;
};

type ThreadRow = {
  companion_id: number;
  display_name: string;
  photo_url: string;
  last_preview: string;
  updated_at: Date;
};

type RankingRow = {
  id: number;
  name: string;
  is_professional: boolean;
  stars: number;
  testimonial: string;
};

export function registerMeRoutes(app: Express, pool: pg.Pool): void {
  const requireClientKeyQuery: RequestHandler = (req, res, next) => {
    const raw = typeof req.query.clientKey === "string" ? req.query.clientKey.trim() : "";
    if (!isUuid(raw)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }
    (req as Express.Request & { clientKey?: string }).clientKey = raw;
    next();
  };

  const getPaymentMethods: RequestHandler = async (req, res) => {
    const clientKey = (req as Express.Request & { clientKey?: string }).clientKey!;
    try {
      const r = await pool.query<PayRow>(
        `SELECT pix_key, bitcoin_address, credit_card_note, updated_at
         FROM user_payment_methods WHERE client_key = $1`,
        [clientKey],
      );
      if (r.rowCount === 0) {
        res.json({
          pixKey: null,
          bitcoinAddress: null,
          creditCardNote: null,
        });
        return;
      }
      const row = r.rows[0]!;
      res.json({
        pixKey: row.pix_key,
        bitcoinAddress: row.bitcoin_address,
        creditCardNote: row.credit_card_note,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const putPaymentMethods: RequestHandler = async (req, res) => {
    const body = req.body as {
      clientKey?: unknown;
      pixKey?: unknown;
      bitcoinAddress?: unknown;
      creditCardNote?: unknown;
    };
    const clientKey = typeof body.clientKey === "string" ? body.clientKey.trim() : "";
    if (!isUuid(clientKey)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }

    const norm = (v: unknown): string | null => {
      if (v === null || v === undefined) return null;
      if (typeof v !== "string") return null;
      const t = v.trim();
      return t.length === 0 ? null : t;
    };

    const pixKey = norm(body.pixKey);
    const bitcoinAddress = norm(body.bitcoinAddress);
    const creditCardNote = norm(body.creditCardNote);

    if (pixKey !== null && pixKey.length > 500) {
      res.status(400).json({ error: "chave Pix muito longa" });
      return;
    }
    if (bitcoinAddress !== null && bitcoinAddress.length > 500) {
      res.status(400).json({ error: "endereço Bitcoin muito longo" });
      return;
    }
    if (creditCardNote !== null && creditCardNote.length > 120) {
      res.status(400).json({ error: "nota do cartão muito longa" });
      return;
    }

    try {
      await pool.query(
        `INSERT INTO user_payment_methods (client_key, pix_key, bitcoin_address, credit_card_note, updated_at)
         VALUES ($1, $2, $3, $4, NOW())
         ON CONFLICT (client_key) DO UPDATE SET
           pix_key = EXCLUDED.pix_key,
           bitcoin_address = EXCLUDED.bitcoin_address,
           credit_card_note = EXCLUDED.credit_card_note,
           updated_at = NOW()`,
        [clientKey, pixKey, bitcoinAddress, creditCardNote],
      );
      res.json({
        pixKey,
        bitcoinAddress,
        creditCardNote,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const getMessageThreads: RequestHandler = async (req, res) => {
    const clientKey = (req as Express.Request & { clientKey?: string }).clientKey!;
    try {
      const r = await pool.query<ThreadRow>(
        `SELECT c.id AS companion_id,
                c.display_name,
                c.photo_url,
                cm.body AS last_preview,
                cm.created_at AS updated_at
         FROM (
           SELECT companion_id, MAX(id) AS max_id
           FROM chat_messages
           WHERE client_key = $1
           GROUP BY companion_id
         ) t
         JOIN chat_messages cm ON cm.id = t.max_id
         JOIN companions c ON c.id = t.companion_id
         ORDER BY cm.created_at DESC`,
        [clientKey],
      );
      res.json(
        r.rows.map((row) => ({
          companionId: row.companion_id,
          displayName: row.display_name,
          photoUrl: row.photo_url,
          lastPreview: row.last_preview,
          updatedAtMs: row.updated_at.getTime(),
        })),
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const parseOptionalBool = (v: unknown): boolean | undefined => {
    if (v === undefined || v === null || v === "") return undefined;
    const s = Array.isArray(v) ? v[0] : v;
    const str = String(s);
    if (str === "true" || str === "1") return true;
    if (str === "false" || str === "0") return false;
    return undefined;
  };

  const getRankings: RequestHandler = async (req, res) => {
    const filter = parseOptionalBool(req.query.isProfessional);
    try {
      let sql = `SELECT id, name, is_professional, stars, testimonial
                 FROM ranking_entries`;
      const params: unknown[] = [];
      if (filter !== undefined) {
        sql += ` WHERE is_professional = $1`;
        params.push(filter);
      }
      sql += ` ORDER BY created_at DESC, id DESC`;
      const r = await pool.query<RankingRow>(sql, params);
      res.json(
        r.rows.map((row) => ({
          id: String(row.id),
          name: row.name,
          isProfessional: row.is_professional,
          stars: row.stars,
          testimonial: row.testimonial,
        })),
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const postRanking: RequestHandler = async (req, res) => {
    const body = req.body as {
      clientKey?: unknown;
      name?: unknown;
      isProfessional?: unknown;
      stars?: unknown;
      testimonial?: unknown;
    };
    const clientKey = typeof body.clientKey === "string" ? body.clientKey.trim() : "";
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const testimonial = typeof body.testimonial === "string" ? body.testimonial.trim() : "";
    const isProf = body.isProfessional === true || body.isProfessional === false ? body.isProfessional : undefined;
    const starsRaw = body.stars;

    if (!isUuid(clientKey)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }
    if (name.length < 2 || name.length > 120) {
      res.status(400).json({ error: "nome deve ter entre 2 e 120 caracteres" });
      return;
    }
    if (isProf === undefined) {
      res.status(400).json({ error: "isProfessional obrigatório" });
      return;
    }
    const stars = typeof starsRaw === "number" ? starsRaw : Number(starsRaw);
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
      res.status(400).json({ error: "estrelas deve ser inteiro entre 1 e 5" });
      return;
    }
    if (testimonial.length < 4 || testimonial.length > 2000) {
      res.status(400).json({ error: "relato deve ter entre 4 e 2000 caracteres" });
      return;
    }

    try {
      const ins = await pool.query<RankingRow>(
        `INSERT INTO ranking_entries (author_client_key, name, is_professional, stars, testimonial)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, name, is_professional, stars, testimonial`,
        [clientKey, name, isProf, stars, testimonial],
      );
      const row = ins.rows[0]!;
      res.status(201).json({
        entry: {
          id: String(row.id),
          name: row.name,
          isProfessional: row.is_professional,
          stars: row.stars,
          testimonial: row.testimonial,
        },
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  app.get("/me/payment-methods", requireClientKeyQuery, getPaymentMethods);
  app.put("/me/payment-methods", putPaymentMethods);
  app.get("/me/message-threads", requireClientKeyQuery, getMessageThreads);
  app.get("/rankings", getRankings);
  app.post("/rankings", postRanking);
}
