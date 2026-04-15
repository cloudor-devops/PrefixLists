###############################################################################
# Workload: staging / us-east-1
#
# Pulls ZPA connectors from network-staging (staging-specific IPs) and
# cross-env offices/vendor-apis from network-shared (same IPs as prod uses).
# This is the core value of the shared leaf: offices don't get maintained
# three times.
###############################################################################

module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.staging_network_account_id
  name_prefix = "zpa-connectors-"
}

module "offices_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.shared_network_account_id
  name_prefix = "offices-corp-"
}

module "vendor_apis_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.shared_network_account_id
  name_prefix = "vendor-apis-"
}

resource "aws_security_group" "app" {
  name        = "app-staging-us-east-1"
  description = "Staging workload — ZPA (staging) + offices/vendor APIs (shared)"
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

resource "aws_vpc_security_group_ingress_rule" "offices_ssh" {
  for_each          = toset(module.offices_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "vendor_apis" {
  for_each          = toset(module.vendor_apis_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
