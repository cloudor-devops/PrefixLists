variable "aws_profile" {
  description = "Named AWS profile for the prod workload account."
  type        = string
  default     = null
}

variable "prod_network_account_id" {
  description = "AWS account ID that owns the network-prod/us-east-1 leaf's prefix lists."
  type        = string
}

variable "shared_network_account_id" {
  description = "AWS account ID that owns the network-shared/us-east-1 leaf's prefix lists."
  type        = string
}

variable "vpc_id" {
  description = "VPC in the prod workload account where the example SG is created."
  type        = string
}
