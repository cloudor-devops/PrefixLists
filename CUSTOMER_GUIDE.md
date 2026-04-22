# Customer POC Setup Guide

Step-by-step guide for setting up the Managed Prefix Lists + RAM POC in a
customer environment. All values are placeholders — replace with actual
account IDs, regions, VPCs, and AWS profile names.

Related docs:
[`README.md`](README.md) |
[`TOPOLOGY.md`](TOPOLOGY.md) |
[`SCENARIOS.md`](SCENARIOS.md) |
[`DEMO_TAGS.md`](DEMO_TAGS.md)

---

## Prerequisites

- Terraform >= 1.5, AWS provider >= 5.40 (pinned in `versions.tf`)
- AWS CLI with named profiles for each account
- At minimum 1 AWS account (single-account POC) or 2 accounts (cross-account POC)
- A VPC in the consumer account (for the demo Security Group)

## Collect before starting

| Item | Placeholder | How to get it |
|------|-------------|---------------|
| Provider account ID | `<PROVIDER_ACCOUNT_ID>` | `aws sts get-caller-identity --profile <provider-profile>` |
| Consumer account ID | `<CONSUMER_ACCOUNT_ID>` | `aws sts get-caller-identity --profile <consumer-profile>` |
| Provider AWS profile | `<provider-profile>` | `~/.aws/config` |
| Consumer AWS profile | `<consumer-profile>` | `~/.aws/config` |
| Target region | `<region>` | Customer decision |
| Consumer VPC ID | `<VPC_ID>` | `aws ec2 describe-vpcs --profile <consumer-profile>` |
| Organization ID (optional) | `<ORG_ID>` | `aws organizations describe-organization` (from mgmt account) |

---

## Phase 1 — Provider: create the prefix lists

### 1.1 Clone and configure

```bash
git clone https://github.com/cloudor-devops/PrefixLists.git
cd PrefixLists
```

Pick the topology that matches the customer. For a minimal POC, keep only
`provider/network-prod/<region>/` and delete the staging/dr/shared folders.

### 1.2 Edit the provider leaf

```bash
cd provider/network-prod/<region>
```

**`providers.tf`** — set the region only (profile is set via `terraform.tfvars`):
```hcl
provider "aws" {
  region  = "<region>"
  profile = var.aws_profile   # set aws_profile in terraform.tfvars, not here
}
```

**Prefix list `.tf` files** — replace example CIDRs with real values:
- Each `entry { cidr = "..." description = "..." }` block is one IP/CIDR
- Update `max_entries` to `current count x 2` (minimum 15)
- Update the `# PADDING` comment
- Delete files for services that don't apply; add new files for new services

**`ram.tf`** — list every prefix list you want shared:
```hcl
locals {
  shared_prefix_list_arns = var.ram_enabled ? {
    zpa-connectors = aws_ec2_managed_prefix_list.zpa_connectors.arn
    # add one line per list
  } : {}
}
```

**`terraform.tfvars`** — create from the example:
```bash
cp terraform.tfvars.example terraform.tfvars
```
Edit:
```hcl
aws_profile    = "<provider-profile>"   # null = use default credentials (env vars / instance role)
ram_enabled    = true
ram_principals = [
  "<CONSUMER_ACCOUNT_ID>",
]
ram_allow_external_principals = true   # false if same AWS Org
```

### 1.3 Apply

```bash
terraform init
terraform plan      # review
terraform apply     # confirm with 'yes'
```

Verify in the console: **VPC -> Managed prefix lists**. Check entries, tags,
and `max_entries` padding.

---

## Phase 2 — Accept the RAM share (cross-account only)

Skip if single-account POC or if accounts are in the same AWS Org with
`enable-sharing-with-aws-organization` enabled.

```bash
# List pending invitations
aws ram get-resource-share-invitations \
  --profile <consumer-profile> --region <region>

# Accept (copy the ARN from the output above)
aws ram accept-resource-share-invitation \
  --profile <consumer-profile> --region <region> \
  --resource-share-invitation-arn <invitation-arn>

# Verify the consumer sees the shared lists
aws ec2 describe-managed-prefix-lists \
  --profile <consumer-profile> --region <region> \
  --filters 'Name=owner-id,Values=<PROVIDER_ACCOUNT_ID>' \
  --query 'PrefixLists[].[PrefixListName,PrefixListId]' --output table
```

---

## Phase 3 — Consumer: wire SG rules to the shared prefix lists

Choose the discovery mode that matches the account setup.

**Important — how tag discovery works**:

Tag-based discovery runs during `terraform plan` — it queries AWS for prefix
lists matching the `Service` + `Environment` tags. This means:

- **CIDR changes** to an existing prefix list propagate to the consumer SG
  **instantly via AWS** — no consumer plan/apply needed at all.
- **New prefix lists** (matching the consumer's tag filter) are only picked
  up when the consumer's `terraform plan` runs and the data source refreshes,
  so run `terraform apply` on the consumer side after the provider adds a
  new list. CIDR changes still propagate automatically either way.

### Option A — Same-account POC (tag-based discovery)

Provider and consumer are the same AWS account. Tags are visible natively.

```bash
cd consumer/examples/workload-same-account
terraform init
terraform apply -var 'vpc_id=<VPC_ID>'
```

Note: `vpc_id` defaults to `""`. When empty, the SG and rules are skipped
but tag discovery still runs — useful for validating the tag filter returns
the right prefix lists without creating any AWS resources.

The consumer code:
```hcl
module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  service     = "ZPA"           # matches the provider's Service tag
  environment = "prod"          # matches the provider's Environment tag
}
```

### Option B — Cross-account POC (owner_id + name_prefix)

Provider and consumer are different accounts. Tags don't cross RAM.

```bash
cd consumer/examples/workload-demo
cp terraform.tfvars.example terraform.tfvars
```
Edit `terraform.tfvars`:
```hcl
provider_owner_id = "<PROVIDER_ACCOUNT_ID>"
vpc_id            = "<VPC_ID>"
aws_profile       = "<consumer-profile>"
```
```bash
terraform init
terraform apply
```

The consumer code:
```hcl
module "zpa_prefix_lists" {
  source      = "../../../modules/prefix-list-consumer"
  owner_id    = var.provider_owner_id      # provider account ID
  name_prefix = "zpa-connectors-"          # matches the provider's list name
}
```

### Option C — Import the module into existing workload Terraform

For real infrastructure (not demo stacks):
```hcl
module "zpa_pl" {
  source      = "git::https://github.com/cloudor-devops/PrefixLists.git//modules/prefix-list-consumer?ref=main"
  service     = "ZPA"                           # same-account
  # owner_id    = "<PROVIDER_ACCOUNT_ID>"       # cross-account (use instead of service)
  # name_prefix = "zpa-connectors-"             # cross-account
}

resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each          = toset(module.zpa_pl.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
```

---

## Phase 4 — Validate the end-to-end flow

### Test 1: CIDR propagation (no consumer action needed)

1. On the provider side, add an entry to a prefix list `.tf` file
2. `terraform apply` in the provider leaf
3. Check the consumer SG in the console — click the `pl-xxx` link in the
   inbound rules to see the new CIDR. No consumer apply needed.

### Test 2: New prefix list discovery

1. Provider creates a new `.tf` file with matching `Service` + `Environment` tags
2. Provider adds its ARN to `ram.tf`
3. `terraform apply` on provider — the new prefix list now exists in AWS
4. Consumer `terraform plan` shows `+1 ingress rule` (the tag filter found the new list)
5. Consumer `terraform apply` creates the new SG rule

---

## Discovery modes quick reference

| Scenario | Module variables | Tags cross the boundary? |
|----------|-----------------|--------------------------|
| Same account | `service`, `environment` | Yes (native) |
| Cross account (RAM) | `owner_id`, `name_prefix` | No (AWS limitation) |
| Region filtering | Automatic (API is region-scoped) | N/A |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Consumer sees no shared lists | RAM invitation not accepted, or wrong region | Accept invitation; verify `--region` |
| Tag filter returns empty cross-account | Owner tags don't propagate via RAM | Use `owner_id + name_prefix` |
| Prefix list resize fails | A consumer SG has no free rule slots | Increase SG quota or detach unused lists |
| New list not discovered | Missing from `ram.tf` or filter doesn't match | Add ARN to `local.shared_prefix_list_arns`; check filter |

---

## Cost

$0/month. Managed Prefix Lists, AWS RAM, Security Groups, SG rules, and all
describe API calls are free AWS resources.
