# Website deployment

Production is the Cloudflare Worker `dsmn-website` on account NOM DE LA SOCIETE
(`0a0c8c3111c01831f0604c9ad662706b`). `dsmn.app` is a Worker custom domain.
D1 database `dsmn` holds analytics and feedback. R2 bucket `dsmn-releases`
holds the appcast and downloads. Do not copy secret values into Git.

A push to `main` that changes `website/**` or `.github/workflows/website.yml`
runs `.github/workflows/website.yml`. The workflow tests, builds, and runs
`npx wrangler deploy`. A push that changes neither path does not deploy the site.

Deploy by hand from this directory with the same commands:

```sh
npm ci && npm test && npm run build
npx wrangler deploy
```

Run that from `website/`. Do not run `cloudflare deploy` from the repo root or
from here. It scaffolds a different Worker. `wrangler.jsonc` already contains
the account id. Non-interactive shells also need `CLOUDFLARE_ACCOUNT_ID` and
`CLOUDFLARE_API_TOKEN`.

## Local development

`npm run dev` runs Vite. `npm start` serves the production build with the Node
server. Do not point local tests at the production D1 database or R2 bucket.

## Release uploads

`scripts/publish_release.sh` uploads the appcast, zip, and dmg to R2. It reads
`~/.dsmn/r2-releases.env` unless `DSMN_R2_ENV` points at another file. Mode
600. Required variables:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ENDPOINT_URL=https://0a0c8c3111c01831f0604c9ad662706b.r2.cloudflarestorage.com
AWS_S3_BUCKET_NAME=dsmn-releases
AWS_DEFAULT_REGION=auto
AWS_S3_URL_STYLE=path
```

That file holds an R2 credential for the NOM DE LA SOCIETE account. An upload
does not need a Worker deploy. Sparkle and the website keep
`https://dsmn.app/appcast.xml` and `https://dsmn.app/download/`.
