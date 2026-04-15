output "prefix_lists" {
  description = "Map of list name -> id/arn/sizing for every managed prefix list in this leaf."
  value = {
    zpa-connectors = {
      id              = aws_ec2_managed_prefix_list.zpa_connectors.id
      arn             = aws_ec2_managed_prefix_list.zpa_connectors.arn
      max_entries     = aws_ec2_managed_prefix_list.zpa_connectors.max_entries
      current_entries = length(aws_ec2_managed_prefix_list.zpa_connectors.entry)
    }
    offices = {
      id              = aws_ec2_managed_prefix_list.offices.id
      arn             = aws_ec2_managed_prefix_list.offices.arn
      max_entries     = aws_ec2_managed_prefix_list.offices.max_entries
      current_entries = length(aws_ec2_managed_prefix_list.offices.entry)
    }
    cpc = {
      id              = aws_ec2_managed_prefix_list.cpc.id
      arn             = aws_ec2_managed_prefix_list.cpc.arn
      max_entries     = aws_ec2_managed_prefix_list.cpc.max_entries
      current_entries = length(aws_ec2_managed_prefix_list.cpc.entry)
    }
    vendor-apis = {
      id              = aws_ec2_managed_prefix_list.vendor_apis.id
      arn             = aws_ec2_managed_prefix_list.vendor_apis.arn
      max_entries     = aws_ec2_managed_prefix_list.vendor_apis.max_entries
      current_entries = length(aws_ec2_managed_prefix_list.vendor_apis.entry)
    }
  }
}

output "ram_share_arn" {
  value = try(aws_ram_resource_share.this[0].arn, null)
}
