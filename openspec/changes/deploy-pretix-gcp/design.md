## Context

This repository mirrors the patterns established in [inat-pkp-ojs](file:///home/mjumbewu/Code/INAT/ojs/inat-pkp-ojs) for deploying containerized applications to Cloud Run in the `inat-359418` GCP project. See proposal.md for motivation.

Key constraints from the existing infrastructure:
- OJS already uses Cloud SQL MySQL (`pkp-ojs` instance), Artifact Registry, Secret Manager, Cloud Scheduler, and a service account with per-resource IAM bindings
- OJS uses GCS FUSE mounts for config (read-only), data files (read-write), and logs
- The GCP project uses the `default` VPC network with private services access configured
- Remote state is stored in the `inat-iac` GCS bucket
- OJS domain mapping uses Cloud Run domain mapping for `conference-submissions.appropriatetech.net`

Pretix-specific constraints from the Docker installation docs:
- The `pretix/standalone` image runs as UID/GID `15371` (not `www-data`/33 like OJS)
- Pretix requires PostgreSQL (not MySQL), Redis, and an SMTP server
- Configuration lives at `/etc/pretix/pretix.cfg` (INI format)
- Persistent data goes to `/data` (media, PDFs, uploads)
- Auto-migration runs on container startup by default
- The `pretix cron` command must be invoked externally on a schedule

## Goals / Non-Goals

**Goals:**
- Deploy a working Pretix instance accessible at `register.appropriatetech.net`
- Follow the same OpenTofu patterns as the OJS deployment for consistency
- Minimize ongoing cost (< $25/month baseline)
- Make the infrastructure reproducible and version-controlled
- Provision shared database and cache infrastructure that OJS can migrate to later

**Non-Goals:**
- Migrating OJS from its existing MySQL Cloud SQL instance to the new PostgreSQL instance (future work)
- Custom Pretix plugins or theme customization (configure through the Pretix admin UI after deployment)
- Configuring Pretix's event settings, registration forms, payment methods, or workshops (done through the admin UI, not infrastructure-as-code)
- HA or multi-region deployment
- Automated backup of GCS data buckets (GCS has built-in versioning/soft-delete; database backups are handled by Cloud SQL)

## Decisions

### 1. Repository structure: `tf/prod/` with config templates

**Decision**: Follow the OJS pattern — `tf/prod/main.tf` as the primary manifest, with `config/pretix.cfg` as a template file rendered via `templatefile()`.

**Alternatives considered**:
- Separate `.tf` files per resource type (e.g., `database.tf`, `run.tf`) — cleaner separation, but the OJS repo uses a single `main.tf` and consistency across INAT repos is more valuable than ideal file organization
- Terragrunt with modules — overkill for a single-environment deployment

**Structure**:
```
tf/prod/
├── main.tf                 # All resources
├── provider.tf             # Terraform/provider config + GCS backend
├── variables.tf            # Input variable declarations
├── .auto.tfvars            # Variable values (gitignored for secrets)
├── config/
│   └── pretix.cfg          # Template for pretix.cfg
└── outputs.tf              # DNS records and connection info
```

### 2. Cloud SQL: New PostgreSQL instance rather than adding to existing MySQL

**Decision**: Create a new Cloud SQL instance `inat-pg` running PostgreSQL 16, separate from the existing `pkp-ojs` MySQL instance. Use `db-f1-micro` tier.

**Rationale**: Pretix requires PostgreSQL. Rather than running two database engines long-term, this instance is designed to eventually replace the MySQL instance when OJS migrates. Naming it `inat-pg` (not `pretix-pg`) signals its shared intent.

**Alternatives considered**:
- Cloud SQL for PostgreSQL `db-g1-small` ($25/mo) — too expensive for initial deployment, can scale up later
- AlloyDB — far too expensive for this scale
- Self-managed PostgreSQL in a container — no automated backups, no managed failover

### 3. Memorystore: Basic tier Redis

**Decision**: Provision a Memorystore for Redis instance (`inat-redis`) on the Basic tier with 1 GB memory.

**Rationale**: Pretix uses Redis for three purposes: Django cache, session storage, and Celery task queue. Basic tier is sufficient — no replication needed for a registration form. 1 GB is the minimum and far more than needed.

**Alternatives considered**:
- Redis in a container on Cloud Run — Cloud Run containers are ephemeral; Redis data would be lost on scale-to-zero
- Memorystore Standard tier (with replication) — unnecessary for a non-critical, low-traffic workload
- Omitting Redis and using database-backed sessions/cache — Pretix requires Redis; it's not optional

### 4. GCS FUSE mounts: Config (read-only) + Data (read-write)

**Decision**: Two GCS buckets, following the OJS pattern:
- `icat-pretix-config` — stores rendered `pretix.cfg`, mounted read-only at `/etc/pretix/`
- `icat-pretix-data` — persistent data, mounted read-write at `/data`

Both mounts use `uid=15371, gid=15371` to match the Pretix container user.

**Alternatives considered**:
- Cloud Run volume with in-memory tmpfs — data wouldn't persist
- Filestore (NFS) — minimum 1 TB, absurdly over-provisioned for config + a few PDFs
- Passing config entirely via environment variables — Pretix supports `PRETIX_SECTION_KEY` env vars, but this would result in dozens of env vars and would diverge from the OJS config-file pattern

### 5. Container image & web server process entrypoint

**Decision**: Use the official `pretix/standalone` image pinned to a specific version tag (`2026.7.0`). First test the standard container `web` entrypoint (`args = ["web"]`). To ensure static files under `/static/` (JS, CSS, SVGs) are served alongside dynamic Python routes, invoke the container with the `web` entrypoint argument (`args = ["web"]`), which launches both Nginx and Gunicorn inside the container. If supervisord/sudo restrictions on Cloud Run block `web`, execute Nginx with an OpenTofu-managed `config/nginx.conf` template file uploaded to the `icat-pretix-config` GCS bucket (mounted at `/etc/pretix/nginx.conf`) alongside Gunicorn.

**Alternatives considered**:
- Running bare Gunicorn directly (`command = ["gunicorn"]`) — Gunicorn only handles dynamic Django views and returns 404 for all `/static/` assets.
- Inline shell string generation with `cat << EOF` — fragile, hard to read, and difficult to maintain compared to an OpenTofu-managed template file in GCS.
- Sidecar Nginx container — If the `web` entrypoint's internal supervisord fails on Cloud Run due to `no-new-privileges` / `sudo` restrictions, add an Nginx sidecar container in the Cloud Run service spec serving `/static/` from an in-memory volume.
- Cloud CDN + GCS bucket for static assets — Requires a Cloud Load Balancer ($18+/mo baseline) and static asset collection scripts on every upgrade. Overkill for a small conference.

**Upgrade path**: Update the image tag in `main.tf` and run `tofu apply`. Pretix auto-migrates on startup.

### 6. SMTP Email Server Endpoint Configuration

**Decision**: Parameterize the `[mail]` section of `pretix.cfg` using OpenTofu variables (`pretix_smtp_host`, `pretix_smtp_port`, `pretix_smtp_use_tls`, `pretix_smtp_use_ssl`) defaulting to `smtp.gmail.com` on port 587 with STARTTLS (`tls = on`).

**Rationale**: `smtp-relay.gmail.com` requires fixed IP whitelist configuration in Google Workspace Admin. `smtp.gmail.com` allows standard password/App Password authentication across Cloud Run's dynamic IP range without connection drops.

### 6. Scheduled tasks: Cloud Run Job + Cloud Scheduler

**Decision**: A single Cloud Run Job running `pretix cron`, triggered hourly by Cloud Scheduler, matching the OJS pattern for `icat-pkp-ojs-scheduled`.

**Rationale**: Pretix recommends running `pretix cron` every 1–15 minutes. Starting with hourly is conservative and sufficient for a small conference. Can be increased to `*/15 * * * *` if needed.

The Cloud Run Job uses the same image, env vars, volume mounts, and service account as the service, ensuring cron tasks see the same config and data.

### 7. Secret management: Secret Manager with per-secret IAM

**Decision**: Store each sensitive value (DB password, Django secret key, SMTP credentials) as a separate Secret Manager secret, with the service account granted `secretAccessor` on each. Secrets are injected as environment variables in Cloud Run (for values Pretix reads from env) or rendered into `pretix.cfg` (uploaded to the config bucket as a GCS object).

**Key secrets**:
- `pretix-db-password` — random, generated by OpenTofu
- `pretix-django-secret` — random, generated by OpenTofu (50+ chars)
- `pretix-smtp-user` — from variables
- `pretix-smtp-pass` — from variables

### 8. SMTP: Gmail SMTP relay

**Decision**: Use `smtp-relay.gmail.com:587` with TLS, consistent with the OJS deployment. The same Google Workspace credentials used for OJS email can be reused.

**Note**: Pretix has its own email queuing (Celery + Redis), so unlike OJS, no custom email relay is needed.

### 9. Remote state: Separate prefix in shared bucket

**Decision**: Use the existing `inat-iac` GCS bucket with prefix `tf/state/icat-pretix/prod` (parallel to OJS's `tf/state/icat-pkp-ojs/prod`).

## Risks / Trade-offs

**[GCS FUSE latency for Pretix data]** → Pretix writes PDFs and media to `/data`. GCS FUSE adds latency compared to local disk. For a small conference with low write volume, this is acceptable. If it becomes a bottleneck, the data bucket could be replaced with a Cloud Run volume backed by a persistent disk.

**[Cloud SQL db-f1-micro performance]** → The micro tier has limited CPU and memory (shared vCPU, 614 MB RAM). Fine for < 1000 registrants. If Pretix becomes sluggish under load, upgrade to `db-g1-small` ($25/mo) with a single `tofu apply` change.

**[Memorystore minimum cost is ~$6/mo even when idle]** → Unlike Cloud SQL (which can be stopped), Memorystore runs continuously. This is the floor cost. If cost is a concern during off-season, the instance could be deleted and recreated, but this loses cached data (acceptable since Redis is ephemeral by nature).

**[Cloud Run cold starts]** → With `cpu_idle = true`, the service scales to zero when unused. First request after idle period takes 10–30 seconds as the Pretix container starts and runs migrations. Acceptable for a registration form that isn't latency-critical. `startup_cpu_boost` mitigates this.

**[Pretix auto-migration on startup]** → The `pretix/standalone` image runs database migrations automatically on container start. This is convenient but means upgrading the image tag could trigger schema changes. Always review Pretix release notes before changing the version tag.

## Migration Plan

This is a greenfield deployment — no migration from an existing system. Deployment sequence:

1. Enable required GCP APIs (if not already enabled)
2. Apply OpenTofu to create all infrastructure
3. Verify DNS records are output, configure `register.appropriatetech.net` DNS
4. Wait for SSL certificate provisioning (Cloud Run managed certs)
5. Access Pretix at `register.appropriatetech.net`, create initial admin superuser via Cloud Run Job or `gcloud run services exec`
6. Configure the first event, payment methods, and registration form through the Pretix admin UI

**Rollback**: `tofu destroy` removes all resources. No external dependencies beyond DNS.
