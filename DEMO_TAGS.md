# Demo: Tag-Based Discovery (Single Account)

This demo proves the original spec's design: the consumer discovers prefix
lists by `Service` + `Environment` tags. No hardcoded IDs, no account IDs,
no naming conventions. Pure tag filtering.

**Prerequisite**: provider and consumer run in the **same AWS account**
(`492094933642`). Tags are visible natively — no Lambda, no cross-account
sync needed.

**Account**: `492094933642` (provider = consumer), region `us-east-1`.

---

## Step 1 — See how tags are defined (provider side)

Open any prefix list file, e.g. `provider/network-prod/us-east-1/zpa-connectors.tf`:

```hcl
tags = merge(local.common_tags, {
  Name        = "zpa-connectors-prod-us-east-1"
  Service     = "ZPA"            # ← consumer filters on this
  Group       = "connectors"
  Environment = "prod"           # ← consumer filters on this
  Owner       = "network-team"
})
```

Every prefix list carries a `Service` and `Environment` tag. This is the
**contract** between provider and consumer. The consumer never sees the
list's ID or name — it only knows "I need `Service=ZPA, Environment=prod`."

**In the AWS Console**: VPC → Managed prefix lists → click any list → Tags
tab. You'll see all 7 tags.

## Step 2 — See how the consumer discovers by tags

Open `consumer/examples/workload-same-account/main.tf`:

```hcl
module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "ZPA"            # ← matches the tag
  environment = "prod"           # ← matches the tag
}

module "offices_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "Office"
  environment = "prod"
}
```

Two lines per service. The module calls the AWS API:
`describe-managed-prefix-lists --filters tag:Service=ZPA tag:Environment=prod`
and gets back the matching prefix list IDs.

The Security Group rules then use `for_each` over those IDs:
```hcl
resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each       = toset(module.zpa_prefix_lists.ids)
  prefix_list_id = each.value       # ← discovered, never hardcoded
  ...
}
```

## Step 3 — Apply and verify (already done)

```bash
cd consumer/examples/workload-same-account
terraform apply -var 'vpc_id=vpc-052e9049c736ca907'
```

What was created:
- 1 Security Group: `app-tag-discovery-demo`
- 4 rules attached (ZPA tcp/443, CPC tcp/443, Offices tcp/22, Vendor APIs tcp/443 egress)
- All 4 prefix list IDs were discovered by tags — zero IDs in the code.

**Verify in the console**:
1. EC2 → Security Groups → `app-tag-discovery-demo`
2. Inbound rules tab → 3 rules, each showing "Source: pl-xxxx"
3. Outbound rules tab → 1 rule showing "Destination: pl-xxxx"
4. Click any pl-xxxx link → Tags tab → confirms the Service + Environment tags

## Step 4 — The killer demo: add a CIDR, watch it propagate

**Provider side** — edit `provider/network-prod/us-east-1/zpa-connectors.tf`:
```hcl
entry {
  cidr        = "10.99.99.0/32"
  description = "demo-new-connector"
}
```

Apply (from the provider leaf):
```bash
cd provider/network-prod/us-east-1
terraform apply
```

**Now check the consumer SG** — refresh EC2 → Security Groups →
`app-tag-discovery-demo` → Inbound rules. The ZPA rule still references the
same `pl-xxxx` — but click it and you'll see the new CIDR
`10.99.99.0/32` in the entries.

**No consumer Terraform run. No code change. No coordination.** The prefix
list updated, and every SG rule pointing at it inherited the change.

## Step 5 — Add a new prefix list, watch it auto-appear

**Provider side** — create a new file
`provider/network-prod/us-east-1/monitoring.tf`:

```hcl
resource "aws_ec2_managed_prefix_list" "monitoring" {
  name           = "monitoring-prod-us-east-1"
  address_family = "IPv4"
  max_entries    = 15

  entry {
    cidr        = "10.88.0.0/16"
    description = "prometheus-scraper"
  }

  tags = merge(local.common_tags, {
    Name        = "monitoring-prod-us-east-1"
    Service     = "Monitoring"
    Group       = "observability"
    Environment = "prod"
    Owner       = "platform-team"
  })
}
```

Add to `ram.tf` → `local.shared_prefix_list_arns`:
```hcl
monitoring = aws_ec2_managed_prefix_list.monitoring.arn
```

Apply: `terraform apply`.

**Consumer side** — if the consumer had a module block like:
```hcl
module "monitoring_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "Monitoring"
  environment = "prod"
}
```

...it would discover the new list on the next `terraform plan` and create
a new SG rule automatically. The consumer just needs a block that matches
the tag — the prefix list ID is never mentioned.

## What the audience should take away

1. **Tags are the contract.** Provider tags every list with `Service` and
   `Environment`. Consumer filters on those tags. They never exchange IDs.

2. **CIDR changes propagate automatically.** Edit the provider `.tf`, apply.
   Every SG rule referencing the list inherits the change with zero consumer
   action.

3. **New lists auto-appear.** If the consumer's tag filter matches a
   newly-created list, it shows up on the next `terraform plan` — one new
   SG rule, no code change in the consumer.

4. **Region is implicit.** The AWS API is region-scoped. A consumer in
   `eu-west-1` cannot see `us-east-1` lists, even if the tags match.
   No cross-region leakage, no wasted SG quota.

## Cleanup

```bash
cd consumer/examples/workload-same-account
terraform destroy -var 'vpc_id=vpc-052e9049c736ca907'
```

This removes only the demo SG and its rules. The prefix lists in the
provider account are untouched.

---

## Quick reference: what's live right now

| Prefix list | ID | Service tag | Environment tag |
|---|---|---|---|
| zpa-connectors-prod-us-east-1 | pl-0bc67b13bcf8a57b6 | ZPA | prod |
| offices-corp-prod-us-east-1 | pl-0dfa8680db597c3a6 | Office | prod |
| cpc-endpoints-prod-us-east-1 | pl-07ce6929a85ef7673 | CPC | prod |
| vendor-apis-prod-us-east-1 | pl-0d29f0178bf2f90d5 | VendorAPIs | prod |

SG: `app-tag-discovery-demo` in VPC `vpc-052e9049c736ca907`
Account: `492094933642`, region `us-east-1`
