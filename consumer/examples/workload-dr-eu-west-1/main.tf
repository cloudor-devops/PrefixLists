###############################################################################
# Workload: DR / eu-west-1
#
# Note: the DR region is different from prod's region. The consumer module
# automatically scopes to eu-west-1 because the aws provider is configured
# for eu-west-1. No cross-region leakage possible.
#
# Shared-leaf lists (offices, vendor APIs) only exist in us-east-1 in this
# example, so DR can't use them here — a common real-world pattern is to
# also replicate network-shared into the DR region.
###############################################################################

module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.dr_network_account_id
  name_prefix = "zpa-connectors-"
}

resource "aws_security_group" "app" {
  name        = "app-dr-eu-west-1"
  description = "DR workload SG — ZPA connectors only (region-local)"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each          = toset(module.zpa_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
