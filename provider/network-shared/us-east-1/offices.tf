# Corporate office IPs. Every workload across prod/staging/dr/dev typically
# needs to allow office traffic (admin SSH, VPN termination, internal tools).
# Living in a shared leaf means a single edit updates every environment.

resource "aws_ec2_managed_prefix_list" "offices" {
  name           = "offices-corp-shared-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 4, max_entries = 20 -> 16 slots of headroom.
  max_entries = 20

  entry {
    cidr        = "203.0.113.0/24"
    description = "london-hq"
  }
  entry {
    cidr        = "198.51.100.0/24"
    description = "new-york-office"
  }
  entry {
    cidr        = "192.0.2.0/24"
    description = "tel-aviv-office"
  }
  entry {
    cidr        = "203.0.114.0/24"
    description = "tokyo-office"
  }

  tags = merge(local.common_tags, {
    Name    = "offices-corp-shared-us-east-1"
    Service = "Office"
    Group   = "corporate"
    Owner   = "it-team"
  })
}
