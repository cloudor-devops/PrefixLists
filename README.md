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

Enable with:
```bash
terraform apply \
  -var 'ram_enabled=true' \
  -var 'ram_principals=["111111111111","222222222222"]'
```

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
