import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// base './' makes asset paths relative, so the same build works at
// https://<user>.github.io/<repo>/ and on a custom domain.
export default defineConfig({
  base: './',
  plugins: [react()],
})
