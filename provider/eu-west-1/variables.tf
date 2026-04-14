# RAM settings are hardcoded here rather than passed via -var or .tfvars.
# Edit this file directly and `terraform apply` — no CLI flags, no extra files.

variable "ram_enabled" {
  description = "Create a RAM share and associate every prefix list in this region."
  type        = bool
  default     = false # flip to true when you're ready to share cross-account
}

variable "ram_principals" {
  description = "Account IDs / org ARNs to share the prefix lists with."
  type        = list(string)
  default = [
    # "111111111111",  # workload-account-dev
    # "222222222222",  # workload-account-prod
  ]
}

variable "ram_allow_external_principals" {
  description = "true = allow sharing outside the AWS Org (simplest for a 2-account POC)."
  type        = bool
  default     = true
}
