import type { Express, RequestHandler } from "express";
import type pg from "pg";

import { isUuid } from "./validation.js";

type MsgRow = {
  id: number;
  companion_id: number;
  client_key: string;
  sender: string;
  body: string;
  created_at: Date;
};

function toDto(row: MsgRow) {
  return {
    id: row.id,
    companionId: row.companion_id,
    sender: row.sender,
    body: row.body,
    sentAt: row.created_at.toISOString(),
  };
}

export function registerChatRoutes(app: Express, pool: pg.Pool): void {
  const getMessages: RequestHandler = async (req, res) => {
    const cid = Number(req.params.id);
    if (!Number.isInteger(cid) || cid < 1) {
      res.status(400).json({ error: "id da acompanhante inválido" });
      return;
    }

    const clientKeyRaw = typeof req.query.clientKey === "string" ? req.query.clientKey.trim() : "";
    if (!isUuid(clientKeyRaw)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }

    let afterId = 0;
    if (req.query.afterId !== undefined && req.query.afterId !== "") {
      afterId = Number(req.query.afterId);
      if (!Number.isInteger(afterId) || afterId < 0) {
        res.status(400).json({ error: "afterId inválido" });
        return;
      }
    }

    try {
      const exists = await pool.query<{ c: string }>(
        `SELECT COUNT(*)::text AS c FROM companions WHERE id = $1`,
        [cid],
      );
      if (Number(exists.rows[0]?.c ?? 0) < 1) {
        res.status(404).json({ error: "acompanhante não encontrada" });
        return;
      }

      const r = await pool.query<MsgRow>(
        `SELECT id, companion_id, client_key, sender, body, created_at
         FROM chat_messages
         WHERE companion_id = $1 AND client_key = $2 AND id > $3
         ORDER BY id ASC`,
        [cid, clientKeyRaw, afterId],
      );
      res.json(r.rows.map(toDto));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    }
  };

  const postMessage: RequestHandler = async (req, res) => {
    const cid = Number(req.params.id);
    if (!Number.isInteger(cid) || cid < 1) {
      res.status(400).json({ error: "id da acompanhante inválido" });
      return;
    }

    const body = req.body as { clientKey?: unknown; text?: unknown };
    const clientKey =
      typeof body.clientKey === "string" ? body.clientKey.trim() : "";
    const textRaw = typeof body.text === "string" ? body.text.trim() : "";

    if (!isUuid(clientKey)) {
      res.status(400).json({ error: "clientKey inválido (use um UUID)" });
      return;
    }
    if (textRaw.length === 0 || textRaw.length > 2000) {
      res.status(400).json({ error: "mensagem deve ter entre 1 e 2000 caracteres" });
      return;
    }

    const conn = await pool.connect();
    try {
      await conn.query("BEGIN");
      const ex = await conn.query<{ c: string }>(
        `SELECT COUNT(*)::text AS c FROM companions WHERE id = $1`,
        [cid],
      );
      if (Number(ex.rows[0]?.c ?? 0) < 1) {
        await conn.query("ROLLBACK");
        res.status(404).json({ error: "acompanhante não encontrada" });
        return;
      }

      const countBefore = await conn.query<{ c: string }>(
        `SELECT COUNT(*)::text AS c FROM chat_messages
         WHERE companion_id = $1 AND client_key = $2 AND sender = 'cliente'`,
        [cid, clientKey],
      );
      const isFirstCliente = Number(countBefore.rows[0]?.c ?? 0) === 0;

      const ins = await conn.query<MsgRow>(
        `INSERT INTO chat_messages (companion_id, client_key, sender, body)
         VALUES ($1, $2, 'cliente', $3)
         RETURNING id, companion_id, client_key, sender, body, created_at`,
        [cid, clientKey, textRaw],
      );

      let autoReplyRow: MsgRow | null = null;
      if (isFirstCliente) {
        const autoReply = await conn.query<MsgRow>(
          `INSERT INTO chat_messages (companion_id, client_key, sender, body)
           VALUES ($1, $2, 'perfil', $3)
           RETURNING id, companion_id, client_key, sender, body, created_at`,
          [
            cid,
            clientKey,
            "Oi! Recebi sua mensagem. Em breve respondo com mais detalhes.",
          ],
        );
        autoReplyRow = autoReply.rows[0] ?? null;
      }

      await conn.query("COMMIT");

      const out = ins.rows[0]!;
      const messages = autoReplyRow
        ? [toDto(out), toDto(autoReplyRow)]
        : [toDto(out)];

      res.status(201).json({ messages });
    } catch (err) {
      await conn.query("ROLLBACK").catch(() => {});
      const message = err instanceof Error ? err.message : String(err);
      res.status(500).json({ error: message });
    } finally {
      conn.release();
    }
  };

  app.get("/companions/:id/messages", getMessages);
  app.post("/companions/:id/messages", postMessage);
}
