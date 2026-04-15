###############################################################################
# Workload: prod / us-east-1
#
# This example demonstrates a consumer that pulls from TWO different provider
# leaves — network-prod/us-east-1 (env-specific lists: ZPA, CPC, etc.) and
# network-shared/us-east-1 (cross-env lists: offices, vendor APIs).
#
# The workload's Security Group attaches ingress/egress rules pointing at
# both sets. No hardcoded IDs, no CIDRs — discovery is owner-id + name prefix.
###############################################################################

# Env-specific: ZPA connectors from the prod network account.
module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.prod_network_account_id
  name_prefix = "zpa-connectors-"
}

# Env-specific: CPC endpoints from the prod network account.
module "cpc_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.prod_network_account_id
  name_prefix = "cpc-endpoints-"
}

# Cross-env: office IPs from the shared network account.
module "offices_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.shared_network_account_id
  name_prefix = "offices-corp-"
}

# Cross-env: vendor API whitelist for egress rules.
module "vendor_apis_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.shared_network_account_id
  name_prefix = "vendor-apis-"
}

resource "aws_security_group" "app" {
  name        = "app-prod-us-east-1"
  description = "Prod workload — ingress from ZPA/CPC/Offices, egress to vendor APIs"
  vpc_id      = var.vpc_id
}

# --- ingress ---

resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each          = toset(module.zpa_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ZPA ingress"
}

resource "aws_vpc_security_group_ingress_rule" "cpc" {
  for_each          = toset(module.cpc_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "CPC endpoint ingress"
}

resource "aws_vpc_security_group_ingress_rule" "offices_ssh" {
  for_each          = toset(module.offices_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "Office SSH ingress"
}

# --- egress ---

resource "aws_vpc_security_group_egress_rule" "vendor_apis" {
  for_each          = toset(module.vendor_apis_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Egress to approved vendor APIs"
}

output "prefix_lists_attached" {
  value = {
    zpa         = module.zpa_prefix_lists.ids
    cpc         = module.cpc_prefix_lists.ids
    offices     = module.offices_prefix_lists.ids
    vendor_apis = module.vendor_apis_prefix_lists.ids
  }
}
