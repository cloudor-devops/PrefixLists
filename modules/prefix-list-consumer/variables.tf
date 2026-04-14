# Discovery supports two modes — pick one (or combine):
#
#   1. owner_id + name_prefix (RAM-shared lists).
#      Owner-applied tags do NOT propagate across AWS RAM, so tag filters
#      return empty for shared lists. Filter by the provider account ID
#      (+ optional name prefix) instead.
#
#   2. Tag filters (locally-owned lists only).
#      service / environment / group map to tag:Service / tag:Environment /
#      tag:Group. Works only if the lists live in the same account as the
#      consumer — i.e. single-account POC before RAM.

variable "owner_id" {
  description = "Provider AWS account ID. Required for RAM-shared lists; tags don't cross RAM."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Optional prefix-list-name prefix filter (e.g. 'zpa-connectors-'). Combine with owner_id for sharp RAM-shared discovery."
  type        = string
  default     = null
}

variable "service" {
  description = "Service tag to filter on. Only effective for locally-owned lists (tags don't cross RAM)."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment tag to filter on. Local-only."
  type        = string
  default     = null
}

variable "group" {
  description = "Group tag to filter on. Local-only."
  type        = string
  default     = null
}

variable "extra_tag_filters" {
  description = "Additional tag filters, merged into the data source. Local-only."
  type        = map(string)
  default     = {}
}
