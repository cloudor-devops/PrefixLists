variable "aws_profile" {
  description = "Named AWS profile used for this leaf. Targets the network-dr account."
  type        = string
  default     = null
}

variable "ram_enabled" {
  type    = bool
  default = false
}

variable "ram_principals" {
  type    = list(string)
  default = []
}

variable "ram_allow_external_principals" {
  type    = bool
  default = true
}
