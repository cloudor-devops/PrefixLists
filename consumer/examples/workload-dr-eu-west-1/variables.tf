variable "aws_profile" {
  type    = string
  default = null
}

variable "dr_network_account_id" {
  description = "Account that owns network-dr/eu-west-1."
  type        = string
}

variable "vpc_id" {
  type = string
}
