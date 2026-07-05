import "./App.css";

const features = [
  {
    icon: "🔍",
    title: "Buscar",
    text: "Filtre por distância, idade, perfil e encontre quem combina com você.",
  },
  {
    icon: "🗺️",
    title: "Explorar no mapa",
    text: "Veja anúncios e perfis com localização marcada num mapa interativo.",
  },
  {
    icon: "💬",
    title: "Mensagens",
    text: "Conversas privadas por dispositivo, sem expor dados desnecessários.",
  },
  {
    icon: "📢",
    title: "Anúncios",
    text: "Publique com fotos, descrição e local — apareça na descoberta.",
  },
  {
    icon: "⭐",
    title: "Rankings",
    text: "Avaliações e depoimentos para construir confiança na comunidade.",
  },
  {
    icon: "🎨",
    title: "Seu estilo",
    text: "Personalize o fundo da tela inicial: rosa, azul, verde, noturno e mais.",
  },
] as const;

const steps = [
  { n: "1", title: "Instale o app", text: "Baixe na Google Play e abra Seduce." },
  { n: "2", title: "Configure sua conta", text: "Nome, foto e preferências — tudo no seu aparelho." },
  { n: "3", title: "Descubra e conecte", text: "Busque, converse e publique quando quiser." },
] as const;

/** Link da Play Store — substitua quando o app estiver publicado. */
const PLAY_STORE_URL = "#";

export default function App() {
  return (
    <div className="page">
      <header className="header">
        <a className="logo" href="#">
          Seduce
        </a>
        <nav className="nav">
          <a href="#recursos">Recursos</a>
          <a href="#como">Como funciona</a>
          <a href="#download" className="nav-cta">
            Baixar app
          </a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <div className="hero-glow" aria-hidden />
          <div className="hero-inner">
            <p className="eyebrow">Privacidade · Descoberta · Conexão</p>
            <h1>
              Encontre pessoas
              <span className="hero-accent"> com discrição</span>
            </h1>
            <p className="hero-lead">
              Seduce é o app para explorar perfis, conversar e publicar anúncios — com filtros
              inteligentes, mapa e uma experiência pensada para você.
            </p>
            <div className="hero-actions">
              <a className="btn btn-primary" href={PLAY_STORE_URL}>
                Google Play
              </a>
              <a className="btn btn-ghost" href="#recursos">
                Ver recursos
              </a>
            </div>
            <ul className="hero-stats">
              <li>
                <strong>Mapa</strong>
                <span>Explorar perto de você</span>
              </li>
              <li>
                <strong>Chat</strong>
                <span>Conversas no app</span>
              </li>
              <li>
                <strong>Anúncios</strong>
                <span>Publique com fotos</span>
              </li>
            </ul>
          </div>
          <div className="hero-visual" aria-hidden>
            <div className="phone">
              <div className="phone-notch" />
              <div className="phone-screen">
                <div className="mock-header">Seduce</div>
                <div className="mock-search">Pesquisar nome, cidade…</div>
                <div className="mock-chips">
                  <span>Fem.</span>
                  <span>Masc.</span>
                  <span>Trans.</span>
                </div>
                <div className="mock-grid">
                  <div className="mock-card" />
                  <div className="mock-card" />
                  <div className="mock-card" />
                  <div className="mock-card" />
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="recursos" className="section">
          <div className="section-head">
            <h2>Tudo o que o app oferece</h2>
            <p>Funcionalidades reais do Seduce Mobile, num só lugar.</p>
          </div>
          <div className="feature-grid">
            {features.map((f) => (
              <article key={f.title} className="feature-card">
                <span className="feature-icon" aria-hidden>
                  {f.icon}
                </span>
                <h3>{f.title}</h3>
                <p>{f.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="como" className="section section-alt">
          <div className="section-head">
            <h2>Como funciona</h2>
            <p>Sem login complicado — comece em minutos.</p>
          </div>
          <ol className="steps">
            {steps.map((s) => (
              <li key={s.n}>
                <span className="step-num">{s.n}</span>
                <div>
                  <h3>{s.title}</h3>
                  <p>{s.text}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section id="download" className="cta-band">
          <div className="cta-inner">
            <h2>Pronto para experimentar?</h2>
            <p>Baixe o Seduce na Play Store e configure sua conta em segundos.</p>
            <a className="btn btn-primary btn-lg" href={PLAY_STORE_URL}>
              Disponível no Android
            </a>
            <p className="cta-note">Em breve: mais plataformas e link direto da loja.</p>
          </div>
        </section>
      </main>

      <footer className="footer">
        <span className="logo">Seduce</span>
        <p>© {new Date().getFullYear()} Seduce. Todos os direitos reservados.</p>
      </footer>
    </div>
  );
}
