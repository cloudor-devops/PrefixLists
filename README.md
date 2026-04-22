# Managed Prefix Lists POC

Refactors external-access CIDR management (ZPA Connectors, CPC, Offices, vendor
whitelists, ...) from inline SG rules into **AWS VPC Managed Prefix Lists**,
shared cross-account via **AWS RAM**, and consumed via `owner_id + name_prefix`
data source discovery (no hard-coded `pl-xxx`).

## Documentation index

- **[TOPOLOGY.md](TOPOLOGY.md)** — the folder model, discovery contract, onboarding flows
- **[SCENARIOS.md](SCENARIOS.md)** — 9 real-world variations with concrete folder/tfvars changes
- **[CUSTOMER_GUIDE.md](CUSTOMER_GUIDE.md)** — one-page handoff guide for new customer engagements

## Layout

```
provider/
  network-prod/             # Prod-env network account
    us-east-1/              # <- leaf stack (versions.tf, ram.tf, *.tf, terraform.tfvars)
      zpa-connectors.tf
      cpc.tf
      offices.tf
      vendor-whitelist.tf
      ram.tf                # one aws_ram_resource_share + associations
    eu-west-1/              # sibling region, independent state
    ap-southeast-1/         # another region (template)
  network-staging/
    us-east-1/              # staging-env CIDRs + staging consumer account IDs
  network-dr/
    eu-west-1/              # DR region; mirror of prod in a different region
  network-shared/
    us-east-1/              # cross-env lists (offices, vendor APIs) for all envs

consumer/
  examples/
    workload-prod-us-east-1/     # prod workload SG wiring (uses prod + shared)
    workload-staging-us-east-1/  # staging workload SG wiring
    workload-dr-eu-west-1/       # DR workload SG wiring (single region)

modules/
  prefix-list-consumer/     # Data-source wrapper (owner_id OR tag filters)
```

## Leaf-folder rule

**Every folder containing `versions.tf` is an independent Terraform stack.** One
`init/plan/apply` per leaf. State never crosses leaves. See
[TOPOLOGY.md](TOPOLOGY.md) for the full model.

## How the provider team manages IPs

They edit Terraform directly. One resource per prefix list, one file per list.

```hcl
# provider/network-prod/us-east-1/zpa-connectors.tf
resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-prod-us-east-1"
  address_family = "IPv4"
  max_entries    = 20        # padded; see "Sizing" below

  entry {
    cidr        = "10.30.1.0/32"
    description = "zpa-connector-prod-us-east-1-a"
  }
  entry {
    cidr        = "10.30.2.0/32"
    description = "zpa-connector-prod-us-east-1-b"
  }

  tags = merge(local.common_tags, {
    Name        = "zpa-connectors-prod-us-east-1"
    Service     = "ZPA"
    Group       = "connectors"
    Environment = "prod"
    Owner       = "network-team"
  })
}
```

Adding/removing an IP = edit the `entry` blocks and `terraform apply`. Adding a
new list = new `.tf` file in the region folder, plus one line in that region's
`ram.tf` so the RAM share picks it up.

## Sizing: `max_entries` padding

`max_entries` is **immutable without a list resize** and every resize forces every
consumer SG to have free rule slots — so under-sizing is a trap. Pad generously up
front.

Rule of thumb: `max_entries ≈ current_entries × 2`, floor at `15`–`20`. Document
the current count in a comment next to `max_entries` so the next editor sees the
headroom at a glance:

```hcl
# PADDING: current entries = 3, max_entries = 20 -> 17 slots of headroom.
max_entries = 20
```

This constraint drives **splitting by group/region** rather than one giant list:
each consumer SG only reserves quota for the list it actually attaches.

## Dynamic discovery (the selling point)

Consumers find prefix lists by `owner_id + name_prefix` — no hard-coded `pl-xxx`:

```hcl
module "zpa_pl" {
  source      = "../modules/prefix-list-consumer"
  owner_id    = var.prod_network_account_id
  name_prefix = "zpa-connectors-"
  # Region is implicit from the aws provider — API is region-scoped.
}
```

**Why `owner_id + name_prefix` and not tag filters**: AWS RAM does not
propagate owner-applied tags to consumer accounts for Managed Prefix Lists.
Tag-based filtering (`service = "ZPA"`) only works for locally-owned lists
(same-account lookups). `owner_id + name_prefix` works in every case.

Every prefix list is still tagged on the provider side for console
legibility, audit, and cost allocation:

| Tag          | Example          |
|--------------|------------------|
| `Service`    | `ZPA`            |
| `Group`      | `connectors`     |
| `Environment`| `prod`           |
| `Region`     | `us-east-1`      |
| `Owner`      | `network-team`   |
| `ManagedBy`  | `terraform`      |
| `Name`       | `zpa-connectors-prod-us-east-1` |

## Cross-account (RAM) — Step 3

Each region's `ram.tf` creates an `aws_ram_resource_share`, associates every
prefix list via `local.shared_prefix_list_arns`, and attaches each consumer
account principal. Gated behind `var.ram_enabled`, default `false`, so Steps 1+2
deliver value in a single account first.

Enable via `terraform.tfvars` (see `provider/<account-alias>/<region>/terraform.tfvars.example`):
```hcl
ram_enabled    = true
ram_principals = ["111111111111", "222222222222"]
```
Then `terraform apply`.

## Run book

```bash
# First time per leaf
cd provider/network-prod/us-east-1
terraform init
terraform plan
terraform apply

# Daily edit loop (any leaf, any list)
$EDITOR provider/network-prod/us-east-1/zpa-connectors.tf
terraform apply
```

## Replicating this repo for your own environment

No customer-specific values are baked into the code. All environment-specific
settings live in gitignored `terraform.tfvars` files, with tracked
`terraform.tfvars.example` templates showing what to fill in.

### 1. Clone and pick your region

```bash
git clone https://github.com/cloudor-devops/PrefixLists.git
cd PrefixLists
```

The repo ships with four provider account aliases covering common real-world
topologies: `network-prod/`, `network-staging/`, `network-dr/`, and
`network-shared/`. Delete the ones you don't need, rename/copy to match your
actual account structure. See [TOPOLOGY.md](TOPOLOGY.md) and
[SCENARIOS.md](SCENARIOS.md) for the full model and worked examples.

### 2. Author your prefix lists

Replace the example CIDRs in `provider/<account-alias>/<region>/*.tf` with your real ones:
- `zpa-connectors.tf`, `cpc.tf`, `offices.tf` are the example groupings —
  rename / add / remove as your services dictate.
- Update `max_entries` (with `current × 2`, floor 15-20) and the `# PADDING`
  comment.
- Tag `Service` / `Group` / `Environment` / `Owner` consistently — they're
  used by the consumer discovery when prefix lists are **locally** owned.
- Add each list's ARN to `local.shared_prefix_list_arns` in `ram.tf`.

### 3. Configure RAM sharing

```bash
cd provider/network-prod/us-east-1
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
# set ram_principals to your consumer account IDs
terraform init
terraform apply
```

If the consumer accounts are not in the same AWS Organization, accept the
RAM invitation from each consumer account once:
```bash
aws ram get-resource-share-invitations --profile <consumer> --region <region>
aws ram accept-resource-share-invitation \
  --profile <consumer> --region <region> \
  --resource-share-invitation-arn <arn-from-above>
```

### 4. Wire consumer workloads

Pick a consumer example that matches your topology (see `consumer/examples/`):
```bash
cd consumer/examples/workload-prod-us-east-1
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
# set provider account IDs, vpc_id, optionally aws_profile
terraform init && terraform apply
```

The examples are reference stacks. In real workloads, import
`modules/prefix-list-consumer` directly from wherever your SG lives:

```hcl
module "zpa_pl" {
  source      = "git::https://github.com/cloudor-devops/PrefixLists.git//modules/prefix-list-consumer?ref=main"
  owner_id    = "111111111111"        # the provider account ID
  name_prefix = "zpa-connectors-"     # matches your provider naming convention
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

For **locally-owned** lists (single-account POC, no RAM), use the tag filter
mode instead — `service`, `environment`, `group` — since
owner-applied tags are visible on same-account lookups.

### What to change per customer

| File | Change |
|---|---|
| `provider/<alias>/<region>/*.tf` | Replace example CIDRs, descriptions, names, owners |
| `provider/<alias>/<region>/ram.tf` | Update `local.shared_prefix_list_arns` as you add/remove lists |
| `provider/<alias>/<region>/terraform.tfvars` | Set `ram_principals` (gitignored, create from `.example`) |
| `consumer/examples/<workload>/terraform.tfvars` | Set provider account IDs, `vpc_id`, optional `aws_profile` |
| `consumer/examples/<workload>/main.tf` | Update `name_prefix` values in module blocks to match your naming |

