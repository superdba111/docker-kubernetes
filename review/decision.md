# Decision: export-service for Friday

To: Data Products (PR author + manager), Platform Engineering Manager
From: Security Review · Monday

## Can this PR ship Friday? **No, not as written.**

Three parts of the design move customer data (CUI) or our supply chain outside
the govhigh authorization boundary:
- **DR copy:** exports are copied to the commercial DR account.
- **Errors and traces:** they go to sentry.io, with user data included.
- **Images:** they're served from Docker Hub.

These are *significant changes*. Security Review can't approve them, and they
need 10+ business days' notice to our FedRAMP partner. That alone rules out
Friday for the design as written.

Separately, the code as written lets **any user, or anyone at all, download any
tenant's export**. The JWT isn't verified, there's no tenant check, and the
bucket is readable by anyone who sends the portal's Referer header. The CI
workflow also gives govhigh deploy credentials to code from fork PRs.

## Merge vs. enable

- **Merge:** yes, in the **disabled** state, after required reviews (policy §2
  Pre-prod: "may merge behind a disabled flag").
- **Enable for any tenant:** no, not until the items below are done.

## What *can* ship Friday: a reduced, in-boundary export

The customer needs Parquet files of their own data. Nothing about that requires
leaving the boundary, so taking the cross-boundary pieces out removes the
10-day notice. Branch `review/maxwell-li` already does most of the code work:
- **Removed:** commercial DR, sentry.io, Docker Hub in CI.
- **Tenant-checked API:** JWT verified; downloads scoped to the caller's tenant.
- **Bucket:** private and KMS-encrypted.
- **Identities:** separate least-privilege roles for the API and worker. The
  worker's own role can't read customer data; each job runs under a role
  limited to that job's tenant.
- **Pods and secrets:** no cluster-admin; secrets from Secrets Manager.
- **CI:** OIDC + ECR, with a scan gate that blocks; PR code never runs on
  the govhigh runner.
- **Image and network:** hardened FIPS base image, hash-locked dependencies,
  no public apt repos, no internet egress, egress only to named security groups.
- **Delivery:** streamed through the portal by default. Presigned S3 links
  can't be turned on without an ISSO approval reference.
- **Feature flag:** per-tenant, **off by default**. With no tenant enabled,
  the worker runs 0 replicas and migrations don't run.

What's left before it can be enabled:

1. **Today:** revoke `GOVHIGH_DEPLOY_AWS_*` and `DOCKERHUB_TOKEN` and check
   CloudTrail. Rotate the RDS password, which is in git history.
2. **Worker code into review (Tue).** `worker` and `migrate` aren't in the PR.
   The worker must take the tenant from the DB job row and do all S3 work with
   the tenant-scoped `export-job` credentials (review B4; the IAM side is
   done). Ingest team to confirm `raw-ingest` keys are tenant-prefixed.
   **No worker review, no launch.** It's the component that reads customer
   data and runs pyarrow on it.
3. **Platform (Wed):**
   - **Pipeline:** OIDC push role and ECR repo; confirm the govhigh runner is
     ephemeral with no ambient credentials.
   - **Terraform:** run `terraform plan`.
   - **Namespace:** confirm the `exports` namespace has default-deny.
   - **Rescan:** the scan gate must be clean (fixable Critical/High).
   - **Inputs:** approved pip mirror (the build now fails without one); names
     of the endpoint and RDS security groups; review of the ingress rules the
     branch adds to baseline security groups; confirm security groups for pods
     (`ENABLE_POD_ENI`) so the pod security group actually applies.
4. **FIPS for DB TLS (Wed), a production gate.** The Postgres driver bundles its
   own OpenSSL. Either Platform confirms libpq in the hardened image and we
   switch drivers, or Security + the Platform EM approve RA-2026-015. The draft
   grants nothing until both sign.
5. **Portal team (Wed):** confirm the in-cluster JWKS service and the token
   issuer.
6. **Delivery path.** Streaming through the portal is already the default, so
   Friday doesn't depend on the ISSO. Presigned S3 is an optional later switch
   that needs the ISSO's approval (review A4). Each click gets a fresh stream,
   which also handles the weekend air-gap transfer.

It merges with the flag off. It's switched on for **this one customer's tenant
only**, and only after items 1–5.

**If that slips:** an operator runs a one-off export for this customer's tenant
inside the boundary, and the customer collects it **through the portal**.
Presigned S3 is used only if the ISSO has approved it. The export is logged and
audited, and the delivery is recorded. I'd approve that as a documented one-off.
It meets the milestone without launching a self-service feature.

**Not Friday:** GovCloud-to-GovCloud DR (only if the contract requires it),
portal previews (rebuilt server-side), tenant ConfigMap seeding (needs its own
RBAC design).

## Owners and asks

| Who | What | By |
|---|---|---|
| Platform + Security | Revoke CI credentials; CloudTrail check | Today |
| Data Products (author) | Rotate DB password; worker + migrate code into the PR with B4; confirm nobody needs `export-config` ConfigMaps and `migrate` doesn't need `psql`; update design doc | Tue EOD |
| Data Products manager | Agree the reduced scope with the program office; choose plan vs. one-off by **Tue noon** | Tue noon |
| Platform | OIDC role, ECR repo, pip mirror, SG names, runner isolation check, libpq in hardened image (for RA-2026-015), `terraform plan`, namespace default-deny, first build + rescan | Wed |
| Ingest team | Confirm `raw-ingest` key layout is `<tenant_id>/...` | Tue |
| Portal team | In-cluster JWKS service name and token issuer | Wed |
| ISSO / compliance | Only if presigned S3 is wanted: is it covered by the SSP? Not on Friday's critical path | When convenient |
| Security Review (me) | Same-day re-review of the worker and the final diff; co-sign RA-2026-014 and RA-2026-015 (or close 015 by remediation) | Wed–Thu |
| Platform Eng Manager | Approve RA-2026-014 and RA-2026-015; sponsor a boundary change record only if commercial DR is still wanted | Thu |
