resource "aws_ec2_managed_prefix_list" "offices" {
  name           = "offices-corp-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 2, max_entries = 15 -> 13 slots of headroom.
  max_entries = 15

  entry {
    cidr        = "203.0.113.0/24"
    description = "london-hq"
  }
  entry {
    cidr        = "198.51.100.0/24"
    description = "new-york-office"
  }

  tags = merge(local.common_tags, {
    Name        = "offices-corp-us-east-1"
    Service     = "Office"
    Group       = "corporate"
    Environment = "prod"
    Owner       = "it-team"
  })
}
