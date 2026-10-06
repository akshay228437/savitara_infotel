variable "project_name" {
  description = "Project name prefix for resource naming and tagging"
  type        = string
  default     = "clouddocs"
}

variable "environment" {
  description = "Environment identifier (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "kms_key_arn" {
  description = "Optional KMS Key ARN for server-side encryption at rest. If empty, AES256 is used."
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Allow deletion of all objects in bucket upon terraform destroy (useful for lab teardown)"
  type        = bool
  default     = false
}
