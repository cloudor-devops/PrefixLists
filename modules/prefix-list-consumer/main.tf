locals {
  # Owner / name filters — work for RAM-shared lists.
  # Tags don't propagate across RAM, so these are the primary path.
  owner_filter = var.owner_id == null ? {} : {
    "owner-id" = var.owner_id
  }
  name_filter = var.name_prefix == null ? {} : {
    "prefix-list-name" = "${var.name_prefix}*"
  }

  # Tag filters — only meaningful for locally-owned lists.
  tag_filters = merge(
    var.service == null ? {} : { Service = var.service },
    var.environment == null ? {} : { Environment = var.environment },
    var.group == null ? {} : { Group = var.group },
    var.extra_tag_filters,
  )

  attribute_filters = merge(local.owner_filter, local.name_filter)
}

# Region is implicit — the AWS API is region-scoped, so any lookup inherently
# returns only lists in the provider's region. Consumers never waste SG quota
# on out-of-region lists.
data "aws_ec2_managed_prefix_lists" "filtered" {
  # Attribute filters (owner-id, prefix-list-name) — work for RAM-shared lists.
  dynamic "filter" {
    for_each = local.attribute_filters
    content {
      name   = filter.key
      values = [filter.value]
    }
  }

  # Tag filters — local-only, silently ignored for RAM-shared lists.
  dynamic "filter" {
    for_each = local.tag_filters
    content {
      name   = "tag:${filter.key}"
      values = [filter.value]
    }
  }
}

data "aws_ec2_managed_prefix_list" "each" {
  for_each = toset(data.aws_ec2_managed_prefix_lists.filtered.ids)
  id       = each.value
}
