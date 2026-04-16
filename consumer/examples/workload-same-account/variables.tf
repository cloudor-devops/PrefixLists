variable "vpc_id" {
  description = "VPC where the demo SG is created. Set in terraform.tfvars. When empty (CI plan-only), SG resources are skipped but tag discovery still runs."
  type        = string
  default     = ""
}
