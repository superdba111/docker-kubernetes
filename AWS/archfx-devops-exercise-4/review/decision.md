# Decision: export-service for Friday

To: Data Products (author + manager), Platform EM · From: Security Review

## Ship the PR as written Friday? **No.**

- **Outside the boundary:** commercial DR, sentry.io and Docker Hub move
  customer data or images outside the boundary. These are significant changes
  with 10+ business days' notice.
- **Cross-tenant access:** any user, or anyone at all, could download any
  tenant's export, and CI gave fork PRs govhigh deploy credentials.

## PR A: merge a non-deploying foundation, not the export feature

`review/maxwell-li` retains application security fixes, dependency locks and
tests. The export workflow only tests on a hosted runner: no AWS identity,
build or publishing. Export Terraform and Helm assets are removed from active
paths and preserved as `.txt` proposals in `review/deferred/` for PR B. There
is no export workload, new storage or customer enablement in PR A.

**Merge PR A** after exposed CI credentials are revoked (with an activity
review), the DB password is rotated, required reviews and checks pass, and
Platform confirms no existing export state/release or separate automation
would deploy this source. This is not a claim that those actions happened.
A5 is excluded from PR A by removing the storage change, not waived by a flag.

## PR B: production export remains no-ship Friday

Before restoring deployment assets or enabling this customer's tenant:

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

**Deferred alternative, if only worker review slips:** one operator-run export under
**RA-2026-016**, with a reviewed script, the tenant-scoped job role, two
people, portal delivery and an audit record. It needs **both** Security Review
and Platform EM approval and POA&M registration (policy §4). All other gates
still apply, including reviewed migration/schema and completed-job registration.
PR A provides no executable fallback. Without boundary clearance, neither option ships Friday;
the DP manager must renegotiate the milestone, not bypass the gate.

## Owners

| Who | What | By |
|---|---|---|
| Platform + Security | Revoke CI credentials; CloudTrail | Today |
| Data Products | Rotate DB password (PR A); worker + migrate code (PR B) | Tue |
| DP manager | Reduced scope with the program office; plan vs. RA-2026-016 | Tue noon |
| Platform + Security, with ISSO / FedRAMP partner | Gate 4; record and advance notice | Start today |
| Platform | Confirm PR A non-deployment scope and no existing export state/release | Before merge |
| Platform / Ingest / Portal | PR B gates 2 and 5; libpq answer | Wed |
| Security Review, then Platform EM | Worker re-review; sign RA-2026-014/015/016 | Wed / Thu |
