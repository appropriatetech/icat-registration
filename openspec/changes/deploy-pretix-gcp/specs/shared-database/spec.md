## Purpose

Provides a shared Cloud SQL PostgreSQL instance for INAT applications, starting with Pretix and designed for future use by OJS and other services.

## ADDED Requirements

### Requirement: PostgreSQL instance provisioned in Cloud SQL
The system SHALL provision a Cloud SQL PostgreSQL instance named `inat-pg` in the `inat-359418` GCP project, `us-central1` region, running PostgreSQL 16 or later.

#### Scenario: Instance created with correct engine
- **WHEN** OpenTofu applies the Cloud SQL configuration
- **THEN** a Cloud SQL instance named `inat-pg` exists running PostgreSQL 16+

### Requirement: Instance uses smallest viable machine type
The system SHALL use the `db-f1-micro` machine type (or the smallest available tier) to minimize cost. The instance SHALL have auto-resize storage enabled so it can grow if needed.

#### Scenario: Cost-optimized instance type
- **WHEN** the instance is provisioned
- **THEN** the machine type is `db-f1-micro` with auto-resize storage enabled

### Requirement: Private IP only connectivity
The system SHALL configure the Cloud SQL instance with private IP connectivity only (no public IP) using the project's default VPC network.

#### Scenario: No public IP assigned
- **WHEN** the instance is provisioned
- **THEN** `ipv4_enabled` is `false` and the instance is accessible only via private IP within the VPC

### Requirement: Automated backups enabled
The system SHALL configure automated daily backups with a retention period of at least 7 days and a 30-day final backup on instance deletion.

#### Scenario: Backup policy configured
- **WHEN** the instance is provisioned
- **THEN** automated backups are enabled with at least 7-day retention

### Requirement: Pretix database and user created
The system SHALL create a database named `pretix` and a database user named `pretix` within the `inat-pg` instance. The user password SHALL be generated randomly and stored in Secret Manager.

#### Scenario: Database and user exist
- **WHEN** OpenTofu applies the database configuration
- **THEN** the `pretix` database and `pretix` user exist on the `inat-pg` instance

#### Scenario: Password stored in Secret Manager
- **WHEN** the user is created
- **THEN** the generated password is stored as a Secret Manager secret version accessible by the Pretix service account
