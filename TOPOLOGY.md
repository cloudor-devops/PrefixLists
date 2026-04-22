# Repository Topology

> **The directory structure IS the distribution strategy.** Each leaf folder
> is an independent Terraform stack, and the path encodes its scope.

## The model

```
provider/
  <account-alias>/               # which account/profile owns these lists
    <region>/                    # which AWS region they live in
      *.tf                       # resources (one file per prefix list)
      ram.tf                     # sharing config for this leaf
      terraform.tfvars(.example) # consumer principals + aws profile
consumer/
  examples/
    <workload-name>/             # example workload SG wiring for a scenario
      *.tf
      terraform.tfvars(.example)
modules/
  prefix-list-consumer/          # shared library — not a leaf
```

**Three rules**:

1. **A leaf is a folder containing `versions.tf`.** Terraform state lives inside
   the leaf. `terraform init/plan/apply` always runs inside a leaf.
2. **The path encodes scope.** `<account-alias>` maps to an AWS profile and an
   owning account. `<region>` matches the `aws` provider's region. No leaf
   crosses either boundary.
3. **Modules are libraries.** `modules/` holds reusable Terraform, not leaves.
   Never run `terraform init` in a module directory.

## Why this shape

| Problem | How the layout solves it |
|---|---|
| Prefix Lists are region-scoped | One folder per region; no provider aliases |
| RAM shares are region-scoped | Co-located with the prefix lists they share |
| Different envs have different consumers | Separate leaves with different `ram_principals` |
| Different envs may live in different accounts | Separate `<account-alias>` folders; each leaf targets its own `aws_profile` |
| Some lists are cross-environment (offices, vendors) | Dedicated `network-shared/` account alias |
| Ownership splits (network vs security vs IT) | Folder-level CODEOWNERS — different teams own different sub-trees |
| New account joining the Org | Bump `ram_principals` (or use Org ARN), re-apply one leaf; no consumer changes |
| New region for existing env | Copy a sibling leaf; change region + tags; apply |
| New environment | New `<account-alias>` top-level folder; run `terraform apply` in each new leaf |

## The account-alias conventions this repo uses

| Alias | Purpose | Typical contents |
|---|---|---|
| `network-prod` | Prod-env network ingress IPs | ZPA connectors, CPC endpoints, per-env vendor allowlists |
| `network-staging` | Staging-env network ingress IPs | Lower-volume mirror of prod |
| `network-dr` | DR-env network ingress IPs | Same services as prod but pointed at DR region |
| `network-shared` | Cross-environment lists | Office IPs, vendor API whitelists, legal-boundary blocks |

These are **aliases**, not account IDs. In a single-account org, every alias
maps to the same physical account with different AWS profiles or roles. In a
multi-account org, each alias maps to a distinct account. The `aws_profile`
variable in each leaf's `terraform.tfvars` picks which.

## The discovery contract (provider ↔ consumer)

The provider guarantees:
- Every prefix list has a **stable name prefix** matching its service:
  `zpa-connectors-*`, `cpc-endpoints-*`, `offices-corp-*`, `vendor-apis-*`, …
- Every prefix list has consistent **tags**: `Service`, `Group`, `Environment`,
  `Region`, `Owner`, `Name`, `ManagedBy`.
- The **owner account ID** doesn't change (implicit; comes with the aws_profile).

The consumer relies on:
- `owner_id` + `name_prefix` attribute filters (works across RAM; robust).
- Region is implicit (the AWS API is region-scoped).

Tag-based filtering is available in the module, but only works for
locally-owned lists. RAM-shared lists have empty tag views on the consumer
side — this is AWS RAM behavior, not a bug. Use `owner_id + name_prefix` for
cross-account, tag filters only for same-account.

## Onboarding flows

### Adding a new list (existing env, existing region)
1. `cd provider/network-prod/us-east-1`
2. Create `my-new-list.tf` with an `aws_ec2_managed_prefix_list` resource.
3. Add its ARN to `local.shared_prefix_list_arns` in `ram.tf`.
4. Add its output to `outputs.tf`.
5. `terraform apply`.
6. Consumers whose `name_prefix` filter matches pick it up on their next plan.

### Adding a new region for an existing env
1. `cp -r provider/network-prod/us-east-1 provider/network-prod/eu-west-1`
2. Update `providers.tf` region, `_tags.tf` Region tag, list `name` values.
3. Update `terraform.tfvars.example` with the new region's consumer list.
4. `terraform init && terraform apply`.

### Adding a new environment
1. `mkdir -p provider/network-dev/us-east-1` (or copy from network-staging).
2. Populate with appropriate CIDRs / consumer list / account alias.
3. `terraform init && terraform apply` in the new leaf.

### Onboarding a new consumer account
1. Provider side: add the account ID to `ram_principals` in the relevant
   leaf's `terraform.tfvars`, apply.
2. Consumer side: clone the repo, copy one of the `consumer/examples/*`
   that matches the env, fill in `terraform.tfvars`, apply.
3. (Only if accounts aren't in the same Org) accept the RAM invitation.
4. Done. Latency from provider edit to consumer SG visibility: seconds.

## Apply model

Every leaf is an independent `terraform init/plan/apply`. When the provider
team updates a prefix list, run `terraform apply` in the affected provider
leaf; CIDR changes then propagate to consumer SGs automatically via AWS (the
`pl-xxx` ID is unchanged). Picking up a *new* prefix list requires a
consumer-side `terraform apply` so the data source re-runs and the SG rule
is reconciled.

When applying across many leaves, apply `provider/` leaves first so the
prefix lists exist in AWS before any consumer tries to discover them, then
apply `consumer/` leaves.
