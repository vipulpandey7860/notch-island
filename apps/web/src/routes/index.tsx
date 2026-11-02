import { createFileRoute } from '@tanstack/react-router'
import { useEffect } from 'react'
import page from '../site/page.html?raw'
import { mountSite } from '../site/site.js'

export const Route = createFileRoute('/')({ component: Home })

// The page is plain markup with its own script: TanStack Start renders it (prerendered to static HTML at build
// time), and site.js brings the island and the demos to life once it's in the browser
function Home() {
  useEffect(mountSite, [])
  return <div dangerouslySetInnerHTML={{ __html: page }} />
}
