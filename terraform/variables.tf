variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project prefix used in all resource names"
  type        = string
  default     = "togglemaster"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "production"
}

# ── EKS ────────────────────────────────────────────────────────────────────

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min" {
  type    = number
  default = 1
}

variable "eks_node_desired" {
  type    = number
  default = 2
}

variable "eks_node_max" {
  type    = number
  default = 4
}

# ── RDS ────────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_username" {
  description = "Master username for all RDS instances"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Master password for all RDS instances"
  type        = string
  sensitive   = true
}

# ── App secrets ────────────────────────────────────────────────────────────

variable "auth_master_key" {
  description = "MASTER_KEY for auth-service admin endpoints"
  type        = string
  sensitive   = true
}

variable "service_api_key" {
  description = "Shared API key for inter-service calls"
  type        = string
  sensitive   = true
}
