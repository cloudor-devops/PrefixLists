resource "aws_ec2_managed_prefix_list" "cpc" {
  name           = "cpc-endpoints-prod-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 2, max_entries = 15 -> 13 slots of headroom.
  max_entries = 15

  entry {
    cidr        = "10.20.0.0/24"
    description = "cpc-endpoint-prod-us-east-1-primary"
  }
  entry {
    cidr        = "10.20.1.0/24"
    description = "cpc-endpoint-prod-us-east-1-secondary"
  }

  tags = merge(local.common_tags, {
    Name        = "cpc-endpoints-prod-us-east-1"
    Service     = "CPC"
    Group       = "endpoints"
    Environment = "prod"
    Owner       = "platform-team"
  })
}
