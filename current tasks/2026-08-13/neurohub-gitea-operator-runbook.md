# Neurohub with Gitea: operator setup and cutover guide

**Date:** 2026-08-13  
**Audience:** the person hosting the central Neurohub service  
**Reference deployment:** one Ubuntu server, Docker Compose, Caddy, PostgreSQL, and Gitea 1.26.4  
**Public names used below:** `git.example.com` and `hub.example.com`

This is the step-by-step companion to the [migration plan](./neurohub-gitea-migration-plan.md).
Replace every `example.com`, email address, and placeholder secret before deploying.

## Read this before installing anything

The infrastructure in this guide can be deployed now, and the implemented Neurohub workspace API
can create, read, revise, share, publish, and archive Gitea-backed workspaces. The complete product
cutover is **not ready yet**: the desktop PKCE/token-storage flow, shared Flutter client, CNL wiring,
artefact releases, and resumable legacy-data migration command still have to land.

Do not make Supabase read-only or direct users to the new service until all release gates in section
12 are checked. Infrastructure setup is reversible; production data cutover is not.

## 1. Choose the production values

Record these before continuing:

```text
Gitea hostname:                 git.example.com
Neurohub API hostname:          hub.example.com
Operator email:                 ops@example.com
SMTP hostname and port:         smtp.example.com:587
SMTP username/from address:     neurohub@example.com
Backup destination:             off-host bucket or backup server
Retention:                      7 daily, 4 weekly, 12 monthly (recommended start)
Maintenance window:             ____________________
Rollback window:                at least one released NMTK version
```

Use separate hostnames rather than a URL subpath. Gitea documents extra proxy requirements and
edge cases for subpaths.

## 2. Prepare DNS, the server, and the firewall

1. Provision a Linux host with persistent storage. A reasonable small starting point is 2 CPU,
   4 GB RAM, and 100 GB SSD, but size disk and object storage from the actual Supabase export plus
   expected growth.
2. Create public DNS `A`/`AAAA` records for both hostnames pointing to the server.
3. Allow inbound TCP 80 and 443. Allow 22 only for operator SSH; Gitea Git-over-SSH on 2222 is
   optional because Neurohub uses HTTPS APIs.
4. Install Docker Engine and the Compose plugin using Docker's supported installation procedure.
5. Confirm both DNS records resolve before starting Caddy, because certificate issuance depends on
   them.

Verify the host:

```bash
docker version
```

```bash
docker compose version
```

## 3. Create the deployment directory and secrets

Run on the server:

```bash
sudo install -d -m 0750 -o "$USER" -g "$USER" /opt/neurohub
```

```bash
cd /opt/neurohub
```

Generate independent values for the PostgreSQL password and metrics token. Run this twice and place
the two different outputs in an operator-only environment file; do not use the literal examples:

```bash
umask 077
openssl rand -hex 32
```

Create `/opt/neurohub/.env`:

```dotenv
GITEA_DOMAIN=git.example.com
NEUROHUB_DOMAIN=hub.example.com

POSTGRES_PASSWORD=replace-with-random-secret-1
GITEA_SECRET_KEY=replace-with-random-secret-2
GITEA_INTERNAL_TOKEN=replace-with-random-secret-3

SMTP_ADDR=smtp.example.com
SMTP_PORT=587
SMTP_USER=neurohub@example.com
SMTP_PASSWORD=replace-with-smtp-password
SMTP_FROM="Neurohub <neurohub@example.com>"

GITEA_METRICS_TOKEN=replace-with-random-secret-4
```

Generate Gitea's secrets with the utility built into the exact image rather than substituting an
arbitrary password:

```bash
docker run --rm docker.gitea.com/gitea:1.26.4-rootless gitea generate secret SECRET_KEY
```

```bash
docker run --rm docker.gitea.com/gitea:1.26.4-rootless gitea generate secret INTERNAL_TOKEN
```

Copy those two outputs into `.env`, then protect it:

```bash
chmod 600 /opt/neurohub/.env
```

Keep `.env` out of Git, support bundles, and backups that are not encrypted.

## 4. Deploy PostgreSQL, Gitea, and TLS

Create `/opt/neurohub/compose.yml`:

```yaml
name: neurohub

services:
  postgres:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: gitea
      POSTGRES_USER: gitea
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea -d gitea"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks: [internal]

  gitea:
    image: docker.gitea.com/gitea:1.26.4-rootless
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      GITEA__database__DB_TYPE: postgres
      GITEA__database__HOST: postgres:5432
      GITEA__database__NAME: gitea
      GITEA__database__USER: gitea
      GITEA__database__PASSWD: ${POSTGRES_PASSWORD}
      GITEA__server__DOMAIN: ${GITEA_DOMAIN}
      GITEA__server__ROOT_URL: https://${GITEA_DOMAIN}/
      GITEA__server__HTTP_PORT: "3000"
      GITEA__server__SSH_DOMAIN: ${GITEA_DOMAIN}
      GITEA__server__SSH_PORT: "2222"
      GITEA__security__INSTALL_LOCK: "true"
      GITEA__security__SECRET_KEY: ${GITEA_SECRET_KEY}
      GITEA__security__INTERNAL_TOKEN: ${GITEA_INTERNAL_TOKEN}
      GITEA__service__DISABLE_REGISTRATION: "false"
      GITEA__service__REQUIRE_SIGNIN_VIEW: "false"
      GITEA__actions__ENABLED: "false"
      GITEA__repository__DISABLED_REPO_UNITS: repo.actions
      GITEA__mailer__ENABLED: "true"
      GITEA__mailer__PROTOCOL: smtp+starttls
      GITEA__mailer__SMTP_ADDR: ${SMTP_ADDR}
      GITEA__mailer__SMTP_PORT: ${SMTP_PORT}
      GITEA__mailer__USER: ${SMTP_USER}
      GITEA__mailer__PASSWD: ${SMTP_PASSWORD}
      GITEA__mailer__FROM: ${SMTP_FROM}
      GITEA__metrics__ENABLED: "true"
      GITEA__metrics__TOKEN: ${GITEA_METRICS_TOKEN}
    volumes:
      - gitea_data:/var/lib/gitea
      - gitea_config:/etc/gitea
    expose: ["3000"]
    networks: [internal, edge]
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:3000/api/v1/version"]
      interval: 10s
      timeout: 5s
      retries: 20

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks: [edge]

networks:
  internal:
    internal: true
  edge:

volumes:
  postgres_data:
    name: neurohub_postgres_data
  gitea_data:
    name: neurohub_gitea_data
  gitea_config:
    name: neurohub_gitea_config
  caddy_data:
    name: neurohub_caddy_data
  caddy_config:
    name: neurohub_caddy_config
```

Create `/opt/neurohub/Caddyfile` initially with only Gitea:

```caddyfile
git.example.com {
    encode zstd gzip
    reverse_proxy gitea:3000
}
```

Validate and start:

```bash
docker compose --env-file .env config --quiet
```

```bash
docker compose --env-file .env up -d --wait
```

Verify that Gitea is pinned and reachable:

```bash
curl --fail --silent https://git.example.com/api/v1/version
```

Expected result includes `1.26.4`. Gitea requires its external `ROOT_URL` to match the proxy URL and
the proxy to preserve host/protocol information; Caddy's standard reverse proxy does that.

## 5. Finish Gitea's administrator setup

Create the first administrator with a generated one-time password:

```bash
docker compose exec -T gitea gitea admin user create --username neurohub-admin --email ops@example.com --admin --random-password --random-password-length 32 --must-change-password
```

Save the printed password in the operator password manager, sign in, change it immediately, and
enable multi-factor authentication. Then:

1. In **Site Administration → Configuration**, verify the displayed root URL and mailer settings.
2. Send a test email. Do not proceed until registration, verification, and password reset mail all
   arrive reliably.
3. Decide whether public self-registration is allowed. If not, set
   `GITEA__service__DISABLE_REGISTRATION=true` after creating/inviting the required accounts, then
   recreate the container.
4. Set explicit repository creation and storage quotas appropriate to the service. In Gitea's
   `app.ini`, set `[repository.release] FILE_MAX_SIZE` and `MAX_FILES` deliberately for large
   artefacts; do this through a managed configuration file rather than guessing an environment name
   for a dotted INI section. Neurohub itself rejects workspace JSON above 10 MB.
5. Confirm Actions is unavailable. Neurohub does not need user-supplied workflow execution.

Apply environment changes with:

```bash
docker compose --env-file .env up -d --wait
```

## 6. Register Neurohub as a public OAuth application

In Gitea, register an OAuth2 application named **Neurohub Desktop**:

1. Open the administrator/user application settings.
2. Set the exact redirect URI to `nmtk://oauth/neurohub`.
3. Mark the application as a **public client** (not confidential).
4. Save and copy the client ID.
5. Do not put a client secret in the desktop app or Neurohub API configuration.

Neurohub requests:

```text
openid profile email read:user write:user write:repository
```

`write:user` is required for creating a repository through `/api/v1/user/repos`;
`write:repository` covers files, visibility, and collaborators. Changing scopes after users approve
the app forces reauthorization, so freeze these before release.

The desktop must use Authorization Code + PKCE with S256, a fresh verifier, and a validated `state`
value. Gitea's public-client flow does not require a client secret.

## 7. Configure and deploy the Neurohub API

Add these values to the Neurohub API's secret environment, not Gitea's public UI:

```dotenv
GITEA_BASE_URL=https://git.example.com
GITEA_OAUTH_CLIENT_ID=replace-with-the-public-client-id
NEUROHUB_OAUTH_REDIRECT_URI=nmtk://oauth/neurohub
GITEA_OAUTH_SCOPES=openid profile email read:user write:user write:repository
NEUROHUB_API_URL=https://hub.example.com
ALLOWED_ORIGINS=https://hub.example.com
ENVIRONMENT=production
```

Release gate: deploy only a Neurohub release that no longer requires its legacy SQL migration at
startup for Gitea-only operation. The current transitional Dockerfile still runs Alembic before
starting, so it is suitable for development validation but is not yet the final database-free
production image described by the migration plan.

When that release exists, add its `neurohub-api` service to `compose.yml`, expose only port 8000 to
the `edge` network, and extend the Caddyfile:

```caddyfile
hub.example.com {
    encode zstd gzip
    reverse_proxy neurohub-api:8000
}
```

Then apply and verify:

```bash
docker compose --env-file .env up -d --wait
```

```bash
curl --fail --silent https://hub.example.com/health
```

```bash
curl --fail --silent https://hub.example.com/api/neurohub/oauth/health
```

The second response must report `status: ok`, `gitea: connected`, and a supported version.

```bash
curl --fail --silent https://hub.example.com/api/neurohub/oauth/config
```

Confirm the response contains the public client ID, exact redirect URI, correct Gitea endpoints,
PKCE required, and no client secret.

## 8. Validate workspace behavior before connecting users

Use two ordinary Gitea accounts, not the administrator. Through the released NMTK app:

1. Sign in as user A.
2. Create a workspace; verify the Gitea repository is private.
3. Verify `.neurohub/manifest.json` and `workspace.nmtk.json` exist in one commit.
4. Save again; verify exactly one additional commit and a changed head SHA.
5. Open the old revision on another client, edit both copies, and save both. The second stale save
   must return a conflict offering reload, save-copy, or resolve; neither copy may disappear.
6. Share read access with user B; user B can open but not save.
7. Change user B to write; user B can save.
8. Revoke user B while their workspace is open; the next remote save must fail without losing their
   local work.
9. Publish explicitly; verify the repository becomes public only after confirmation.
10. Archive it; verify it remains recoverable and is not permanently deleted.

Do not use a global Gitea administrator token for these tests. The Neurohub API must act only with
the signed-in user's OAuth token.

## 9. Back up Gitea and prove restoration

Back up all four authoritative parts: PostgreSQL, repositories/data, configuration/secrets, and any
external attachment/object storage. Copy backups off the Gitea host and encrypt them.

For a consistent local-volume snapshot, create a maintenance window and run:

```bash
cd /opt/neurohub
```

```bash
install -d -m 0700 backups
```

```bash
docker compose stop gitea
```

```bash
docker compose exec -T postgres pg_dump -U gitea -d gitea -Fc > backups/gitea-database.dump
```

```bash
docker run --rm -v neurohub_gitea_data:/source:ro -v /opt/neurohub/backups:/backup alpine:3.22 tar -C /source -czf /backup/gitea-data.tar.gz .
```

```bash
docker run --rm -v neurohub_gitea_config:/source:ro -v /opt/neurohub/backups:/backup alpine:3.22 tar -C /source -czf /backup/gitea-config.tar.gz .
```

```bash
docker compose start gitea
```

```bash
sha256sum backups/* > backups/SHA256SUMS
```

Also save the encrypted `/opt/neurohub/.env`, `compose.yml`, and `Caddyfile`. If attachments use S3,
enable bucket versioning and include that bucket in the same recovery point.

At least once before launch, restore into an empty isolated host, run `git fsck` through Gitea's
doctor tooling, open private repositories as their owners, and compare repository/payload checksums.
Record the restore date and duration. A backup job without a successful empty-host restore does not
satisfy the launch gate.

## 10. Migrate existing Supabase/legacy data

Release gate: this step requires the planned idempotent Neurohub migration command. Do not replace it
with manual repository creation or an improvised SQL script.

Once shipped:

1. Snapshot and export Supabase users, rows, object blobs, visibility, collaborators, versions, and
   SHA-256 values without modifying the source.
2. Run the migration in dry-run mode and resolve every identity collision explicitly.
3. Import to a production-shaped staging Gitea.
4. Read every result back through the Neurohub API and reconcile counts, visibility, permissions,
   sizes, versions, and checksums.
5. Run the same import a second time. It must create zero duplicates.
6. Save and encrypt the source-ID → owner/repository/tag/commit report.
7. Rehearse rollback while both old and new stores are non-production.

The migration release must document its exact command and version. If it cannot resume after an
interruption or produce a machine-readable reconciliation report, it is not ready for production.

## 11. Cut over users

1. Announce the maintenance window and confirm a fresh backup and restore drill.
2. Put Supabase-backed Neurohub writes into read-only mode; leave local NMTK workspaces unaffected.
3. Run the final incremental migration and reconciliation.
4. Enable Gitea storage and OAuth on the central Neurohub API.
5. Test with operator accounts, then a small user cohort, then everyone.
6. Monitor OAuth failures, API latency, repository creation, save conflicts, 403/404 rates,
   checksum failures, quota failures, disk/object-storage capacity, database health, and backup age.
7. Keep Supabase/legacy SQL and blobs read-only for at least one released NMTK version.

Rollback before any new Gitea writes is a configuration switch back to the legacy service. After
new Gitea writes exist, keep both stores read-only and use the migration report/reverse exporter;
never silently point clients back and strand new commits.

## 12. Final release checklist

Do not declare Neurohub fully migrated until every item is checked:

- [ ] Both public hostnames have valid TLS and external monitoring.
- [ ] SMTP registration, verification, invitation, and password reset work.
- [ ] Gitea is pinned to a tested 1.26.x release; Actions is disabled.
- [ ] The OAuth app is public, uses the exact redirect URI, and exposes no secret.
- [ ] Desktop PKCE, secure token storage, refresh, sign-out, and account switching are released.
- [ ] NMTK and CNL use the central `NEUROHUB_API_URL`, not a private Suite API URL.
- [ ] Real-Gitea two-user tests pass for private visibility, sharing, conflicts, and revocation.
- [ ] Artefact tags/releases/attachments and checksum downloads pass if publishing is enabled.
- [ ] Migration dry run, import, reconciliation, and second idempotent run are exact.
- [ ] Backup and empty-host restore have passed with checksum comparison.
- [ ] Cutover and rollback have both been rehearsed.
- [ ] Supabase stays read-only and recoverable through the rollback window.
- [ ] Seven days pass without data loss, permission leakage, or unexplained checksum mismatches.

Only after the rollback window should the old Supabase, PostgreSQL, object-storage, search, and auth
runtime dependencies be removed.

## 13. Routine operations

Daily:

- Check API error rate, free storage, PostgreSQL health, queues, and backup completion.
- Alert immediately on any private-repository visibility mismatch or checksum mismatch.

Weekly:

- Test a random repository and attachment restore.
- Review failed sign-ins, rate limits, permission denials, and workspace conflicts.

Before every Gitea upgrade:

1. Read the release notes and verify Neurohub's minimum/maximum supported version.
2. Restore the latest backup into staging.
3. Upgrade staging using the same image and configuration.
4. Run the complete real-Gitea contract and two-user E2E suites.
5. Back up production, pin the new image tag, deploy, and verify.
6. Keep the previous image and database backup available until the observation window passes.

Official references:

- [Gitea rootless Docker installation](https://docs.gitea.com/1.26/installation/install-with-docker-rootless)
- [Gitea OAuth2 provider and PKCE](https://docs.gitea.com/1.26/development/oauth2-provider)
- [Gitea reverse-proxy requirements](https://docs.gitea.com/1.26/administration/reverse-proxies)
- [Gitea configuration and storage limits](https://docs.gitea.com/administration/config-cheat-sheet)
- [Gitea backup and restore](https://docs.gitea.com/usage/backup-and-restore)
