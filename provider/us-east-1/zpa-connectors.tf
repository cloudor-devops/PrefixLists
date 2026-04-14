resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-prod-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 3, max_entries = 20 -> 17 slots of headroom.
  # max_entries is immutable without a list resize, and every resize forces
  # consumer SGs to have free rule slots. Pad generously up front.
  max_entries = 20

  entry {
    cidr        = "172.16.0.0/12"
    description = "zpa-connector-prod-us-east-1-a"
  }
  entry {
    cidr        = "10.24.136.0/21"
    description = "zpa-connector-prod-us-east-1-b"
  }
  entry {
    cidr        = "10.24.16.0/21"
    description = "zpa-connector-prod-us-east-1-c"
  }
  entry {
    cidr        = "10.24.8.0/21"
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
