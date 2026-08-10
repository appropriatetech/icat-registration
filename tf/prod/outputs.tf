output "cloud_run_service_url" {
  description = "The URL of the deployed Pretix Cloud Run service"
  value       = google_cloud_run_v2_service.icat_pretix.uri
}

output "domain_mapping_records" {
  description = "DNS records required for custom domain mapping (register.appropriatetech.net)"
  value       = google_cloud_run_domain_mapping.pretix_domain.status[0].resource_records
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.inat_pg.connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL instance private IP address"
  value       = google_sql_database_instance.inat_pg.private_ip_address
}

output "redis_host" {
  description = "Memorystore Redis host IP"
  value       = google_redis_instance.inat_redis.host
}

output "redis_port" {
  description = "Memorystore Redis port"
  value       = google_redis_instance.inat_redis.port
}
