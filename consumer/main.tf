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
# AFTER: cross-account dynamic discovery with LIVE tag sync.
#
# Tag state on the consumer side is managed entirely by the tag-sync Lambda
# in consumer/tag-sync.tf — it mirrors every tag change from the provider
# account in near-real-time (EventBridge -> cross-account forward -> Lambda).
# No static service_name_map, no per-apply manual tagging.
#
# For discovery we still use owner_id + name_prefix here because it doesn't
# depend on tags being present, so the first plan works even before the
# Lambda's bootstrap invocation has run. Once tags are flowing, you can
# switch this block to pure tag-based discovery (service = "ZPA", ...) and
# it will work too — the Lambda keeps the tag state current.
###############################################################################

module "zpa_prefix_lists" {
  source      = "../modules/prefix-list-consumer"
  owner_id    = var.provider_owner_id
  name_prefix = "zpa-connectors-"
}

resource "aws_security_group" "app" {
  name        = "app-prefix-list-demo"
  description = "Example workload SG consuming RAM-shared managed prefix lists"
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
