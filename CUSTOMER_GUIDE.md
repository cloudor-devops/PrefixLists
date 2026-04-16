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
| Provider account ID | `<PROVIDER_ACCOUNT_ID>` | `aws sts get-caller-identity --profile <provider>` |
| Consumer account ID | `<CONSUMER_ACCOUNT_ID>` | `aws sts get-caller-identity --profile <consumer>` |
| Provider AWS profile | `<provider-profile>` | `~/.aws/config` |
| Consumer AWS profile | `<consumer-profile>` | `~/.aws/config` |
| Target region | `<region>` | Customer decision |
| Consumer VPC ID | `<VPC_ID>` | `aws ec2 describe-vpcs --profile <consumer>` |
| Organization ID (optional) | `<ORG_ID>` | `aws organizations describe-organization` |

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

**`providers.tf`** — set the AWS profile and region:
```hcl
provider "aws" {
  region  = "<region>"
  profile = "<provider-profile>"
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

**Important — how tag discovery and CI work together**:

Tag-based discovery runs during `terraform plan` — it queries AWS for prefix
lists matching the `Service` + `Environment` tags. This means:

- **CIDR changes** to an existing prefix list propagate to the consumer SG
  **instantly via AWS** — no consumer plan/apply needed at all.
- **New prefix lists** (matching the consumer's tag filter) are only picked
  up when the consumer's `terraform plan` runs and the data source refreshes.

With CI enabled (Phase 5), this plan/apply happens **automatically** after
every provider merge. CI applies the provider leaf first (creates the new
list in AWS), then applies all consumer leaves (tag filter discovers it,
SG rule gets created). No one on the consumer side needs to run anything.

Without CI, someone would need to run `terraform apply` on the consumer side
manually to pick up new prefix lists. CIDR changes still propagate
automatically either way.

### Option A — Same-account POC (tag-based discovery)

Provider and consumer are the same AWS account. Tags are visible natively.

```bash
cd consumer/examples/workload-same-account
terraform init
terraform apply -var 'vpc_id=<VPC_ID>'
```

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

**With CI (Phase 5)**: steps 3-5 happen automatically on PR merge. The
provider team merges a PR, CI applies the provider leaf, then CI applies
all consumer leaves. The consumer team does nothing — CI runs the
plan/apply that triggers the tag discovery.

---

## Phase 5 — Enable CI (recommended)

CI automates plan/apply so nobody runs Terraform manually. When the
provider team merges a change, CI applies the provider leaves first, then
re-applies all consumer leaves. Consumer SGs update without any consumer
team involvement.

### 5.1 Create the GitHub Actions OIDC identity provider in AWS

Run once per AWS account:
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 5.2 Create an IAM role for GitHub Actions

Replace `<ACCOUNT_ID>` and `<GITHUB_ORG>/<REPO>` with your values:
```bash
aws iam create-role \
  --role-name GitHubActionsTerraform \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
        "StringLike": {"token.actions.githubusercontent.com:sub": "repo:<GITHUB_ORG>/<REPO>:*"}
      }
    }]
  }'
```

Attach permissions (scope down for production):
```bash
aws iam attach-role-policy --role-name GitHubActionsTerraform \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

aws iam put-role-policy --role-name GitHubActionsTerraform \
  --policy-name RAMAccess \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"ram:*","Resource":"*"}]}'
```

### 5.3 Add the GitHub secret

```bash
gh secret set AWS_ROLE_DEFAULT \
  --repo <GITHUB_ORG>/<REPO> \
  --body "arn:aws:iam::<ACCOUNT_ID>:role/GitHubActionsTerraform"
```

Or via GitHub web: Settings -> Secrets and variables -> Actions -> New
repository secret -> Name: `AWS_ROLE_DEFAULT`, Value: the role ARN.

### 5.4 Mark leaves as CI-enabled

Only leaves with a `.ci` marker file are picked up by CI. Template leaves
without `.ci` are skipped.

```bash
touch provider/network-prod/<region>/.ci
touch consumer/examples/workload-same-account/.ci
# add .ci to any other leaf you want CI to manage
```

### 5.5 (Optional) Set up remote state for CI apply

CI plan works without remote state (plans from scratch). CI apply needs
shared state. Add `backend.tf` to each CI-enabled leaf:

```hcl
# provider/network-prod/<region>/backend.tf
terraform {
  backend "s3" {
    bucket         = "<TFSTATE_BUCKET>"
    key            = "prefix-lists/network-prod/<region>/terraform.tfstate"
    region         = "<region>"
    dynamodb_table = "<TFSTATE_LOCK_TABLE>"
    encrypt        = true
  }
}
```

Create the S3 bucket + DynamoDB table first:
```bash
aws s3api create-bucket --bucket <TFSTATE_BUCKET> --region <region>
aws s3api put-bucket-versioning --bucket <TFSTATE_BUCKET> \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name <TFSTATE_LOCK_TABLE> \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region <region>
```

Add S3/DynamoDB permissions to the GitHub Actions role:
```bash
aws iam put-role-policy --role-name GitHubActionsTerraform \
  --policy-name TerraformState \
  --policy-document '{
    "Version":"2012-10-17",
    "Statement":[
      {"Effect":"Allow","Action":"s3:*","Resource":["arn:aws:s3:::<TFSTATE_BUCKET>","arn:aws:s3:::<TFSTATE_BUCKET>/*"]},
      {"Effect":"Allow","Action":"dynamodb:*","Resource":"arn:aws:dynamodb:<region>:<ACCOUNT_ID>:table/<TFSTATE_LOCK_TABLE>"}
    ]
  }'
```

### 5.6 Test CI

1. Push the code to the repo
2. Create a branch, make a small change (e.g., add a CIDR entry)
3. Open a PR -> CI runs `terraform plan` on all `.ci`-enabled leaves
4. Review the plan output in the GitHub Actions summary
5. Merge -> CI runs `terraform apply` (Phase 1: provider, Phase 2: consumer)
6. Verify in the AWS Console that the change applied

### CI flow diagram

```
PR opened
  ↓
CI: terraform plan (all .ci-enabled leaves, parallel)
  ↓
Plan output visible in GitHub Actions
  ↓
Reviewer approves + merges
  ↓
CI Phase 1: terraform apply (provider/ leaves)
  ↓  prefix lists created/updated in AWS
CI Phase 2: terraform apply (consumer/ leaves)
  ↓  tag filters re-run, SG rules reconciled
Done — all consumer SGs reflect the change

Daily schedule (weekdays 06:00 UTC):
  CI applies all consumer leaves → catches new lists or drift
```

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
| CI auth failure | OIDC role missing for this leaf | Add `AWS_ROLE_<leaf_name>` GitHub secret |
| New list not discovered | Missing from `ram.tf` or filter doesn't match | Add ARN to `local.shared_prefix_list_arns`; check filter |

---

## Cost

$0/month. Managed Prefix Lists, AWS RAM, Security Groups, SG rules, and all
describe API calls are free AWS resources.
