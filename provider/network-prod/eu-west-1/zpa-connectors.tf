resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-prod-eu-west-1"
  address_family = "IPv4"

  # PADDING: current entries = 3, max_entries = 20 -> 17 slots of headroom.
  max_entries = 20

  entry {
    cidr        = "10.10.1.0/32"
    description = "zpa-connector-prod-eu-west-1-a"
  }
  entry {
    cidr        = "10.10.2.0/32"
    description = "zpa-connector-prod-eu-west-1-b"
  }
  entry {
    cidr        = "10.10.3.0/32"
    description = "zpa-connector-prod-eu-west-1-c"
  }

  tags = merge(local.common_tags, {
    Name        = "zpa-connectors-prod-eu-west-1"
    Service     = "ZPA"
    Group       = "connectors"
    Environment = "prod"
    Owner       = "network-team"
  })
}
