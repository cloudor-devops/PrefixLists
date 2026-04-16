# PrefixLists — Customer Handoff

One-page guide to stand up **AWS Managed Prefix Lists + RAM cross-account sharing**
in your environment. Full context in [`README.md`](README.md).

## What you get

A pattern where the **team owning the IPs** edits one `.tf` file, runs
`terraform apply`, and workloads in other AWS accounts automatically pick up the
new CIDRs in their Security Groups — **no consumer-side Terraform run**.

## Prerequisites

- 2+ AWS accounts: one **provider** (owns the IPs), one+ **consumer** (runs workloads).
- AWS CLI profiles for each account (SSO, named profiles, or env creds).
- Terraform ≥ 1.5, AWS provider ≥ 5.40 (already pinned).
- A VPC in each consumer account (only needed for the smoke test examples).

## Checklist

- [ ] `git clone https://github.com/cloudor-devops/PrefixLists.git && cd PrefixLists`
- [ ] Under `provider/`, pick the account-alias folders (`network-prod/`, `network-staging/`, `network-dr/`, `network-shared/`) that match your topology. Delete the rest, or rename/copy. See [`TOPOLOGY.md`](TOPOLOGY.md) for the full model.
- [ ] In each leaf `provider/<alias>/<region>/*.tf`: replace example CIDRs with real ones, update `max_entries` to `current × 2` (floor 15–20), update the `# PADDING` comment.
- [ ] In each leaf's `ram.tf`: add/remove entries in `local.shared_prefix_list_arns` to match the `.tf` files you kept.
- [ ] Create `terraform.tfvars` from the `.example` in each leaf (see below).
- [ ] `cd provider/<alias>/<region> && terraform init && terraform apply`.
- [ ] In each consumer account: accept the RAM invitation (see below). Skip if same AWS Org with `enable-sharing-with-aws-organization`.
- [ ] Pick a consumer example from `consumer/examples/` (or import `modules/prefix-list-consumer` directly into your workload Terraform). Replace inline `cidr_blocks` with `prefix_list_id`.
- [ ] Demo the update loop to the owning team: add an entry, apply, watch it appear in the consumer account.

## Tfvars templates

### `provider/<alias>/<region>/terraform.tfvars`
```hcl
ram_enabled = true

ram_principals = [
  "222222222222",  # consumer-account-1
  # "333333333333",  # consumer-account-2
  # "arn:aws:organizations::111111111111:ou/o-xxx/ou-xxx-yyy",  # whole OU
]

# true = standalone accounts not in the same AWS Org
# false = everything is inside the same org
ram_allow_external_principals = true
```

### `consumer/examples/<workload>/terraform.tfvars`
```hcl
prod_network_account_id   = "111111111111"   # account that owns env-specific lists
shared_network_account_id = "111111111111"   # account that owns cross-env lists (offices, vendors)
vpc_id                    = "vpc-xxxxxxxxxxxxxxxxx"
aws_profile               = "my-consumer-profile"   # optional; omit for default creds
```
Variable names differ per example (e.g., `workload-demo` uses `provider_owner_id` instead of the split prod/shared pattern). Check the example's `variables.tf`.

**Both `terraform.tfvars` files are gitignored** — safe to fill with real values.

## RAM invitation accept (per consumer account, one-time)

Skip if provider + consumer are in the same AWS Organization (auto-accepts).

```bash
aws ram get-resource-share-invitations \
  --profile <consumer-profile> --region <region>

aws ram accept-resource-share-invitation \
  --profile <consumer-profile> --region <region> \
  --resource-share-invitation-arn <arn-from-output>
```

Verify:
```bash
aws ec2 describe-managed-prefix-lists \
  --profile <consumer-profile> --region <region> \
  --filters 'Name=owner-id,Values=<PROVIDER_ACCOUNT_ID>' \
  --query 'PrefixLists[].[PrefixListName,PrefixListId]' --output table
```

## Wiring into your real workload Terraform

Pin the module by commit SHA in production. `main` is fine for evaluation.

```hcl
module "zpa_pl" {
  source      = "git::https://github.com/cloudor-devops/PrefixLists.git//modules/prefix-list-consumer?ref=main"
  owner_id    = "111111111111"         # the provider account ID
  name_prefix = "zpa-connectors-"      # matches names in provider/<alias>/<region>/zpa-connectors.tf
}

resource "aws_vpc_security_group_ingress_rule" "zpa" {
  for_each          = toset(module.zpa_pl.ids)
  security_group_id = aws_security_group.app.id
  prefix_list_id    = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ZPA ingress via managed prefix list ${each.value}"
}
```

For **locally-owned** prefix lists (single-account, no RAM), drop `owner_id`
and use tag filters instead:
```hcl
module "zpa_pl" {
  source      = "git::https://github.com/cloudor-devops/PrefixLists.git//modules/prefix-list-consumer?ref=main"
  service     = "ZPA"
  environment = "prod"
}
```

## Day-2 routine (what you hand the owning team)

> When an IP changes, edit one file and run `terraform apply`. That's it.

```bash
$EDITOR provider/<alias>/<region>/zpa-connectors.tf   # add/remove entry { } blocks
terraform apply
```

Cross-account propagation, consumer SG updates, and regional isolation happen
automatically. No consumer-side Terraform run, no ticket, no coordination.

## Gotchas

| Pitfall | What happens | Fix |
|---|---|---|
| Forget to accept RAM invitation | Consumer `describe-managed-prefix-lists` returns empty | Run `aws ram accept-resource-share-invitation` once per consumer account |
| Tag filters on RAM-shared lists | Returns empty — **owner tags don't propagate across RAM** | Use `owner_id + name_prefix` mode (above) |
| Under-sized `max_entries` | Later resize blocked if any consumer SG is full | Pad generously at creation (`current × 2`, floor 20) |
| Renaming a `.tf` file after apply | Resource label changes → destroy+recreate → consumer SGs break briefly | Edit in place; don't rename active files |
| Mixing regions in one stack | Provider aliases, gets ugly fast | Keep one folder per region under `provider/<alias>/` |

## Cost

Everything in the pattern is **$0/month**: Managed Prefix Lists, AWS RAM, Security
Groups, SG rules, and describe API calls are all free. You only pay for the
compute/networking you already have.

## Support

- Full architecture + rationale: [`README.md`](README.md)
- Folder model + onboarding flows: [`TOPOLOGY.md`](TOPOLOGY.md)
- 9 worked real-world scenarios: [`SCENARIOS.md`](SCENARIOS.md)
- Module source + variables: `modules/prefix-list-consumer/`
