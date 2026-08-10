## Why

INAT needs a conference registration tool for the International Conference on Appropriate Technology (ICAT) that supports both online payments (Stripe) and bank transfers with invoice generation — critical for participants from countries where Stripe is unavailable (e.g., Zimbabwe, Sudan). Pretix, an open-source event registration platform, handles both payment methods natively, generates PDF invoices, supports custom registration questions, and provides an embeddable widget for static conference websites.

Self-hosting Pretix on GCP keeps costs low (no per-ticket platform fees) while following the same infrastructure patterns already established for OJS in the `inat-pkp-ojs` repository. The hosted Pretix option remains a future fallback if a non-developer volunteer takes over.

## What Changes

- **Add OpenTofu configuration** to deploy the `pretix/standalone` Docker image to Cloud Run in the existing `inat-359418` GCP project
- **Provision a shared Cloud SQL PostgreSQL instance** (`inat-pg`) that Pretix uses immediately and OJS can migrate to later
- **Provision a Memorystore Redis instance** (`inat-redis`) for Pretix's cache, session store, and Celery task queue
- **Create GCS buckets** for Pretix config files (read-only mount) and persistent data files (read-write mount)
- **Template `pretix.cfg`** using OpenTofu's `templatefile()` function with secrets from Secret Manager
- **Set up Cloud Scheduler + Cloud Run Job** to run `pretix cron` on an hourly schedule
- **Configure Cloud Run domain mapping** for `register.appropriatetech.net`
- **Store all secrets** (database password, Django secret key, SMTP credentials) in Secret Manager

## Capabilities

### New Capabilities
- `pretix-cloud-run`: OpenTofu configuration for deploying the Pretix Docker container as a Cloud Run service with GCS FUSE data mounts, Cloud SQL connectivity, and domain mapping
- `shared-database`: Shared Cloud SQL PostgreSQL instance (`inat-pg`) provisioned for cross-application use within the INAT GCP project
- `shared-cache`: Memorystore Redis instance (`inat-redis`) provisioned for cross-application use within the INAT GCP project
- `pretix-scheduled-tasks`: Cloud Run Job + Cloud Scheduler configuration for running Pretix's periodic maintenance tasks

### Modified Capabilities
_(none — this is a new deployment in a fresh repository)_

## Impact

- **GCP project `inat-359418`**: New resources — Cloud SQL PostgreSQL instance, Memorystore Redis instance, Cloud Run service, Cloud Run job, GCS buckets, Secret Manager secrets, Cloud Scheduler job, service account, domain mapping
- **DNS**: Requires a CNAME or A record for `register.appropriatetech.net` pointing to the Cloud Run service
- **Cost**: Cloud SQL (db-f1-micro ~$7/mo), Memorystore (basic-M1 1GB ~$6/mo), Cloud Run (pay-per-use, likely <$5/mo at conference scale), GCS (negligible), Secret Manager (negligible) — estimated **~$18–25/month baseline**
- **Existing OJS deployment**: No changes required now; the Cloud SQL instance is named `inat-pg` (vs. OJS's existing `pkp-ojs`) to eventually become a shared resource
