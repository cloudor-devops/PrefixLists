variable "aws_profile" {
  description = "Named AWS profile used for this leaf. Targets the network-shared account (cross-environment)."
  type        = string
  default     = null
}

variable "ram_enabled" {
  type    = bool
  default = false
}

variable "ram_principals" {
  description = "Consumer principals from ALL environments that should see these lists. Typically the Organization ARN so new accounts auto-join."
  type        = list(string)
  default     = []
}

variable "ram_allow_external_principals" {
  type    = bool
  default = true
}
