resource "aws_ec2_managed_prefix_list" "offices" {
  name           = "offices-corp-eu-west-1"
  address_family = "IPv4"

  # PADDING: current entries = 3, max_entries = 15 -> 12 slots of headroom.
  max_entries = 15

  entry {
    cidr        = "203.0.113.0/24"
    description = "london-hq"
  }
  entry {
    cidr        = "198.51.100.0/24"
    description = "tel-aviv-office"
  }
  entry {
    cidr        = "192.0.2.0/24"
    description = "berlin-office"
  }

  tags = merge(local.common_tags, {
    Name        = "offices-corp-eu-west-1"
    Service     = "Office"
    Group       = "corporate"
    Environment = "prod"
    Owner       = "it-team"
  })
}
