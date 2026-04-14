# RAM POC — Execution Log

End-to-end test of the Managed Prefix List + AWS RAM cross-account flow.

## Accounts

| Role     | Account ID     | AWS Profile | Notes |
|----------|----------------|-------------|-------|
| Provider | `492094933642` | default     | Owns + edits the prefix lists |
| Consumer | `498374411602` | `pilot`     | Receives the lists read-only via RAM |

Region: `us-east-1`. Accounts are **not** in the same AWS Organization, so
`allow_external_principals = true` is required.

## Starting state

Two prefix lists already existed in the provider account from the earlier apply:

| Name                              | ID                     | Entries | max_entries |
|-----------------------------------|------------------------|---------|-------------|
| `zpa-connectors-prod-us-east-1`   | `pl-0bc67b13bcf8a57b6` | 2       | 20          |
| `offices-corp-us-east-1`          | `pl-0986dc6d9d2ced6a9` | 2       | 15          |

---

## Phase 1 — Share (provider account)

Flipped defaults in `provider/us-east-1/variables.tf`:
```hcl
variable "ram_enabled"    { default = true }
variable "ram_principals" { default = ["498374411602"] }
```

Ran:
```bash
cd provider/us-east-1
terraform plan -out=tfplan
terraform apply tfplan
```

**Plan:** `4 to add, 0 to change, 0 to destroy`
- `aws_ram_resource_share.this[0]`
- `aws_ram_resource_association.this["zpa-connectors"]`
- `aws_ram_resource_association.this["offices"]`
- `aws_ram_principal_association.this["498374411602"]`

**Result:** apply complete. RAM share ARN:
```
arn:aws:ram:us-east-1:492094933642:resource-share/5b03dc78-e465-4c7b-83b6-c72d2d7287b8
```

---

## Phase 2 — Accept (pilot account)

```bash
aws ram get-resource-share-invitations --profile pilot --region us-east-1
```
One `PENDING` invitation for `managed-prefix-lists-us-east-1`.

```bash
aws ram accept-resource-share-invitation \
  --profile pilot --region us-east-1 \
  --resource-share-invitation-arn arn:aws:ram:us-east-1:492094933642:resource-share-invitation/69bff5fa-17a5-4801-8cac-c2164d987e2c
```
Status: `ACCEPTED`. One-time handshake — all future updates propagate automatically.

---

## Phase 3 — Verify (pilot account)

```bash
aws ec2 describe-managed-prefix-lists \
  --profile pilot --region us-east-1 \
  --filters 'Name=owner-id,Values=492094933642' \
  --query 'PrefixLists[].[PrefixListName,PrefixListId]' --output table
```
```
+--------------------------------+------------------------+
|  zpa-connectors-prod-us-east-1 |  pl-0bc67b13bcf8a57b6  |
|  offices-corp-us-east-1        |  pl-0986dc6d9d2ced6a9  |
+--------------------------------+------------------------+
```
Both lists visible in the pilot account, with `OwnerId = 492094933642` — read-only
from here (AWS rejects `modify-managed-prefix-list` calls from the consumer side).

### ⚠️ Critical finding: tags do NOT propagate across RAM

A key premise of the original design was **tag-based discovery**: consumer filters
by `Service=ZPA` and finds the right list regardless of ID. This does not work
for RAM-shared prefix lists:

```bash
aws ec2 describe-managed-prefix-lists \
  --profile pilot --region us-east-1 \
  --filters 'Name=tag:Service,Values=ZPA'
# -> { "PrefixLists": [] }
```
Full describe output also shows `"Tags": []` for the shared lists from the pilot
side. AWS does not propagate the **owner's** tags to the consumer view — this is
documented AWS behavior for RAM-shared resources.

**Implication for the consumer module:** the tag-filter approach in
`modules/prefix-list-consumer` only works for **locally-owned** prefix lists, not
RAM-shared ones. Needs one of:

1. **Owner-id-based discovery** (simplest) — filter by `Name=owner-id,Values=<provider-account-id>`, optionally combined with a name prefix like `zpa-connectors-*`. Works today, no extra moving parts.
2. **Consumer-side re-tagging** — the pilot team applies their own tags to each shared list (`aws ec2 create-tags`) via a small TF stack. One-time friction, then the existing tag filter works unchanged.
3. **Name-convention discovery** — filter purely on `prefix-list-name` patterns (`zpa-*`). Works today but couples consumer to provider's naming scheme.

**Recommendation:** go with option 1. Update `modules/prefix-list-consumer` to accept a `provider_owner_id` variable and combine it with an optional name prefix.

---

## Phase 4 — Killer demo: add an IP, watch it propagate

### Provider side
Edited `provider/us-east-1/zpa-connectors.tf`, added:
```hcl
entry {
  cidr        = "10.30.3.0/32"
  description = "zpa-connector-prod-us-east-1-c"
}
```
Bumped the padding comment to `current = 3`. Ran `terraform apply` — `1 to change, 0 to add`. ~5 seconds.

Output confirms:
```
"zpa-connectors" = {
  "current_entries" = 3
  "max_entries"     = 20
  ...
}
```

### Pilot side — **no Terraform run, no SG edit, nothing**
```bash
aws ec2 get-managed-prefix-list-entries \
  --profile pilot --region us-east-1 \
  --prefix-list-id pl-0bc67b13bcf8a57b6 --output table
```
```
|     Cidr      |           Description            |
+---------------+----------------------------------+
|  10.30.1.0/32 |  zpa-connector-prod-us-east-1-a  |
|  10.30.2.0/32 |  zpa-connector-prod-us-east-1-b  |
|  10.30.3.0/32 |  zpa-connector-prod-us-east-1-c  |
```

The new entry appears in the pilot account **instantly**. Any Security Group in
the pilot account that had `prefix_list_id = pl-0bc67b13bcf8a57b6` would now
allow traffic from `10.30.3.0/32` without any consumer-side action.

**This is the entire pitch in one command.**

---

## Summary of findings

| # | Finding | Status |
|---|---------|--------|
| 1 | RAM share creation + principal association from HCL works cleanly | ✅ Works |
| 2 | Cross-account sharing works even without an AWS Organization (`allow_external_principals = true` + invitation accept) | ✅ Works |
| 3 | Shared prefix lists appear read-only in the consumer account, owner-id stamped as the provider account | ✅ Works |
| 4 | Updates to the prefix list on the provider side propagate to the consumer **instantly** with zero consumer-side action | ✅ Works — the killer demo |
| 5 | **Owner-applied tags do NOT propagate across RAM** — the current tag-filter consumer module will not find RAM-shared lists | ⚠️ Gotcha — needs fix |

## Next steps

1. **Fix the consumer module** — add `provider_owner_id` support and/or a name-pattern filter, because pure tag filtering won't work across RAM.
2. **Pitch meeting** — demo Phase 4 live. It's ~30 seconds end-to-end and makes the value immediately obvious.
3. **Document the invitation-accept step** as a one-time operation per consumer account in the onboarding runbook. Accounts in the same AWS Organization skip it entirely (auto-accept), so if the target teams are already in the org this whole friction disappears.
4. **Decide on RAM scope for prod** — current POC shares with explicit account IDs. At scale, prefer `ram_principals = [<org-arn>]` so new accounts inherit the share automatically.
