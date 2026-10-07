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

## What *can* ship Friday: a reduced, in-boundary export

The customer needs Parquet files of their own data. Nothing about that requires
leaving the boundary, so taking the cross-boundary pieces out removes the
10-day notice. Branch `review/maxwell-li` already does most of the code work:
- **Removed:** commercial DR, sentry.io, Docker Hub in CI.
- **Tenant-checked API:** JWT verified; downloads scoped to the caller's tenant.
- **Bucket:** private and KMS-encrypted.
- **Identities:** separate least-privilege roles for the API and worker.
- **Pods and secrets:** no cluster-admin; secrets from Secrets Manager.
- **CI:** OIDC + ECR, with a scan gate that blocks.

What's left before it can be enabled:

1. **Today:** revoke `GOVHIGH_DEPLOY_AWS_*` and `DOCKERHUB_TOKEN` and check
   CloudTrail. Rotate the RDS password, which is in git history.
2. **Worker code into review (Tue).** `worker` and `migrate` aren't in the PR.
   The worker must take the tenant from the DB job row and process each job
   with credentials scoped to that tenant's prefix (review B4). **No worker
   review, no launch.** It's the one component that reads every tenant's data
   and runs pyarrow on it.
3. **Platform (Wed):**
   - **Pipeline:** OIDC push role and ECR repo.
   - **Base image:** hardened FIPS image with libpq 17.
   - **Terraform:** run `terraform plan`.
   - **Namespace:** confirm the `exports` namespace has default-deny.
   - **Rescan:** the scan gate must be clean (fixable Critical/High).
4. **Delivery path (Wed).** Customers downloading straight from S3 with a
   presigned URL needs **ISSO confirmation** that it's covered by the SSP
   (review A4). If the ISSO doesn't confirm by Wednesday, the download is
   **streamed through the portal** instead (the portal is already the approved
   internet-facing path). That's a small change to the download endpoint.
   Either way, the user gets a fresh link or stream per click, which also
   handles the weekend air-gap transfer.

It ships behind a feature flag, **enabled for this one customer only**.

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
| Data Products (author) | Rotate DB password; worker + migrate code into the PR with B4; confirm nobody needs `export-config` ConfigMaps; update design doc | Tue EOD |
| Data Products manager | Agree the reduced scope with the program office; choose plan vs. one-off by **Tue noon** | Tue noon |
| Platform | OIDC role, ECR repo, hardened libpq 17 image, `terraform plan`, namespace default-deny, rescan | Wed |
| ISSO / compliance | Presigned S3 download covered by the SSP: yes/no (no means portal streaming) | Wed |
| Security Review (me) | Same-day re-review of the worker and the final diff; co-sign RA-2026-014 | Wed–Thu |
| Platform Eng Manager | Approve RA-2026-014; sponsor a boundary change record only if commercial DR is still wanted | Thu |
