###############################################################################
# workload-demo — the simplest consumer, used as the live POC smoke test.
#
# Pulls a single prefix list (ZPA) from a single provider leaf via
# owner_id + name_prefix and attaches it to a demo Security Group's
# ingress rules. No shared-leaf lookups, no egress, no complications.
#
# For richer examples see sibling folders:
#   ../workload-prod-us-east-1/     (prod + shared, ingress + egress)
#   ../workload-staging-us-east-1/  (staging-env ZPA + shared)
#   ../workload-dr-eu-west-1/       (DR region, ZPA only)
#
# BEFORE vs AFTER for context:
#   BEFORE: inline cidr_blocks = ["10.30.1.0/32", "10.30.2.0/32"]  # drifts, nobody owns
#   AFTER:  prefix_list_id     = each.value                         # discovered, auto-updates
###############################################################################

module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.provider_owner_id
  name_prefix = "zpa-connectors-"
}

resource "aws_security_group" "app" {
  name        = "app-prefix-list-demo"
  description = "Live POC smoke test SG — consumes RAM-shared prefix list"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each = toset(module.zpa_prefix_lists.ids)

  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ZPA ingress via managed prefix list ${each.value}"
}

output "attached_prefix_lists" {
  value = {
    zpa = module.zpa_prefix_lists.details
  }
}
