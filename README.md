# Managed Prefix Lists POC

Refactors external-access CIDR management (ZPA Connectors, CPC, Offices, ...) from
inline SG rules into **AWS VPC Managed Prefix Lists**, shared cross-account via **AWS
RAM**, and consumed via **tag-based data source discovery** (no hard-coded `pl-xxx`).

## Layout

```
provider/
  us-east-1/                # Root stack: one prefix list per .tf file
    versions.tf
    providers.tf
    variables.tf            # ram_enabled, ram_principals
    _tags.tf                # common tags
    zpa-connectors.tf       # aws_ec2_managed_prefix_list.zpa_connectors
    ram.tf                  # aws_ram_resource_share + associations
    outputs.tf
  eu-west-1/                # Same shape, multiple lists
    zpa-connectors.tf
    cpc.tf
    offices.tf
    ram.tf
    ...
modules/
  prefix-list-consumer/     # Tag-filtered data source wrapper (consumer side)
consumer/                   # Example consumer root stack (workload account)
```

## Per-region stacks

Prefix Lists and RAM shares are **strictly per-region**. Each region is its own
root stack — one `terraform init` / `apply` per region, independent state. No
provider aliases, no workspaces, no filtering logic: `cd provider/us-east-1 &&
terraform apply`.

## How the provider team manages IPs

They edit Terraform directly. One resource per prefix list, one file per list.

```hcl
# provider/us-east-1/zpa-connectors.tf
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

## Tag-based discovery (the selling point)

Every list is tagged with:

| Tag          | Example          |
|--------------|------------------|
| `Service`    | `ZPA`            |
| `Group`      | `connectors`     |
| `Environment`| `prod`           |
| `Region`     | `eu-west-1`      |
| `Owner`      | `network-team`   |
| `ManagedBy`  | `terraform`      |
| `Name`       | `zpa-connectors-prod-eu-west-1` |

Consumer looks up by tags — no IDs, no cross-region leakage:

```hcl
module "zpa_pl" {
  source      = "../modules/prefix-list-consumer"
  service     = "ZPA"
  environment = "prod"
  # Region is implicit from the aws provider — API is region-scoped.
}
```

## Cross-account (RAM) — Step 3

Each region's `ram.tf` creates an `aws_ram_resource_share`, associates every
prefix list via `local.shared_prefix_list_arns`, and attaches each consumer
account principal. Gated behind `var.ram_enabled`, default `false`, so Steps 1+2
deliver value in a single account first.

Enable via `terraform.tfvars` (see `provider/<region>/terraform.tfvars.example`):
```hcl
ram_enabled    = true
ram_principals = ["111111111111", "222222222222"]
```
Then `terraform apply`.

## Run book

```bash
# First time per region
cd provider/us-east-1
terraform init
terraform plan
terraform apply

# Daily edit loop
$EDITOR provider/us-east-1/zpa-connectors.tf
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

The repo ships with two example regions: `provider/us-east-1/` and
`provider/eu-west-1/`. Delete the one you don't need, or rename/copy to your
target region. Update `providers.tf` inside to your region name.

### 2. Author your prefix lists

Replace the example CIDRs in `provider/<region>/*.tf` with your real ones:
- `zpa-connectors.tf`, `cpc.tf`, `offices.tf` are the example groupings —
  rename / add / remove as your services dictate.
- Update `max_entries` (with `current × 2`, floor 15-20) and the `# PADDING`
  comment.
- Tag `Service` / `Group` / `Environment` / `Owner` consistently — they're
  used by the consumer discovery when prefix lists are **locally** owned.
- Add each list's ARN to `local.shared_prefix_list_arns` in `ram.tf`.

### 3. Configure RAM sharing

```bash
cp provider/us-east-1/terraform.tfvars.example provider/us-east-1/terraform.tfvars
$EDITOR provider/us-east-1/terraform.tfvars
# set ram_principals to your consumer account IDs
```

Then:
```bash
cd provider/us-east-1
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

```bash
cp consumer/terraform.tfvars.example consumer/terraform.tfvars
$EDITOR consumer/terraform.tfvars
# set provider_owner_id, vpc_id, optionally aws_profile
```

`consumer/main.tf` is an example. In real workloads, import
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
| `provider/<region>/*.tf` | Replace example CIDRs, descriptions, names, owners |
| `provider/<region>/ram.tf` | Update `local.shared_prefix_list_arns` as you add/remove lists |
| `provider/<region>/terraform.tfvars` | Set `ram_principals` (gitignored, create from `.example`) |
| `consumer/terraform.tfvars` | Set `provider_owner_id`, `vpc_id`, optional `aws_profile` |
| `consumer/main.tf` | Update `name_prefix` values in module blocks to match your naming |
| `RAM-POC.md` | Historical execution log from the original run — treat as reference, not config |

