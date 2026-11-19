# Front end

React + TypeScript + Vite, deployed to GitHub Pages by `.github/workflows/pages.yml`.

```bash
npm ci
npm run dev     # http://localhost:5173
npm run build   # outputs dist/
npm run lint    # oxlint
```

Everything in the built bundle is public. Only put public values in `VITE_*`
variables (for example the API URL), never keys or secrets.
