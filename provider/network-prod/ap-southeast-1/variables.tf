variable "aws_profile" {
  description = "Named AWS profile used for this leaf. Targets the network-prod account."
  type        = string
  default     = null
}

variable "ram_enabled" {
  description = "Create a RAM share and associate every prefix list in this region."
  type        = bool
  default     = false
}

variable "ram_principals" {
  description = "Account IDs / org ARNs to share the prefix lists with."
  type        = list(string)
  default     = []
}

variable "ram_allow_external_principals" {
  type    = bool
  default = true
}
