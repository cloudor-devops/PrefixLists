resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-staging-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 2, max_entries = 15 -> 13 slots of headroom.
  # Staging typically has fewer connectors than prod; tighter padding is fine.
  max_entries = 15

  entry {
    cidr        = "10.130.1.0/32"
    description = "zpa-connector-staging-us-east-1-a"
  }
  entry {
    cidr        = "10.130.2.0/32"
    description = "zpa-connector-staging-us-east-1-b"
  }

  tags = merge(local.common_tags, {
    Name        = "zpa-connectors-staging-us-east-1"
    Service     = "ZPA"
    Group       = "connectors"
    Environment = "staging"
    Owner       = "network-team"
  })
}
