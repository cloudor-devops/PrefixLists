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
# AFTER: tag-based dynamic discovery (the spec's original design).
#
# Consumer filters by Service / Environment / Group tags. No hardcoded pl-xxx
# IDs, no CIDRs. Region is implicit — the aws provider's region scopes the
# lookup, so cross-region leakage is impossible.
#
# Important caveat for cross-account RAM: AWS does not propagate the owner's
# tags to consumers. If the prefix lists are owned by a different account and
# shared via RAM, tag-based filters will return empty on the consumer side.
# For that scenario the module also supports owner_id + name_prefix mode —
# pass those instead of service/environment.
###############################################################################

module "zpa_prefix_lists" {
  source      = "../modules/prefix-list-consumer"
  service     = "ZPA"
  environment = var.environment
}

module "office_prefix_lists" {
  source      = "../modules/prefix-list-consumer"
  service     = "Office"
  environment = var.environment
}

resource "aws_security_group" "app" {
  name        = "app-prefix-list-demo"
  description = "Example workload SG consuming managed prefix lists (tag-based discovery)"
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
