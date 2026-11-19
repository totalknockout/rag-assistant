import './App.css'

const milestones = [
  { name: 'Phase 0: foundations (account, pipeline, smoke test)', done: true },
  { name: 'Milestones 1-4: ingestion pipeline', done: false },
  { name: 'Milestones 5-7: question answering with citations', done: false },
  { name: 'Milestone 8: document-level access control', done: false },
  { name: 'Milestone 9: guardrails and prompt-injection defences', done: false },
  { name: 'Milestone 10: evaluation', done: false },
]

function App() {
  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL

  return (
    <main className="page">
      <header>
        <p className="eyebrow">Portfolio project</p>
        <h1>Enterprise RAG Knowledge Assistant</h1>
        <p className="lead">
          Permission-aware answers from internal documents, with citations. Serverless on AWS,
          front end on GitHub Pages.
        </p>
      </header>

      <section aria-labelledby="progress">
        <h2 id="progress">Build progress</h2>
        <ul className="milestones">
          {milestones.map((m) => (
            <li key={m.name} className={m.done ? 'done' : ''}>
              <span aria-hidden="true">{m.done ? '\u2713' : '\u25CB'}</span> {m.name}
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="config">
        <h2 id="config">Configuration</h2>
        <p>
          API: {apiBaseUrl ? <code>{apiBaseUrl}</code> : 'not configured yet (Milestone 5)'}
        </p>
      </section>
    </main>
  )
}

export default App
