# Snapmark landing page

A responsive, dependency-free landing page with the current Snapmark icon and an approved native editor preview using a sample project board.

Cloudflare Pages project `snapmark` serves https://snapmark.braksa.xyz/.
Keep `updates/appcast.xml` in the Pages deployment for Sparkle.

Preview from the monorepo root.

```fish
python3 -m http.server 4178 --directory personal/snapmark/site --bind 127.0.0.1
```

Open http://127.0.0.1:4178. The page uses local assets and system fonts. Download links point to the signed, notarized Snapmark 0.1.1 GitHub release for Apple silicon and Intel Macs running macOS 14 or later.

The page has no build step, analytics, forms, or backend.
