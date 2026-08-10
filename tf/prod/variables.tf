variable "pretix_smtp_user" {
  description = "SMTP username for Pretix email configuration"
  type        = string
  sensitive   = true
}

variable "pretix_smtp_pass" {
  description = "SMTP password for Pretix email configuration"
  type        = string
  sensitive   = true
}

variable "pretix_image_tag" {
  description = "Docker image tag for pretix/standalone"
  type        = string
  default     = "2025.3.0"
}

variable "pretix_site_url" {
  description = "Public URL for the Pretix instance"
  type        = string
  default     = "https://register.appropriatetech.net"
}
