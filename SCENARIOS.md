# Real-world scenarios

Nine variations you'll hit in production, with the concrete folder moves,
`terraform.tfvars` changes, and `ram_principals` values. Every scenario
composes from the topology described in `TOPOLOGY.md`.

## 1. Single prod network account, single region
**You start here.** One leaf, one region, one env.

- Folder: `provider/network-prod/us-east-1/`
- Apply: `cd provider/network-prod/us-east-1 && terraform apply`
- Consumers: each workload TF imports `modules/prefix-list-consumer` with
  `owner_id = <network-prod account ID>` and the service name prefix.

This is the `consumer/examples/workload-prod-us-east-1/` example (minus the
cross-env shared lists).

## 2. Single prod account, multiple regions
Prefix Lists are region-scoped, so every region is an independent leaf.

```
provider/network-prod/
  us-east-1/
  eu-west-1/
  ap-southeast-1/       <- copy one of the others, update region + names
```

Each region-leaf has its own `terraform.tfstate`, its own RAM share, its own
apply. Consumers deployed in `eu-west-1` automatically find only the
`eu-west-1` lists because the AWS API is region-scoped — no filter needed.

## 3. Multi-env via multiple network accounts (prod / staging / dr)
Separate accounts mean separate IAM blast radius per env. Separate CIDRs
per env keep prod traffic isolated from staging.

```
provider/
  network-prod/us-east-1/       <- production IPs
  network-staging/us-east-1/    <- staging IPs (10.130.0.0/16)
  network-dr/eu-west-1/         <- DR IPs (10.240.0.0/16), in the DR region
```

Each leaf:
- Uses a different `aws_profile` (targets its env's network account).
- Has different `ram_principals` (shares only to its env's workload accounts).
- Is applied independently by the team that owns that env.

Consumers point at `owner_id = <env's network account>`. A prod workload can't
accidentally pull staging CIDRs because the account IDs differ.

## 4. DR in a different region from prod
Same pattern as #3, but the DR leaf targets `eu-west-1` while prod is in
`us-east-1`. The DR workload's AWS provider is region=eu-west-1, so its
consumer module only sees eu-west-1 lists — the prod lists in us-east-1
are invisible by API scope.

See `provider/network-dr/eu-west-1/` and
`consumer/examples/workload-dr-eu-west-1/`.

## 5. Cross-environment shared lists (offices, vendor APIs)
Office IPs, vendor API allowlists, and corp VPN pools don't change per env —
prod workloads need the same Stripe IPs as staging workloads. Duplicating
them across `network-prod/` + `network-staging/` + `network-dr/` means
three-way maintenance.

Solution: a `network-shared/` leaf that every env's consumers read from.

```
provider/network-shared/us-east-1/
  offices.tf
  vendor-whitelist.tf
  ram.tf           <- shares to ALL consumer accounts across all envs
```

Consumers pull from TWO sources (env-specific + shared):
```hcl
module "zpa_prefix_lists" {
  owner_id    = var.prod_network_account_id       # env-specific
  name_prefix = "zpa-connectors-"
}
module "offices_prefix_lists" {
  owner_id    = var.shared_network_account_id     # cross-env
  name_prefix = "offices-corp-"
}
```

See `consumer/examples/workload-prod-us-east-1/main.tf` — the prod workload
pulls ZPA + CPC from `network-prod` and offices + vendor APIs from
`network-shared`.

## 6. Growing an existing prefix list
1. Edit the relevant `.tf` file, add an `entry { }` block.
2. Bump the `# PADDING` comment to reflect the new count (just documentation).
3. `terraform apply` in the leaf.
4. **AWS propagates the new CIDR to every consumer SG instantly** — no
   consumer apply, no restart, no coordination.

If you exceed `max_entries`, the resize will only succeed if every consumer
SG has enough free rule slots. Over-pad at creation (`current × 2`, floor 15).

## 7. Adding a new prefix list to an existing env
1. Create `provider/network-prod/us-east-1/my-new-service.tf` with a new
   `aws_ec2_managed_prefix_list.my_new_service` resource.
2. Add its ARN to `ram.tf`'s `local.shared_prefix_list_arns` map.
3. Add its output to `outputs.tf`.
4. `terraform apply`.
5. **Consumers whose `name_prefix` filter matches the new list** pick it up
   on their next plan and add ingress rules automatically.
6. Other consumers (filters that don't match) are unaffected — no quota
   consumption on their SGs.

## 8. Decommissioning a prefix list
1. First: confirm no consumers are still using it via
   `aws ec2 get-managed-prefix-list-associations --prefix-list-id pl-xxx`.
2. Remove the `.tf` file (or the resource block).
3. Remove its entry from `ram.tf`'s `local.shared_prefix_list_arns`.
4. Remove from `outputs.tf`.
5. `terraform apply` → destroys the list. Consumer SG rules that reference
   the ID will fail on their next plan; those consumers need to `apply`
   to drop the now-orphan rule.

Coordinate by announcing the deprecation, giving consumers a window to
remove the filter, then destroying.

## 9. Onboarding a new consumer account
**Provider side** — edit one line:
```hcl
# provider/network-prod/us-east-1/terraform.tfvars
ram_principals = [
  "<CONSUMER_ACCOUNT_ID>",
  "111111111111",
  "999999999999",   # <- new consumer
]
```
`terraform apply`. AWS sends the new account a RAM invitation.

**Consumer side** — one-time setup:
```bash
# 1. Accept the invitation (skip if same AWS Org with auto-accept enabled)
aws ram accept-resource-share-invitation \
  --profile new-consumer --region us-east-1 \
  --resource-share-invitation-arn <arn>

# 2. Deploy the workload stack
git clone <this repo>
cp -r consumer/examples/workload-prod-us-east-1 my-workload
cd my-workload
cat > terraform.tfvars <<EOF
aws_profile                = "new-consumer"
prod_network_account_id    = "<PROVIDER_ACCOUNT_ID>"
shared_network_account_id  = "<PROVIDER_ACCOUNT_ID>"
vpc_id                     = "vpc-xxxxxxxxxxxxxxxxx"
EOF
terraform init && terraform apply
```

**Scale to 10+ consumers**: flip `ram_principals` to the Organization ARN,
run `aws ram enable-sharing-with-aws-organization` once from the mgmt
account, and new accounts auto-inherit the share — no provider-side
edits needed for future onboardings.

## When to split into more leaves

| Signal | Action |
|---|---|
| You have >30 prefix lists in one leaf | Split by service (network-prod-zpa, network-prod-offices) |
| Different teams should review different lists | Split by ownership → different folders, different CODEOWNERS |
| One region's lists need faster iteration than another | Separate leaves are already separate — you're good |
| `max_entries` pressure in one leaf affects another list's SGs | Split into smaller per-service lists, not per-folder |

## When NOT to split

- Don't split a single env-region into multiple folders just because it has
  multiple lists. Files-per-list within one leaf is the right granularity.
- Don't split a shared list into per-env copies if the values are identical
  — that's what `network-shared/` exists for.
- Don't pre-create empty leaves for envs that don't exist yet. Wait until
  you actually need them; copy-paste is cheap.
