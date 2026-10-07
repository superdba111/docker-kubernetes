# Decision: export-service for Friday

To: Data Products (author + manager), Platform EM · From: Security Review

## Ship the PR as written Friday? **No.**

- **Outside the boundary:** commercial DR, sentry.io and Docker Hub move
  customer data or images outside the boundary. These are significant changes
  with 10+ business days' notice.
- **Cross-tenant access:** any user, or anyone at all, could download any
  tenant's export, and CI gave fork PRs govhigh deploy credentials.

## Reduced scope: not cleared for Friday

`review/maxwell-li` removes the cross-boundary pieces and fixes the code
technical Blockers. The new exports bucket remains a **Blocker (boundary)**
under §6, even in GovCloud. Delivery streams through the portal; the flag is **off
by default**.

**Merge** (flag off) after leaked CI credentials are revoked (with a CloudTrail
check), the RDS password is rotated, required reviews are done, and A5 is
resolved through the boundary-change process (review.md). B4's worker-code check
is Pre-prod: with the flag off, the worker runs 0 replicas.

**Enable** for this customer's tenant only after:

1. **Worker + migrate code reviewed (Tue).** The IAM setup supports
   per-tenant credentials for each job. Whether the worker uses them is
   unverified until then.
2. **Platform build (Wed):** SBOM, clean scan, `terraform plan`, endpoints,
   ECR, mirror, runner isolation.
3. **DB TLS FIPS (Wed):** system libpq, or RA-2026-015 approved.
4. **Boundary change (start today):** Platform + Security record the new storage
   location and notify the FedRAMP partner and authorizing officials before
   deployment; satisfy the required lead time (typically 10+ business days).
   Friday is not viable unless existing authorization explicitly covers this
   storage and flow, with evidence confirmed through that process. An ISSO
   interpretation or risk exception alone cannot waive §6.
5. **Ingest/Portal:** tenant-prefixed keys; JWKS service.

**If only worker review slips:** one operator-run export for this tenant under
**RA-2026-016**, with a reviewed script, the tenant-scoped job role, two
people, portal delivery and an audit record. It needs **both** Security Review
and Platform EM approval and POA&M registration (policy §4). All other gates
still apply, including reviewed migration/schema and completed-job registration
for portal download. Without boundary clearance, neither option ships Friday;
the DP manager must renegotiate the milestone, not bypass the gate.

## Owners

| Who | What | By |
|---|---|---|
| Platform + Security | Revoke CI credentials; CloudTrail | Today |
| Data Products | Rotate DB password; worker + migrate code | Tue |
| DP manager | Reduced scope with the program office; plan vs. RA-2026-016 | Tue noon |
| Platform + Security, with ISSO / FedRAMP partner | Gate 4; record and advance notice | Start today |
| Platform / Ingest / Portal | Gates 2 and 5; libpq answer | Wed |
| Security Review, then Platform EM | Worker re-review; sign RA-2026-014/015/016 | Wed / Thu |
