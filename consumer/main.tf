###############################################################################
# BEFORE: inline CIDRs maintained by us (what we're refactoring away from)
###############################################################################
# resource "aws_security_group_rule" "zpa_ingress" {
#   type              = "ingress"
#   from_port         = 443
#   to_port           = 443
#   protocol          = "tcp"
#   security_group_id = aws_security_group.app.id
#   cidr_blocks       = [
#     "10.30.1.0/32",  # zpa-connector-prod-us-east-1-a  <- drifts, nobody owns
#     "10.30.2.0/32",  # zpa-connector-prod-us-east-1-b
#   ]
# }
###############################################################################
# AFTER: owner_id + name_prefix discovery across AWS RAM.
#
# Owner-applied tags do NOT propagate across RAM, so we filter by the provider
# account's owner-id + a name-prefix. Region is still implicit (API is
# region-scoped).
###############################################################################

module "zpa_prefix_lists" {
  source      = "../modules/prefix-list-consumer"
  owner_id    = var.provider_owner_id
  name_prefix = "zpa-connectors-"
}

module "office_prefix_lists" {
  source      = "../modules/prefix-list-consumer"
  owner_id    = var.provider_owner_id
  name_prefix = "offices-corp-"
}

resource "aws_security_group" "app" {
  name        = "app-prefix-list-demo"
  description = "Example workload SG consuming managed prefix lists (RAM-shared)"
  vpc_id      = var.vpc_id
}

# One rule per prefix list (SGs do not accept multiple prefix_list_ids per rule).
resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each = toset(module.zpa_prefix_lists.ids)

  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ZPA ingress via managed prefix list ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "office" {
  for_each = toset(module.office_prefix_lists.ids)

  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "Office SSH ingress via managed prefix list ${each.value}"
}

output "attached_prefix_lists" {
  value = {
    zpa    = module.zpa_prefix_lists.details
    office = module.office_prefix_lists.details
  }
}
