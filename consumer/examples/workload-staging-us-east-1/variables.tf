variable "aws_profile" {
  type    = string
  default = null
}

variable "staging_network_account_id" {
  description = "Account that owns network-staging/us-east-1."
  type        = string
}

variable "shared_network_account_id" {
  description = "Account that owns network-shared/us-east-1."
  type        = string
}

variable "vpc_id" {
  type = string
}
