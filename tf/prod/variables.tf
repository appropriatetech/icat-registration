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

variable "pretix_sender_email" {
  description = "Sender (from) email address for Pretix email configuration (default to the same as pretix_smtp_user)"
  type        = string
  sensitive   = true
  default     = null
}

variable "pretix_image_tag" {
  description = "Docker image tag for pretix/standalone"
  type        = string
  default     = "2026.7.0"
}

variable "pretix_site_url" {
  description = "Public URL for the Pretix instance"
  type        = string
  default     = "https://register.appropriatetech.net"
}

variable "pretix_smtp_host" {
  description = "SMTP server hostname for Pretix email configuration"
  type        = string
  default     = "smtp.gmail.com"
}

variable "pretix_smtp_port" {
  description = "SMTP server port for Pretix email configuration"
  type        = number
  default     = 587
}

variable "pretix_smtp_use_tls" {
  description = "Enable STARTTLS for SMTP"
  type        = string
  default     = "on"
}

variable "pretix_smtp_use_ssl" {
  description = "Enable implicit SSL/TLS for SMTP"
  type        = string
  default     = "off"
}
