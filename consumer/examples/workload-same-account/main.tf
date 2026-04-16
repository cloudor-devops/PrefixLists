###############################################################################
# Single-account tag-based discovery demo.
#
# The consumer doesn't know any prefix list IDs or account IDs. It just says
# "give me everything tagged Service=ZPA, Environment=prod in this region"
# and AWS returns the matching prefix lists.
#
# This works because provider and consumer are in the SAME AWS account, so
# owner-applied tags are visible to the consumer's data source.
###############################################################################

# --- Discovery by tag ---

module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "ZPA"
  environment = "prod"
}

module "offices_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "Office"
  environment = "prod"
}

module "cpc_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "CPC"
  environment = "prod"
}

module "vendor_apis_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "VendorAPIs"
  environment = "prod"
}

# --- Security Group ---

resource "aws_security_group" "app" {
  name        = "app-tag-discovery-demo"
  description = "Tag-based discovery demo - all prefix lists found by Service + Environment tags"
  vpc_id      = var.vpc_id
}

# --- Ingress rules ---

resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each          = toset(module.zpa_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ZPA ingress (tag-discovered)"
}

resource "aws_vpc_security_group_ingress_rule" "offices_ssh" {
  for_each          = toset(module.offices_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "Office SSH ingress (tag-discovered)"
}

resource "aws_vpc_security_group_ingress_rule" "cpc" {
  for_each          = toset(module.cpc_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "CPC ingress (tag-discovered)"
}

# --- Egress rules ---

resource "aws_vpc_security_group_egress_rule" "vendor_apis" {
  for_each          = toset(module.vendor_apis_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Vendor API egress (tag-discovered)"
}

# --- Outputs ---

output "discovered_prefix_lists" {
  description = "What the tag filter found — these IDs were never hardcoded anywhere."
  value = {
    zpa         = module.zpa_prefix_lists.details
    offices     = module.offices_prefix_lists.details
    cpc         = module.cpc_prefix_lists.details
    vendor_apis = module.vendor_apis_prefix_lists.details
  }
}
