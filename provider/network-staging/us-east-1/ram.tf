locals {
  shared_prefix_list_arns = var.ram_enabled ? {
    zpa-connectors = aws_ec2_managed_prefix_list.zpa_connectors.arn
  } : {}
}

resource "aws_ram_resource_share" "this" {
  count = var.ram_enabled ? 1 : 0

  name                      = "managed-prefix-lists-staging-us-east-1"
  allow_external_principals = var.ram_allow_external_principals

  tags = merge(local.common_tags, {
    Name = "managed-prefix-lists-staging-us-east-1"
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
