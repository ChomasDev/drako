# Drako landing page

TanStack Start (prerendered to static HTML), Tailwind CSS v4 and Motion.

```sh
pnpm install
pnpm dev      # http://localhost:5173
pnpm build    # static site in dist/client (index.html, sitemap.xml, robots.txt)
```

Before deploying, set the real domain in `src/lib/site.ts` and `public/robots.txt`,
and the download link in `src/components/Closing.tsx`.
