import { HeadContent, Scripts, createRootRoute } from '@tanstack/react-router'
import css from '../site/site.css?url'

const title = "Notch Island: your MacBook's notch, put to work"
const description =
  "Notch Island turns your MacBook's notch into a small workspace: today's tasks, a daily note, what's playing, what you've copied and what your coding agents are up to. Free and open source."

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: 'utf-8' },
      { name: 'viewport', content: 'width=device-width, initial-scale=1' },
      { title },
      { name: 'description', content: description },
      { name: 'theme-color', content: '#E9EEF4' },
      { property: 'og:title', content: title },
      { property: 'og:description', content: description },
      { property: 'og:type', content: 'website' },
    ],
    links: [
      { rel: 'stylesheet', href: css },
      { rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' },
    ],
  }),
  shellComponent: Document,
})

function Document({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
