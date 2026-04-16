# Demo: Tag-Based Discovery (Single Account)

Walkthrough for presenting the tag-based prefix list discovery POC.
Each step demonstrates a specific capability of the solution.

**Environment**: account `492094933642`, region `us-east-1`.
Provider and consumer run in the same account (tags visible natively).

---

## Step 1 — Show how tags are defined on the provider side

**Capability**: consistent tagging contract between provider and consumer.

Open `provider/network-prod/us-east-1/zpa-connectors.tf` and show the tags block:

```hcl
tags = merge(local.common_tags, {
  Name        = "zpa-connectors-prod-us-east-1"
  Service     = "ZPA"            # consumer filters on this
  Group       = "connectors"
  Environment = "prod"           # consumer filters on this
  Owner       = "network-team"
})
```

Every prefix list carries `Service` and `Environment` tags. These two fields
are the discovery contract: the consumer only needs to know the service name
and the environment to find the right list.

**In the AWS Console**: VPC → Managed prefix lists → click any list → Tags tab.
Show all 7 tags. Point out `Service` and `Environment` specifically.

---

## Step 2 — Show how the consumer discovers prefix lists by tags

**Capability**: dynamic discovery without hardcoded IDs.

Open `consumer/examples/workload-same-account/main.tf` and show the module blocks:

```hcl
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
```

Two lines per service. No prefix list IDs, no account IDs, no naming
conventions. The module queries the AWS API with tag filters and returns
matching prefix list IDs.

The Security Group rules use `for_each` over the discovered IDs:
```hcl
resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each       = toset(module.zpa_prefix_lists.ids)
  prefix_list_id = each.value
  ...
}
```

---

## Step 3 — Verify the applied state in the console

**Capability**: SG rules reference prefix lists instead of raw CIDRs.

The consumer stack has been applied. Verify in the console:

1. EC2 → Security Groups → `app-tag-discovery-demo`
2. Inbound rules tab: 3 rules, each with source `pl-xxxx` (not a CIDR)
   - ZPA tcp/443
   - CPC tcp/443
   - Offices tcp/22
3. Outbound rules tab: 1 rule with destination `pl-xxxx`
   - Vendor APIs tcp/443
4. Click any `pl-xxxx` link → opens the prefix list with its entries and tags

All 4 prefix list IDs were discovered by `Service + Environment` tags.
No ID appears anywhere in the consumer code.

---

## Step 4 — Demonstrate automatic CIDR propagation

**Capability**: IP changes flow to consumer SGs without any consumer action.

Edit `provider/network-prod/us-east-1/zpa-connectors.tf`, add:
```hcl
entry {
  cidr        = "10.99.99.0/32"
  description = "demo-new-connector"
}
```

Apply from the provider leaf:
```bash
cd provider/network-prod/us-east-1
terraform apply
```

Refresh the consumer SG in the console: EC2 → Security Groups →
`app-tag-discovery-demo` → Inbound rules → click the ZPA `pl-xxxx` link →
the new CIDR `10.99.99.0/32` appears in the entries.

The consumer did not run `terraform apply`. The SG rule still points at the
same `pl-xxxx` ID, but AWS resolves it to the updated entry set. This is
native prefix list behavior — any SG referencing the list inherits CIDR
changes automatically.

---

## Step 5 — Demonstrate automatic discovery of a new prefix list

**Capability**: new prefix lists auto-appear in the consumer without code changes.

This is the tag discovery in action. When the provider creates a new prefix
list with tags that match the consumer's filter, the consumer picks it up on
the next `terraform plan`.

**Provider side** — create `provider/network-prod/us-east-1/monitoring.tf`:
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

Apply: `terraform apply`. The new list now exists in AWS with
`Service=Monitoring, Environment=prod` tags.

**Consumer side** — add one module block to the consumer's `main.tf`:
```hcl
module "monitoring_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "Monitoring"
  environment = "prod"
}
```

And one rule block:
```hcl
resource "aws_vpc_security_group_ingress_rule" "monitoring" {
  for_each          = toset(module.monitoring_prefix_lists.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 9100
  to_port           = 9100
  description       = "Monitoring ingress (tag-discovered)"
}
```

Run `terraform plan`. The plan shows `+1 new ingress rule` — the tag filter
found the new list automatically. Apply to attach it to the SG.

If the consumer already had this block in place before the provider created
the list, it would have returned zero matches (no error). The moment the
list appears with the right tags, the next plan picks it up.

---

## Step 6 — Demonstrate CI-driven consumer updates across multiple workloads

**Capability**: provider merges a change, CI applies it to all consumers automatically. No consumer team involvement.

This is what makes the solution operational at scale. The CI workflow
(`.github/workflows/ci.yml`) has two phases:

```
Phase 1: apply all provider/ leaves  (prefix list created/updated in AWS)
             ↓
Phase 2: apply all consumer/ leaves  (data sources re-run, SG rules reconciled)
```

**Demo scenario — provider adds a CIDR, 3 consumer workloads update automatically:**

1. Provider team edits `provider/network-prod/us-east-1/zpa-connectors.tf`:
   ```hcl
   entry {
     cidr        = "10.99.99.0/32"
     description = "demo-new-connector"
   }
   ```

2. Provider opens a PR. CI runs `terraform plan` on every leaf:
   - `provider/network-prod/us-east-1`: `Plan: 0 to add, 1 to change` (prefix list entry added)
   - `consumer/examples/workload-same-account`: `No changes` (same pl-xxx ID, CIDR propagates via AWS)
   - `consumer/examples/workload-prod-us-east-1`: `No changes`
   - `consumer/examples/workload-demo`: `No changes`

3. Reviewer approves. PR merged to `main`.

4. CI Phase 1 applies the provider leaf — prefix list updated in AWS.
   CI Phase 2 applies all consumer leaves — data sources refresh, SG rules
   confirmed in sync. No new rules needed (same prefix list ID, CIDRs
   propagated by AWS already).

**No consumer team opened a PR. No consumer team ran terraform. CI did it all.**

**Demo scenario — provider creates a new prefix list, consumers auto-discover it:**

1. Provider team creates `provider/network-prod/us-east-1/monitoring.tf`
   with `Service=Monitoring, Environment=prod` tags. Opens PR, merges.

2. CI Phase 1 applies the provider leaf — new prefix list created in AWS.

3. CI Phase 2 applies the consumer leaves:
   - Any consumer that already has `service = "Monitoring"` in its module
     block → tag filter now returns 1 ID → plan shows `+1 ingress rule`
     → CI applies it.
   - Consumers without a Monitoring block → no change.

4. The consumer team that wanted Monitoring added the module block once
   (could have been months ago when the block returned zero matches).
   The moment the provider creates the list, CI connects them.

**Scheduled reconcile**: CI also runs all consumer leaves on a daily schedule
(weekdays 06:00 UTC). This catches new lists or drift even if the provider
change came from outside this repo (console, another pipeline, etc.).

---

## Summary for the audience

| Step | Capability demonstrated |
|------|------------------------|
| 1 | Tags are the provider-consumer contract (`Service`, `Environment`) |
| 2 | Consumer discovers prefix lists by tags, no hardcoded IDs |
| 3 | SG rules reference prefix lists instead of raw CIDRs |
| 4 | CIDR changes propagate automatically, zero consumer action |
| 5 | New prefix lists are discovered automatically via tag matching |
| 6 | CI applies changes to all consumers — no manual runs, no coordination |

---

## Cleanup

```bash
cd consumer/examples/workload-same-account
terraform destroy -var 'vpc_id=vpc-052e9049c736ca907'
```

Removes only the demo SG and its rules. Prefix lists in the provider account
are untouched.

---

## Live state reference

| Prefix list | ID | Service tag | Environment tag |
|---|---|---|---|
| zpa-connectors-prod-us-east-1 | pl-0bc67b13bcf8a57b6 | ZPA | prod |
| offices-corp-prod-us-east-1 | pl-0dfa8680db597c3a6 | Office | prod |
| cpc-endpoints-prod-us-east-1 | pl-07ce6929a85ef7673 | CPC | prod |
| vendor-apis-prod-us-east-1 | pl-0d29f0178bf2f90d5 | VendorAPIs | prod |

SG: `app-tag-discovery-demo` in VPC `vpc-052e9049c736ca907`
Account: `492094933642`, region `us-east-1`
