resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-dr-eu-west-1"
  address_family = "IPv4"

  # PADDING: current entries = 2, max_entries = 20 -> 18 slots of headroom.
  # DR mirrors prod's shape; keep padding consistent so failover drills don't
  # surface quota surprises.
  max_entries = 20

  entry {
    cidr        = "10.240.1.0/32"
    description = "zpa-connector-dr-euw1-a"
  }
  entry {
    cidr        = "10.240.2.0/32"
    description = "zpa-connector-dr-euw1-b"
  }

  tags = merge(local.common_tags, {
    Name        = "zpa-connectors-dr-eu-west-1"
    Service     = "ZPA"
    Group       = "connectors"
    Environment = "dr"
    Owner       = "network-team"
  })
}
