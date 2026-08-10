## Purpose

Runs Pretix's periodic maintenance tasks (order expiration, email sending, cleanup) on a schedule via Cloud Run Jobs triggered by Cloud Scheduler.

## ADDED Requirements

### Requirement: Cloud Run Job executes `pretix cron`
The system SHALL define a Cloud Run Job that runs the `pretix cron` command inside the `pretix/standalone` container image. The job SHALL have the same environment variables, volume mounts, VPC connectivity, and service account as the main Pretix Cloud Run service.

#### Scenario: Cron job executes successfully
- **WHEN** the Cloud Run Job is triggered
- **THEN** the `pretix cron` command runs to completion inside a container with full access to the Pretix configuration, database, Redis, and data directory

### Requirement: Cloud Scheduler triggers cron job hourly
The system SHALL create a Cloud Scheduler job that triggers the Cloud Run Job on an hourly schedule (`0 * * * *`). The scheduler job SHALL authenticate as the Pretix service account.

#### Scenario: Hourly trigger configured
- **WHEN** OpenTofu applies the Cloud Scheduler configuration
- **THEN** a scheduler job exists with cron expression `0 * * * *` targeting the Cloud Run Job's execution endpoint

### Requirement: Cron job uses same container image as the service
The system SHALL ensure the Cloud Run Job references the same pinned `pretix/standalone` image version as the main Cloud Run service, so that cron tasks run against the same application version.

#### Scenario: Image version consistency
- **WHEN** the Cloud Run Job and Cloud Run Service configurations are applied
- **THEN** both reference the same `pretix/standalone:<version>` image tag
