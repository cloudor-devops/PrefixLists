resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-prod-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 3, max_entries = 20 -> 17 slots of headroom.
  # max_entries is immutable without a list resize, and every resize forces
  # consumer SGs to have free rule slots. Pad generously up front.
  max_entries = 20

  entry {
    cidr        = "10.30.1.0/32"
    description = "zpa-connector-prod-us-east-1-a"
  }
  entry {
    cidr        = "10.30.2.0/32"
    description = "zpa-connector-prod-us-east-1-b"
  }
  entry {
    cidr        = "10.30.3.0/32"
    description = "zpa-connector-prod-us-east-1-c"
  }

  tags = merge(local.common_tags, {
    Name        = "zpa-connectors-prod-us-east-1"
    Service     = "ZPA"
    Group       = "connectors"
    Environment = "prod"
    Owner       = "network-team"
  })
}
