variable "region" {
  type    = string
  default = "us-east-1"
}

variable "provider_owner_id" {
  description = "AWS account ID that owns the shared prefix lists (the provider account)."
  type        = string
  default     = "492094933642"
}

variable "vpc_id" {
  description = "VPC the example security group is created in."
  type        = string
}
