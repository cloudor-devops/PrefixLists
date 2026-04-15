# Vendor API egress whitelist. Same IPs are needed across prod/staging/dr
# (when a workload needs Stripe in staging, it still hits the same Stripe
# endpoints). Shared leaf avoids triple maintenance.

resource "aws_ec2_managed_prefix_list" "vendor_apis" {
  name           = "vendor-apis-shared-us-east-1"
  address_family = "IPv4"

  # PADDING: current entries = 3, max_entries = 30 -> 27 slots of headroom.
  # Vendor lists grow unpredictably; over-pad generously.
  max_entries = 30

  entry {
    cidr        = "203.0.113.128/25"
    description = "stripe-api"
  }
  entry {
    cidr        = "198.51.100.128/25"
    description = "sendgrid-api"
  }
  entry {
    cidr        = "192.0.2.128/25"
    description = "datadog-intake"
  }

  tags = merge(local.common_tags, {
    Name    = "vendor-apis-shared-us-east-1"
    Service = "VendorAPIs"
    Group   = "egress"
    Owner   = "security-team"
  })
}
