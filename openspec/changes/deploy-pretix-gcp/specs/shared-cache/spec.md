## Purpose

Provides a shared Memorystore Redis instance for INAT applications, starting with Pretix for caching, session storage, and Celery task queuing.

## ADDED Requirements

### Requirement: Redis instance provisioned in Memorystore
The system SHALL provision a Memorystore for Redis instance named `inat-redis` in the `inat-359418` GCP project, `us-central1` region.

#### Scenario: Instance created
- **WHEN** OpenTofu applies the Memorystore configuration
- **THEN** a Memorystore Redis instance named `inat-redis` exists in `us-central1`

### Requirement: Instance uses smallest viable tier
The system SHALL use the Basic tier with the smallest available memory size (1 GB) to minimize cost.

#### Scenario: Cost-optimized instance
- **WHEN** the instance is provisioned
- **THEN** the tier is `BASIC` and memory size is 1 GB

### Requirement: Instance accessible via private VPC networking
The system SHALL configure the Redis instance on the project's default VPC network, accessible only via private IP from other VPC-connected resources (Cloud Run services).

#### Scenario: Private network connectivity
- **WHEN** the instance is provisioned
- **THEN** it is attached to the default VPC network and has no public endpoint

### Requirement: Connection details available to consuming services
The system SHALL output the Redis instance's host IP and port so that consuming services (Pretix) can construct their connection string.

#### Scenario: Connection info available
- **WHEN** OpenTofu applies the configuration
- **THEN** the Redis host and port are available as OpenTofu outputs or local values for use by other resources
