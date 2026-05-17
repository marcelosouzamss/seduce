import type pg from "pg";

export async function bootstrapDb(pool: pg.Pool): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS companions (
      id SERIAL PRIMARY KEY,
      display_name VARCHAR(120) NOT NULL,
      photo_url TEXT NOT NULL,
      gender VARCHAR(32) NOT NULL CHECK (gender IN ('feminino', 'masculino', 'trans')),
      age INT NOT NULL CHECK (age >= 18 AND age <= 99),
      distance_km NUMERIC(8, 2) NOT NULL CHECK (distance_km >= 0),
      has_location BOOLEAN NOT NULL DEFAULT FALSE,
      is_professional BOOLEAN NOT NULL DEFAULT FALSE,
      bio TEXT NOT NULL DEFAULT '',
      city VARCHAR(120) NOT NULL DEFAULT '',
      hourly_rate_brl NUMERIC(10, 2) NOT NULL DEFAULT 350
    );
  `);

  await pool.query(`
    ALTER TABLE companions
      ADD COLUMN IF NOT EXISTS hourly_rate_brl NUMERIC(10, 2)
  `);

  await pool.query(`
    UPDATE companions SET hourly_rate_brl = 350 WHERE hourly_rate_brl IS NULL
  `);

  await pool.query(`
    ALTER TABLE companions
      ALTER COLUMN hourly_rate_brl SET DEFAULT 350
  `);

  await pool.query(`
    ALTER TABLE companions
      ALTER COLUMN hourly_rate_brl SET NOT NULL
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_messages (
      id SERIAL PRIMARY KEY,
      companion_id INT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
      client_key VARCHAR(80) NOT NULL,
      sender VARCHAR(16) NOT NULL CHECK (sender IN ('cliente', 'perfil')),
      body TEXT NOT NULL CHECK (LENGTH(body) >= 1 AND LENGTH(body) <= 2000),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_chat_messages_conv
      ON chat_messages (companion_id, client_key, id);
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_ads (
      id SERIAL PRIMARY KEY,
      client_key VARCHAR(80) NOT NULL,
      title VARCHAR(200) NOT NULL,
      body TEXT NOT NULL CHECK (LENGTH(body) >= 1 AND LENGTH(body) <= 5000),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_user_ads_client ON user_ads (client_key, created_at DESC);
  `);

  await pool.query(`
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS gender VARCHAR(32);
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS age INT;
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS price_brl NUMERIC(10, 2);
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS has_location BOOLEAN;
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS is_professional BOOLEAN;
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS address TEXT;
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS photo_urls JSONB;
  `);
  await pool.query(`
    UPDATE user_ads SET gender = 'feminino' WHERE gender IS NULL;
    UPDATE user_ads SET age = 25 WHERE age IS NULL;
    UPDATE user_ads SET price_brl = 350 WHERE price_brl IS NULL;
    UPDATE user_ads SET has_location = FALSE WHERE has_location IS NULL;
    UPDATE user_ads SET is_professional = FALSE WHERE is_professional IS NULL;
    UPDATE user_ads SET address = '' WHERE address IS NULL;
    UPDATE user_ads SET photo_urls = '[]'::jsonb WHERE photo_urls IS NULL;
  `);
  await pool.query(`
    ALTER TABLE user_ads ALTER COLUMN gender SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN gender SET DEFAULT 'feminino';
    ALTER TABLE user_ads ALTER COLUMN age SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN age SET DEFAULT 25;
    ALTER TABLE user_ads ALTER COLUMN price_brl SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN price_brl SET DEFAULT 350;
    ALTER TABLE user_ads ALTER COLUMN has_location SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN has_location SET DEFAULT FALSE;
    ALTER TABLE user_ads ALTER COLUMN is_professional SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN is_professional SET DEFAULT FALSE;
    ALTER TABLE user_ads ALTER COLUMN address SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN address SET DEFAULT '';
    ALTER TABLE user_ads ALTER COLUMN photo_urls SET NOT NULL;
    ALTER TABLE user_ads ALTER COLUMN photo_urls SET DEFAULT '[]'::jsonb;
  `);
  await pool.query(`
    ALTER TABLE user_ads DROP CONSTRAINT IF EXISTS user_ads_gender_check;
    ALTER TABLE user_ads ADD CONSTRAINT user_ads_gender_check
      CHECK (gender IN ('feminino', 'masculino', 'trans'));
    ALTER TABLE user_ads DROP CONSTRAINT IF EXISTS user_ads_age_check;
    ALTER TABLE user_ads ADD CONSTRAINT user_ads_age_check
      CHECK (age >= 18 AND age <= 99);
  `);

  await pool.query(`
    ALTER TABLE companions ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
    ALTER TABLE companions ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
    ALTER TABLE user_ads ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_payment_methods (
      client_key VARCHAR(80) PRIMARY KEY,
      pix_key TEXT,
      bitcoin_address TEXT,
      credit_card_note TEXT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS ranking_entries (
      id SERIAL PRIMARY KEY,
      author_client_key VARCHAR(80),
      name VARCHAR(120) NOT NULL,
      is_professional BOOLEAN NOT NULL,
      stars SMALLINT NOT NULL CHECK (stars >= 1 AND stars <= 5),
      testimonial TEXT NOT NULL CHECK (LENGTH(testimonial) >= 1 AND LENGTH(testimonial) <= 2000),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_ranking_prof ON ranking_entries (is_professional, created_at DESC);
  `);

  await pool.query(`
    ALTER TABLE companions DROP CONSTRAINT IF EXISTS companions_gender_check
  `);
  await pool.query(`
    UPDATE companions SET gender = 'trans' WHERE gender = 'nao_binario'
  `);
  await pool.query(`
    ALTER TABLE companions ADD CONSTRAINT companions_gender_check
      CHECK (gender IN ('feminino', 'masculino', 'trans'))
  `);

  const count = await pool.query<{ n: string }>(
    "SELECT COUNT(*)::text AS n FROM companions",
  );
  if (Number(count.rows[0]?.n ?? 0) === 0) {
  type SeedRow = readonly [
    string,
    string,
    string,
    number,
    number,
    boolean,
    boolean,
    string,
    string,
    number,
    number | null,
    number | null,
  ];

  const rows: SeedRow[] = [
    [
      "Ana Lucia",
      "https://picsum.photos/seed/seduce1/600/800",
      "feminino",
      28,
      2.4,
      true,
      true,
      "Atendimento com hora marcada. Idiomas: português, inglês.",
      "São Paulo — Centro",
      580,
      -23.5475,
      -46.6361,
    ],
    [
      "Marina Costa",
      "https://picsum.photos/seed/seduce2/600/800",
      "feminino",
      24,
      5.1,
      false,
      true,
      "Perfil novo na plataforma, agenda flexível fins de semana.",
      "São Paulo — Pinheiros",
      420,
      null,
      null,
    ],
    [
      "Juliana Meyers",
      "https://picsum.photos/seed/seduce3/600/800",
      "feminino",
      31,
      8.0,
      true,
      false,
      "Independent, sem espaço físico próprio neste período.",
      "São Paulo — Vila Mariana",
      280,
      -23.5889,
      -46.6384,
    ],
    [
      "Camila Santos",
      "https://picsum.photos/seed/seduce4/600/800",
      "feminino",
      26,
      1.2,
      true,
      true,
      "Experiência com eventos corporativos e viagens curtas.",
      "São Paulo — Itaim",
      750,
      -23.5857,
      -46.6727,
    ],
    [
      "Rafael Moura",
      "https://picsum.photos/seed/seduce5/600/800",
      "masculino",
      29,
      12.6,
      false,
      true,
      "Foco em acompanhamento social e eventos formais.",
      "Santo André",
      490,
      null,
      null,
    ],
    [
      "Diego Alvares",
      "https://picsum.photos/seed/seduce6/600/800",
      "masculino",
      34,
      6.9,
      true,
      false,
      "Perfil iniciante nesta cidade; horários noturnos.",
      "Osasco",
      220,
      -23.5329,
      -46.7916,
    ],
    [
      "Lúcia Ferreira",
      "https://picsum.photos/seed/seduce7/600/800",
      "feminino",
      22,
      18.5,
      false,
      false,
      "Deslocamento por região; sem local próprio.",
      "Guarulhos",
      180,
      null,
      null,
    ],
    [
      "Patrícia Ramos",
      "https://picsum.photos/seed/seduce8/600/800",
      "feminino",
      27,
      3.3,
      true,
      true,
      "Atendimento reservado, verificação de identidade obrigatória.",
      "São Paulo — Moema",
      920,
      -23.6045,
      -46.6729,
    ],
    [
      "Bruno Xavier",
      "https://picsum.photos/seed/seduce9/600/800",
      "masculino",
      30,
      9.9,
      true,
      true,
      "Contratos antecipados e confirmação por mensagem.",
      "São Bernardo",
      650,
      -23.6914,
      -46.5646,
    ],
    [
      "Iris Nolan",
      "https://picsum.photos/seed/seduce10/600/800",
      "trans",
      25,
      4.0,
      true,
      false,
      "Neutralidade na dinâmica do encontro, open to travel curto.",
      "São Paulo — Consolação",
      360,
      -23.5489,
      -46.6603,
    ],
    [
      "Laura Prado",
      "https://picsum.photos/seed/seduce11/600/800",
      "feminino",
      35,
      7.7,
      false,
      true,
      "Mais de 8 anos como profissional; referências mediante solicitação.",
      "São Paulo — Jardins",
      880,
      null,
      null,
    ],
    [
      "Gabriel Norte",
      "https://picsum.photos/seed/seduce12/600/800",
      "masculino",
      27,
      22.0,
      false,
      false,
      "Perfil independente, deslocamento limitado a 15 km.",
      "Taboão da Serra",
      260,
      null,
      null,
    ],
  ];

  const insert = `
    INSERT INTO companions (
      display_name, photo_url, gender, age, distance_km,
      has_location, is_professional, bio, city, hourly_rate_brl,
      latitude, longitude
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
  `;

  for (const r of rows) {
    await pool.query(insert, [...r]);
  }
  }

  const rankCount = await pool.query<{ n: string }>(
    "SELECT COUNT(*)::text AS n FROM ranking_entries",
  );
  if (Number(rankCount.rows[0]?.n ?? 0) === 0) {
    type RankSeed = readonly [string, boolean, number, string];
    const seeds: RankSeed[] = [
      [
        "Marina Costa",
        true,
        5,
        "Pontual e muito atenciosa. Recomendo para eventos corporativos.",
      ],
      ["Bruno Xavier", true, 4, "Comunicação clara e respeito total com combinados."],
      [
        "Cliente verificado #12",
        false,
        5,
        "Respeitador e transparente desde o primeiro contato.",
      ],
      ["Cliente verificado #08", false, 4, "Pagamento em dia e boa comunicação."],
    ];
    const insRank = `
      INSERT INTO ranking_entries (author_client_key, name, is_professional, stars, testimonial)
      VALUES (NULL, $1, $2, $3, $4)
    `;
    for (const [name, isProf, stars, testimonial] of seeds) {
      await pool.query(insRank, [name, isProf, stars, testimonial]);
    }
  }
}
