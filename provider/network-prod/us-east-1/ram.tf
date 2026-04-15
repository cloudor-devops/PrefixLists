# RAM sharing is gated behind var.ram_enabled so Steps 1+2 work without
# cross-account permissions. Flip the var to true once the consumer account
# principals are ready.
#
# NOTE: When adding a new prefix list in this region, also add its ARN to
# local.shared_prefix_list_arns below so it's picked up by the RAM share.

locals {
  shared_prefix_list_arns = var.ram_enabled ? {
    zpa-connectors = aws_ec2_managed_prefix_list.zpa_connectors.arn
    offices        = aws_ec2_managed_prefix_list.offices.arn
    cpc            = aws_ec2_managed_prefix_list.cpc.arn
    vendor-apis    = aws_ec2_managed_prefix_list.vendor_apis.arn
  } : {}
}

resource "aws_ram_resource_share" "this" {
  count = var.ram_enabled ? 1 : 0

  name                      = "managed-prefix-lists-us-east-1"
  allow_external_principals = var.ram_allow_external_principals

  tags = merge(local.common_tags, {
    Name = "managed-prefix-lists-us-east-1"
  })
}

resource "aws_ram_resource_association" "this" {
  for_each = local.shared_prefix_list_arns

  resource_arn       = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = var.ram_enabled ? toset(var.ram_principals) : toset([])

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn
}
