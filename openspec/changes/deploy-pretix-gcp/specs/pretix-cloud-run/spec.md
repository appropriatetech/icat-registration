## Purpose

Deploys the Pretix event registration platform as a Cloud Run service on GCP, with persistent storage via GCS FUSE and database connectivity via Cloud SQL, served at a custom domain.

## ADDED Requirements

### Requirement: Cloud Run service runs the Pretix standalone image
The system SHALL deploy the `pretix/standalone` Docker image as a Cloud Run service in the `inat-359418` GCP project, `us-central1` region. The image tag SHALL be pinned to a specific stable release version (not `latest` or `stable` rolling tags).

#### Scenario: Service deploys with pinned image version
- **WHEN** OpenTofu applies the Cloud Run service configuration
- **THEN** the service runs `pretix/standalone:<pinned-version>` where `<pinned-version>` is a specific release tag (e.g., `2025.3.0`)

### Requirement: Pretix configuration is mounted read-only from GCS
The system SHALL store the rendered `pretix.cfg` configuration file in a GCS bucket and mount it into the container at `/etc/pretix/` using GCS FUSE with read-only access. The mount SHALL use UID/GID `15371` to match the Pretix container's internal user.

#### Scenario: Configuration file accessible inside container
- **WHEN** the Cloud Run service starts
- **THEN** the file `/etc/pretix/pretix.cfg` is readable by the Pretix process (UID 15371)

### Requirement: Pretix data directory is mounted read-write from GCS
The system SHALL mount a GCS bucket at `/data` inside the container using GCS FUSE with read-write access and UID/GID `15371`. This bucket stores event media, ticket PDFs, uploads, and generated files.

#### Scenario: Pretix writes data files
- **WHEN** Pretix generates a PDF invoice or stores an uploaded file
- **THEN** the file persists in the GCS bucket and survives container restarts

### Requirement: Pretix configuration is templated with secrets
The system SHALL use OpenTofu's `templatefile()` function to render `pretix.cfg` from a template, injecting values for database credentials, Redis connection, Django secret key, SMTP credentials, and the site URL. Sensitive values SHALL be sourced from Secret Manager.

#### Scenario: Config template renders with all required values
- **WHEN** OpenTofu renders the `pretix.cfg` template
- **THEN** the rendered file contains valid values for `[database]`, `[redis]`, `[django]`, `[mail]`, and `[pretix]` sections with no placeholder tokens remaining

### Requirement: Cloud Run service connects to Cloud SQL via private networking
The system SHALL configure the Cloud Run service with VPC egress for private IP connectivity to the Cloud SQL PostgreSQL instance, using the Cloud SQL Auth Proxy socket mount or direct private IP connection.

#### Scenario: Pretix connects to PostgreSQL
- **WHEN** the Cloud Run service starts and Pretix initializes
- **THEN** Pretix successfully connects to the PostgreSQL database specified in `pretix.cfg`

### Requirement: Cloud Run service connects to Memorystore Redis
The system SHALL configure the Cloud Run service with VPC egress to reach the Memorystore Redis instance on its private IP. The Redis connection string in `pretix.cfg` SHALL use the Memorystore instance's IP address and port.

#### Scenario: Pretix connects to Redis
- **WHEN** the Cloud Run service starts
- **THEN** Pretix successfully connects to Redis for caching, sessions, and task queuing

### Requirement: Custom domain mapping for the service
The system SHALL configure Cloud Run domain mapping for `register.appropriatetech.net`. The OpenTofu output SHALL include the DNS records required for the domain owner to complete the mapping.

#### Scenario: Domain mapping resource created
- **WHEN** OpenTofu applies the domain mapping configuration
- **THEN** a Cloud Run domain mapping exists for `register.appropriatetech.net` and the required DNS records are available as OpenTofu outputs

### Requirement: Service account with least-privilege IAM
The system SHALL create a dedicated service account for the Pretix Cloud Run service with only the IAM roles necessary to access Cloud SQL, GCS buckets, Secret Manager secrets, and Memorystore.

#### Scenario: Service account has minimum required permissions
- **WHEN** the service account is bound to the Cloud Run service
- **THEN** it has roles for Cloud SQL client, GCS object access (viewer on config bucket, admin on data bucket), Secret Manager secret accessor, and no broader project-level roles beyond what is required

### Requirement: Cloud Run resource configuration optimized for low cost
The system SHALL configure the Cloud Run service with CPU throttling enabled (`cpu_idle = true`), startup CPU boost, and conservative resource limits appropriate for a small-scale conference registration workload.

#### Scenario: Service scales to zero when idle
- **WHEN** no HTTP requests are received for the configured idle period
- **THEN** Cloud Run scales the service to zero instances
