# Very Serious Daily Game Studio

Home page for an imaginary daily game studio by Tuomas Härkönen. Plain static HTML/CSS — no build step.

## Run locally

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Edit

- `index.html` — content and game links (each game is an `<a class="card">`)
- `styles.css` — theme colors live in `:root`
- `images/tuomas.svg` — halftone portrait, generated with `swift tools/halftone.swift <photo.jpg> images/tuomas.svg [columns] [color]` (macOS 14+)

## Deploy

Works on any static host (Vercel, Netlify, GitHub Pages). On Vercel: `vercel` for a preview, `vercel --prod` to publish. `.vercelignore` keeps `tools/`, `.claude/` and this README off the live site.
