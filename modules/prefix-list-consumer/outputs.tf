output "ids" {
  description = "List of Prefix List IDs matching the tag filter. Plug into aws_security_group_rule.prefix_list_ids."
  value       = sort(data.aws_ec2_managed_prefix_lists.filtered.ids)
}

output "by_name" {
  description = "Map of Name tag -> prefix list id."
  value = {
    for id, pl in data.aws_ec2_managed_prefix_list.each :
    pl.name => id
  }
}

output "details" {
  description = "Full details per prefix list (id, name, max_entries, address_family, tags)."
  value = {
    for id, pl in data.aws_ec2_managed_prefix_list.each : pl.name => {
      id             = pl.id
      arn            = pl.arn
      max_entries    = pl.max_entries
      address_family = pl.address_family
      tags           = pl.tags
    }
  }
}
