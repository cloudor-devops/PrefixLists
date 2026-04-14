variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS profile to use for the consumer account. Leave null to use default credentials / env vars."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment tag to filter prefix lists by (prod/staging/dev)."
  type        = string
  default     = "prod"
}

variable "vpc_id" {
  description = "VPC in the consumer account where the example Security Group is created."
  type        = string
}
