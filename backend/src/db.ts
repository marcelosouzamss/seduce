import pg from "pg";

const { Pool } = pg;

export function createPool(databaseUrl?: string): pg.Pool {
  const url = databaseUrl ?? process.env.DATABASE_URL;
  if (!url) {
    throw new Error("DATABASE_URL is not set");
  }
  return new Pool({
    connectionString: url,
    max: 10,
  });
}
