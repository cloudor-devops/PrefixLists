resource "aws_ec2_managed_prefix_list" "zpa_connectors" {
  name           = "zpa-connectors-prod-ap-southeast-1"
  address_family = "IPv4"

  # PADDING: current entries = 2, max_entries = 20 -> 18 slots of headroom.
  max_entries = 20

  entry {
    cidr        = "10.50.1.0/32"
    description = "zpa-connector-prod-apse1-a"
  }
  entry {
    cidr        = "10.50.2.0/32"
    description = "zpa-connector-prod-apse1-b"
  }

  tags = merge(local.common_tags, {
    Name        = "zpa-connectors-prod-ap-southeast-1"
    Service     = "ZPA"
    Group       = "connectors"
    Environment = "prod"
    Owner       = "network-team"
  })
}
