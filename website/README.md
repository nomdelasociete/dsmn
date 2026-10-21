# dsmn website

Simple landing page for dsmn, “don’t stop me now”, a macOS awake-control utility for local AI coding sessions.

## Local development

```sh
npm ci
npm run dev
```

The landing page includes an interactive menu preview; its timers do not control
the computer. Agent buttons simulate activity, and Stop pauses the activity
animation. Motion also respects the system's reduced-motion preference and the
footer's Pause motion control. The pixel pulse mark matches the heading type;
its menu-bar version briefly traces a beat while the preview timer is active.

Logo assets are in `public/assets/dsmn-pulse*.svg`, with a 180 px touch icon in
`dsmn-pulse-touch.png`. The standalone mark uses a 28 × 20 pixel grid, with an
optically simplified 16 px favicon. These are website assets; the native app
bundle has not been changed.

The 1200 × 630 social card is `public/assets/dsmn-social-preview-pixel.png`.
Its editable source is `scripts/social-preview.html`, served during development
at `/scripts/social-preview.html`. It reuses the site fonts, logo, menu styles,
and a still frame of the dither shader. To re-export, capture that page at
1200 × 630 with device scale factor 1 after `window.socialPreviewReady` is true.
This source page is excluded from the production build. Both Open Graph and
Twitter card metadata reference the exported PNG.

Agentation is available during development for visual feedback. To connect its
MCP server, set `VITE_AGENTATION_ENDPOINT=http://localhost:4747` before starting
Vite. Without an endpoint, feedback can be copied locally.

Development download links proxy the existing release at `https://dsmn.app`.

## Build

```sh
npm run build
npm start
```

`npm start` serves the built `dist/` directory on `PORT`, which works for Railway.
It also exposes the release URLs used by Sparkle and the Download buttons:

```text
/appcast.xml
/download/dsmn-latest.dmg
/download/dsmn-latest.zip
/download/<versioned-archive>.zip
/download/<versioned-archive>.dmg
```

## Deploy on Railway

This directory is part of the dsmn monorepo. See [DEPLOYMENT.md](DEPLOYMENT.md)
for the service settings, migration cutover, rollback, and release upload setup.
Only changes under `website/` trigger automatic website deployments from main.

Railway/Nixpacks can use the included scripts:

- install: `npm ci`
- build: `npm run build`
- start: `npm start`

Point `dsmn.app` at the Railway service once deployed.

## Analytics

The site records first-party analytics through the same Node server:

- `page_view`: browser page views
- `download_click`: clicks on `/download/...` links
- `download`: files actually served by the server, with `metadata.downloadKind`
  set to `site_dmg`, `sparkle_update_zip`, `direct_zip`, or `unknown`
- `appcast_request`: Sparkle update-feed requests

No IP address is stored. The site does not set an analytics cookie or use local
storage for analytics, so events are counted without linking them to a visitor.
Analytics records are pruned after 395 days by default. Override with
`DSMN_ANALYTICS_RETENTION_DAYS` only if the legal page is updated to match.

Attach a Railway Postgres database to provide `DATABASE_URL`. Without
`DATABASE_URL`, local/dev runs write to `.analytics/events.jsonl`; that fallback
is not durable on Railway.

Set `DSMN_METRICS_TOKEN` to expose metrics at `/api/metrics`:

```sh
curl -H "Authorization: Bearer $DSMN_METRICS_TOKEN" https://dsmn.app/api/metrics
curl "https://dsmn.app/api/metrics?token=$DSMN_METRICS_TOKEN"
```

Download metrics are split in `totals`, `last24h`, and each `byDay` row:

- `site_downloads`: DMG downloads from the website download flow
- `update_downloads`: versioned ZIP downloads used by Sparkle updates
- `direct_downloads`: direct ZIP downloads such as `dsmn-latest.zip`
- `unknown_downloads`: other served assets

`appcast_requests` counts update checks. `update_downloads` counts update
archives actually served.

## Feedback

The app can submit feedback to the first-party website backend:

```http
POST /api/feedback
Content-Type: application/json
```

```json
{
  "category": "bug",
  "message": "The helper says it needs approval after I approved it.",
  "email": "optional@example.com",
  "appVersion": "0.1.4",
  "buildNumber": "5",
  "osVersion": "macOS 15.5",
  "diagnostics": {
    "helper": "enabled",
    "status": "inactive"
  }
}
```

Security model:

- no secret is embedded in the macOS app
- the endpoint accepts only JSON bodies up to 8KB
- messages are capped at 4000 characters
- category and email are validated server-side
- diagnostics are opt-in and reduced to primitive key/value fields
- feedback is rate-limited in memory per client IP, but IP addresses are not stored
- no automatic action is triggered by feedback content

With `DATABASE_URL`, feedback is stored in the `feedback_messages` table. Without
Postgres, local/dev runs write to `.feedback/messages.jsonl`.

Feedback records are pruned after 730 days by default. Override with
`DSMN_FEEDBACK_RETENTION_DAYS` only if the legal page is updated to match.

Recent messages are available behind the same admin token as metrics:

```sh
curl -H "Authorization: Bearer $DSMN_METRICS_TOKEN" https://dsmn.app/api/feedback
curl "https://dsmn.app/api/feedback?token=$DSMN_METRICS_TOKEN&limit=25"
```

## Release assets

Use a Railway Bucket for the notarized app archives. Railway Buckets are private,
so the website proxies the files through stable public URLs instead of exposing
bucket URLs directly.

Attach the bucket variables to the website service with Railway reference
variables, not copied static credentials:

```text
AWS_ENDPOINT_URL=${{dsmn-releases.ENDPOINT}}
AWS_ACCESS_KEY_ID=${{dsmn-releases.ACCESS_KEY_ID}}
AWS_SECRET_ACCESS_KEY=${{dsmn-releases.SECRET_ACCESS_KEY}}
AWS_S3_BUCKET_NAME=${{dsmn-releases.BUCKET}}
AWS_DEFAULT_REGION=${{dsmn-releases.REGION}}
```

The server reads release files from `DSMN_RELEASE_PREFIX`, defaulting to
`updates/`. Locally, without bucket variables, it falls back to `dist/updates`.

`AWS_S3_URL_STYLE` is intentionally omitted for the current Railway bucket
because new buckets use virtual-host style and the server defaults to that.
Only set it to `path` for an older bucket whose Credentials tab requires
path-style URLs.

After generating `appcast.xml` in the app repo:

```sh
railway run npm run upload:release -- --dir ../dist/updates
```

The upload command sends:

- `appcast.xml`
- the versioned `.zip` generated by Sparkle
- `dsmn-latest.zip`, used by Sparkle and direct update-archive downloads
- the versioned `.dmg` generated for drag-and-drop installs
- `dsmn-latest.dmg`, used by the website download buttons
