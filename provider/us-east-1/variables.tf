# RAM settings. Defaults are safe for the first apply (no cross-account
# sharing). Flip via terraform.tfvars (preferred) or by editing defaults here.

variable "ram_enabled" {
  description = "Create a RAM share and associate every prefix list in this region."
  type        = bool
  default     = false
}

variable "ram_principals" {
  description = "Account IDs / org ARNs to share the prefix lists with. Required when ram_enabled=true."
  type        = list(string)
  default     = []
}

variable "ram_allow_external_principals" {
  description = "true = allow sharing outside the AWS Org (needed for standalone accounts not in the same org)."
  type        = bool
  default     = true
}
