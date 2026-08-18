locals {
  project_id = "inat-359418"
  region     = "us-central1"

  db_name = "pretix"
  db_user = "pretix"

  pretix_secrets = {
    "pretix-db-password"   = random_password.pretix_db_password.result
    "pretix-django-secret" = random_password.pretix_django_secret.result
    "pretix-smtp-user"     = var.pretix_smtp_user
    "pretix-smtp-pass"     = var.pretix_smtp_pass
  }
}

# ------------------------------------------------------------------------------
# 2. GCP API Enablement
# ------------------------------------------------------------------------------

resource "google_project_service" "compute" {
  project            = local.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = local.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  project            = local.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = local.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudscheduler" {
  project            = local.project_id
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "redis" {
  project            = local.project_id
  service            = "redis.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vpcaccess" {
  project            = local.project_id
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 3. Shared Database (Cloud SQL PostgreSQL)
# ------------------------------------------------------------------------------

resource "google_sql_database_instance" "inat_pg" {
  name             = "inat-pg"
  database_version = "POSTGRES_16"
  region           = local.region

  settings {
    edition = "ENTERPRISE"
    tier    = "db-f1-micro"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = "projects/${local.project_id}/global/networks/default"
      enable_private_path_for_google_cloud_services = true
    }

    disk_autoresize = true

    backup_configuration {
      enabled    = true
      start_time = "03:00"
      location   = "us"
    }
  }

  deletion_protection = true

  depends_on = [
    google_project_service.sqladmin,
    google_project_service.compute
  ]
}

resource "random_password" "pretix_db_password" {
  length  = 32
  special = false
}

resource "google_sql_database" "pretix" {
  name     = local.db_name
  instance = google_sql_database_instance.inat_pg.name
}

resource "google_sql_user" "pretix" {
  name     = local.db_user
  instance = google_sql_database_instance.inat_pg.name
  password = random_password.pretix_db_password.result
}

# ------------------------------------------------------------------------------
# 4. Shared Cache (Memorystore Redis)
# ------------------------------------------------------------------------------

resource "google_redis_instance" "inat_redis" {
  name               = "inat-redis"
  tier               = "BASIC"
  memory_size_gb     = 1
  region             = local.region
  authorized_network = "projects/${local.project_id}/global/networks/default"
  redis_version      = "REDIS_7_0"

  depends_on = [
    google_project_service.redis,
    google_project_service.compute
  ]
}

# ------------------------------------------------------------------------------
# 5. Secret Management
# ------------------------------------------------------------------------------

resource "random_password" "pretix_django_secret" {
  length  = 50
  special = true
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = local.pretix_secrets
  secret_id = each.key
  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "secret_versions" {
  for_each    = local.pretix_secrets
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value
}

# ------------------------------------------------------------------------------
# 6. GCS Buckets and Config Template
# ------------------------------------------------------------------------------

resource "google_storage_bucket" "icat_pretix_config" {
  name     = "icat-pretix-config"
  location = local.region

  soft_delete_policy {
    retention_duration_seconds = 604800
  }
}

resource "google_storage_bucket" "icat_pretix_data" {
  name     = "icat-pretix-data"
  location = local.region

  soft_delete_policy {
    retention_duration_seconds = 604800
  }
}

resource "google_storage_bucket_object" "pretix_cfg" {
  name   = "pretix.cfg"
  bucket = google_storage_bucket.icat_pretix_config.name

  content = templatefile("${path.module}/config/pretix.cfg", {
    site_url      = var.pretix_site_url
    db_name       = local.db_name
    db_user       = local.db_user
    db_password   = random_password.pretix_db_password.result
    db_host       = google_sql_database_instance.inat_pg.private_ip_address
    redis_host    = google_redis_instance.inat_redis.host
    redis_port    = google_redis_instance.inat_redis.port
    django_secret = random_password.pretix_django_secret.result
    mail_from     = coalesce(var.pretix_sender_email, var.pretix_smtp_user)
    mail_host     = var.pretix_smtp_host
    mail_user     = var.pretix_smtp_user
    mail_password = var.pretix_smtp_pass
    mail_port     = var.pretix_smtp_port
    mail_tls      = var.pretix_smtp_use_tls
    mail_ssl      = var.pretix_smtp_use_ssl
  })
}

resource "google_storage_bucket_object" "nginx_conf" {
  name   = "nginx.conf"
  bucket = google_storage_bucket.icat_pretix_config.name

  content = file("${path.module}/config/nginx.conf")
}

# ------------------------------------------------------------------------------
# 7. Service Account and IAM
# ------------------------------------------------------------------------------

resource "google_service_account" "pretix_sa" {
  account_id   = "pretix-sa"
  display_name = "Pretix Service Account"
}

resource "google_project_iam_member" "cloudsql_client" {
  project = local.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.pretix_sa.email}"
}

resource "google_storage_bucket_iam_member" "config_viewer" {
  bucket = google_storage_bucket.icat_pretix_config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.pretix_sa.email}"
}

resource "google_storage_bucket_iam_member" "data_admin" {
  bucket = google_storage_bucket.icat_pretix_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pretix_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "secret_access" {
  for_each  = local.pretix_secrets
  secret_id = google_secret_manager_secret.secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pretix_sa.email}"
}

resource "google_project_iam_member" "run_invoker" {
  project = local.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.pretix_sa.email}"
}

# ------------------------------------------------------------------------------
# 8. VPC Connector
# ------------------------------------------------------------------------------

resource "google_vpc_access_connector" "connector" {
  name          = "pretix-vpc-conn"
  region        = local.region
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  min_instances = 2
  max_instances = 3

  depends_on = [
    google_project_service.vpcaccess,
    google_project_service.compute
  ]
}

# ------------------------------------------------------------------------------
# 9. Cloud Run Service (Pretix)
# ------------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "icat_pretix" {
  name                = "icat-pretix"
  location            = local.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    timeout         = "900s"
    service_account = google_service_account.pretix_sa.email

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      max_instance_count = 4
    }

    containers {
      image   = "pretix/standalone:${var.pretix_image_tag}"
      command = ["/bin/bash"]
      args    = ["-c", "gunicorn pretix.wsgi --bind unix:/tmp/pretix.sock --workers 2 --name pretix & exec nginx -c /etc/pretix/nginx.conf"]

      ports {
        container_port = 80
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "PRETIX_CONFIG_VERSION"
        value = jsonencode({
          pretix_cfg = google_storage_bucket_object.pretix_cfg.md5hash
          nginx_conf = google_storage_bucket_object.nginx_conf.md5hash
        })
      }

      env {
        name  = "PYTHONPATH"
        value = "/pretix/src"
      }

      env {
        name  = "DJANGO_SETTINGS_MODULE"
        value = "production_settings"
      }

      env {
        name  = "HOME"
        value = "/pretix"
      }

      env {
        name  = "DATA_DIR"
        value = "/data/"
      }

      env {
        name  = "PRETIX_PRETIX_TRUST_X_FORWARDED_FOR"
        value = "on"
      }

      env {
        name  = "PRETIX_PRETIX_TRUST_X_FORWARDED_PROTO"
        value = "on"
      }

      volume_mounts {
        name       = "config-files"
        mount_path = "/etc/pretix"
      }

      volume_mounts {
        name       = "data-files"
        mount_path = "/data"
      }

      startup_probe {
        tcp_socket {
          port = 80
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 90
        timeout_seconds       = 5
      }
    }

    volumes {
      name = "config-files"
      gcs {
        bucket    = google_storage_bucket.icat_pretix_config.name
        read_only = true
        mount_options = [
          "uid=15371",
          "gid=15371"
        ]
      }
    }

    volumes {
      name = "data-files"
      gcs {
        bucket    = google_storage_bucket.icat_pretix_data.name
        read_only = false
        mount_options = [
          "uid=15371",
          "gid=15371"
        ]
      }
    }
  }

  depends_on = [
    google_project_service.run,
    google_storage_bucket_object.pretix_cfg
  ]
}

resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.icat_pretix.location
  service  = google_cloud_run_v2_service.icat_pretix.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_domain_mapping" "pretix_domain" {
  name     = "register.appropriatetech.net"
  location = local.region

  metadata {
    namespace = local.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.icat_pretix.name
  }
}

# ------------------------------------------------------------------------------
# 10. Scheduled Tasks (Cloud Run Job + Cloud Scheduler)
# ------------------------------------------------------------------------------

resource "google_cloud_run_v2_job" "icat_pretix_cron" {
  name     = "icat-pretix-cron"
  location = local.region

  template {
    template {
      service_account = google_service_account.pretix_sa.email

      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = "pretix/standalone:${var.pretix_image_tag}"
        command = ["pretix", "cron"]

        resources {
          limits = {
            cpu    = "1000m"
            memory = "2Gi"
          }
        }

        env {
          name  = "PRETIX_CONFIG_VERSION"
          value = jsonencode({
            pretix_cfg = google_storage_bucket_object.pretix_cfg.md5hash
          })
        }

        env {
          name  = "PYTHONPATH"
          value = "/pretix/src"
        }

        env {
          name  = "DJANGO_SETTINGS_MODULE"
          value = "production_settings"
        }

        env {
          name  = "HOME"
          value = "/pretix"
        }

        env {
          name  = "DATA_DIR"
          value = "/data/"
        }

        volume_mounts {
          name       = "config-files"
          mount_path = "/etc/pretix"
        }

        volume_mounts {
          name       = "data-files"
          mount_path = "/data"
        }
      }

      volumes {
        name = "config-files"
        gcs {
          bucket    = google_storage_bucket.icat_pretix_config.name
          read_only = true
          mount_options = [
            "uid=15371",
            "gid=15371"
          ]
        }
      }

      volumes {
        name = "data-files"
        gcs {
          bucket    = google_storage_bucket.icat_pretix_data.name
          read_only = false
          mount_options = [
            "uid=15371",
            "gid=15371"
          ]
        }
      }
    }
  }

  depends_on = [
    google_project_service.run,
    google_storage_bucket_object.pretix_cfg
  ]
}

resource "google_cloud_scheduler_job" "icat_pretix_cron_trigger" {
  name     = "icat-pretix-cron-trigger"
  region   = local.region
  schedule = "15,45 * * * *"

  http_target {
    http_method = "POST"
    uri         = "https://${local.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${local.project_id}/jobs/${google_cloud_run_v2_job.icat_pretix_cron.name}:run"

    oidc_token {
      service_account_email = google_service_account.pretix_sa.email
    }
  }

  depends_on = [
    google_project_service.cloudscheduler
  ]
}
