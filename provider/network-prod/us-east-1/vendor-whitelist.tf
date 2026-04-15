resource "aws_ec2_managed_prefix_list" "vendor_apis" {
  name           = "vendor-apis-prod-us-east-1"
  address_family = "IPv4"

  # Vendor APIs the prod workloads egress to. Reviewed by security team
  # on each change.
  #
  # PADDING: current entries = 3, max_entries = 25 -> 22 slots of headroom.
  # Higher padding because vendor lists grow unpredictably over time.
  max_entries = 25

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
    Name        = "vendor-apis-prod-us-east-1"
    Service     = "VendorAPIs"
    Group       = "egress"
    Environment = "prod"
    Owner       = "security-team"
  })
}
