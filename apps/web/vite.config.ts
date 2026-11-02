import { defineConfig } from 'vite'
import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import viteReact from '@vitejs/plugin-react'
import { cloudflare } from '@cloudflare/vite-plugin'

export default defineConfig({
  plugins: [
    cloudflare({ viteEnvironment: { name: 'ssr' } }),
    // The site is one page that doesn't change per visitor: build it as static HTML, which Cloudflare serves as is
    tanstackStart({ prerender: { enabled: true } }),
    viteReact(),
  ],
})
