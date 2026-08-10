## 1. Project Scaffolding

- [x] 1.1 Create `tf/prod/provider.tf` with OpenTofu version constraint, Google provider (`~> 7.12`), random provider, and GCS backend (`bucket = "inat-iac"`, `prefix = "tf/state/icat-pretix/prod"`)
- [x] 1.2 Create `tf/prod/variables.tf` with input variable declarations for SMTP credentials (`pretix_smtp_user`, `pretix_smtp_pass`), Pretix image tag (`pretix_image_tag` with a default pinned to the latest stable version), and the site URL
- [x] 1.3 Create `tf/prod/.auto.tfvars` with SMTP credential values (add to `.gitignore`)
- [x] 1.4 Create `tf/prod/main.tf` with `locals` block defining `project_id = "inat-359418"`, `region = "us-central1"`, and Pretix-specific environment value maps
- [x] 1.5 Ensure `.gitignore` excludes `.auto.tfvars`, `.terraform/`, and `*.tfstate*`

## 2. GCP API Enablement

- [x] 2.1 Add `google_project_service` resources for required APIs: `compute.googleapis.com`, `run.googleapis.com`, `sqladmin.googleapis.com`, `secretmanager.googleapis.com`, `cloudscheduler.googleapis.com`, `redis.googleapis.com`, `vpcaccess.googleapis.com`

## 3. Shared Database (Cloud SQL PostgreSQL)

- [x] 3.1 Add `google_sql_database_instance` resource `inat-pg` — PostgreSQL 16, `db-f1-micro`, private IP only on default VPC, auto-resize storage, automated daily backups (7-day retention), 30-day deletion protection backup
- [x] 3.2 Add `random_password` resource for the Pretix database user password (32 chars)
- [x] 3.3 Add `google_sql_database` resource for the `pretix` database on the `inat-pg` instance
- [x] 3.4 Add `google_sql_user` resource for the `pretix` user on the `inat-pg` instance
- [x] 3.5 Add Secret Manager secret and version for `pretix-db-password` with the generated password

## 4. Shared Cache (Memorystore Redis)

- [x] 4.1 Add `google_redis_instance` resource `inat-redis` — Basic tier, 1 GB memory, `us-central1`, default VPC authorized network, Redis version 7.x
- [x] 4.2 Add local values to capture the Redis instance host and port for use in the Pretix config template

## 5. Secret Management

- [x] 5.1 Add `random_password` resource for `pretix-django-secret` (50+ characters)
- [x] 5.2 Add Secret Manager secrets and versions for: `pretix-db-password` (from task 3.5), `pretix-django-secret`, `pretix-smtp-user`, `pretix-smtp-pass`
- [x] 5.3 Add a local map of secret IDs to secret values (following the OJS pattern) for dynamic env block generation

## 6. GCS Buckets and Config Template

- [x] 6.1 Add `google_storage_bucket` resource `icat-pretix-config` — for config file storage, 7-day soft delete policy
- [x] 6.2 Add `google_storage_bucket` resource `icat-pretix-data` — for persistent Pretix data (media, PDFs, uploads), 7-day soft delete policy
- [x] 6.3 Create `tf/prod/config/pretix.cfg` template with `templatefile()` variables for all `[pretix]`, `[database]`, `[redis]`, `[django]`, and `[mail]` sections — using `${variable_name}` syntax for substitution
- [x] 6.4 Add `google_storage_bucket_object` resource to upload the rendered `pretix.cfg` to the config bucket

## 7. Service Account and IAM

- [x] 7.1 Add `google_service_account` resource `pretix-sa` (`pretix-sa@inat-359418.iam.gserviceaccount.com`)
- [x] 7.2 Bind `roles/cloudsql.client` at project level for the service account
- [x] 7.3 Bind `roles/storage.objectViewer` on `icat-pretix-config` bucket
- [x] 7.4 Bind `roles/storage.objectAdmin` on `icat-pretix-data` bucket
- [x] 7.5 Bind `roles/secretmanager.secretAccessor` on each Secret Manager secret
- [x] 7.6 Bind `roles/run.invoker` at project level (for Cloud Scheduler to trigger Cloud Run Jobs)

## 8. VPC Connector

- [x] 8.1 Add `google_vpc_access_connector` resource (or verify one exists from OJS deployment) for Cloud Run to reach private IP services (Cloud SQL, Memorystore) — use Serverless VPC Access or Direct VPC Egress depending on what the OJS deployment uses

## 9. Cloud Run Service (Pretix)

- [x] 9.1 Add `google_cloud_run_v2_service` resource `icat-pretix` — image `pretix/standalone:${var.pretix_image_tag}`, port 80, service account `pretix-sa`, VPC egress for private ranges
- [x] 9.2 Configure resource limits: 1 vCPU (`1000m`), 512Mi memory, `cpu_idle = true`, `startup_cpu_boost = true`
- [x] 9.3 Configure scaling: max 4 instances, concurrency 80
- [x] 9.4 Add GCS FUSE volume mount for config bucket at `/etc/pretix/` (read-only, `uid=15371`, `gid=15371`)
- [x] 9.5 Add GCS FUSE volume mount for data bucket at `/data` (read-write, `uid=15371`, `gid=15371`)
- [x] 9.6 Configure environment variables for `PRETIX_PRETIX_TRUST_X_FORWARDED_FOR=on` and `PRETIX_PRETIX_TRUST_X_FORWARDED_PROTO=on` (Cloud Run sets these headers)
- [x] 9.7 Add startup probe on TCP port 80 with appropriate timeout for Pretix initialization (including auto-migration)
- [x] 9.8 Set the Cloud Run service to allow unauthenticated access (public registration form)
- [x] 9.9 Add `google_cloud_run_domain_mapping` resource for `register.appropriatetech.net`
- [x] 9.10 Update Cloud Run service container command/args to use `pretix web` (Nginx + Gunicorn) for static asset serving

## 10. Scheduled Tasks (Cloud Run Job + Cloud Scheduler)

- [x] 10.1 Add `google_cloud_run_v2_job` resource `icat-pretix-cron` — same image, env vars, volume mounts, VPC egress, and service account as the service. Command: `pretix cron`
- [x] 10.2 Add `google_cloud_scheduler_job` resource `icat-pretix-cron-trigger` — cron expression `0 * * * *`, HTTP target pointing to the Cloud Run Job execution API, OAuth token using the service account

## 11. Outputs

- [x] 11.1 Create `tf/prod/outputs.tf` with outputs for: Cloud Run service URL, domain mapping DNS records (type, name, value), Cloud SQL instance connection name, Redis host/port


## 12. Validation and Initial Deployment

- [x] 12.1 Run `tofu init` to initialize the backend and providers
- [x] 12.2 Run `tofu validate` to check configuration syntax
- [x] 12.3 Run `tofu plan` to review the full resource creation plan
- [x] 12.4 Run `tofu apply` to create all infrastructure
- [x] 12.5 Configure DNS: add the CNAME/A record for `register.appropriatetech.net` using the values from the outputs
- [x] 12.6 Verify SSL certificate provisioning for the custom domain
- [x] 12.7 Create the initial Pretix admin superuser via `gcloud run jobs execute` or `gcloud run services exec` running `pretix createsuperuser`
- [x] 12.8 Access `register.appropriatetech.net` and verify the Pretix admin interface loads
- [x] 12.9 Verify static assets (`/static/pretixcontrol/js/...`, `/static/CACHE/css/...`, `/static/pretixbase/img/...`) return HTTP 200
