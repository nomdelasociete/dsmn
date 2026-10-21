# Website deployment

The website, feedback/analytics backend, and download/appcast proxy deploy as
one Railway service. Native macOS releases are signed and uploaded separately;
a website deployment keeps the existing release bucket and database.

## Production service

Use the existing **DSMN Website** project, **production** environment, and
**dsmn-website** service. Preserve its `dsmn.app` domain, Postgres database,
bucket references, and environment variables. Do not copy secret values into Git.

| Setting | Value |
|---|---|
| Repository | `nomdelasociete/dsmn` |
| Branch | `main` |
| Root directory | `/website` |
| Watch paths (repository relative) | `/website/**` |
| Builder | Railpack |
| Build command | `npm ci && npm test && npm run build` |
| Start command | `npm start` |
| Health check | `/healthz`, 120 seconds |

Service settings hold the deployment configuration. Railway's current management
API rejects the deprecated `railway.json` config-file setting. Keep this table
updated when changing the service. Website tests also run in GitHub Actions for
website or website-workflow changes. The production build repeats the tests so
a failing test cannot deploy even when GitHub CI gating is disabled.

## Initial migration

The import is a snapshot of `nomdelasociete/dsmn-website` commit
`8e83b56` (2026-10-21 import). The original repository retains its history.
Only tracked files were imported; local credentials, data, dependencies, and
build output were excluded. Private paths in historical QA notes were removed.
First-party website source follows the root GPL-3.0-only license; font and icon
licenses remain under `public/licenses/` and `public/icons/LICENSE`.

1. Merge the migration PR and confirm its website checks pass. Until then, keep
   production on the old repository; the target folder is absent on main.
2. Review the staged Railway patch. It must contain only this service's source,
   root directory, watch paths, build/start commands, and health-check settings
   (plus CI gating if enabled). Apply the patch after merge.
3. Verify the deployment uses the merged commit and is healthy. Check `/`,
   `/legal.html`, `/healthz`, `/appcast.xml`, and both `/download/dsmn-latest.zip`
   and `/download/dsmn-latest.dmg`. Preserve release version 0.1.48 / 49 during
   the migration. Confirm feedback validation with synthetic invalid input;
   avoid creating production feedback records for a smoke test.
4. On subsequent merges, confirm website changes deploy and native-only changes
   do not. Watch paths restrict automatic GitHub deployments; manual redeploys
   and service configuration changes can still initiate builds.
5. Once production is verified, archive the old repository with a pointer here.

Rollback: reconnect `nomdelasociete/dsmn-website` on main, restore root directory
`/`, and clear the `/website/**` watch filter. The Node build/start commands
work in either location. Keep the same domain, database, bucket, and variables.

## Local development and release uploads

From this directory, run `npm ci`, `npm test`, and `npm run build`.
`npm start` serves the production build; `npm run dev` runs Vite.
Do not set production database or bucket credentials for local tests.

Link each new checkout before using the native release uploader:

```sh
cd website
railway link --project 'DSMN Website' --environment production --service dsmn-website
```

The root `scripts/publish_release.sh` uses this directory by default and expects
its dependencies installed. `DSMN_WEBSITE_DIR` remains an override. Uploading
release archives changes bucket objects; it does not require a website deploy.
