# Decision: export-service for Friday

To: Data Products (PR author + manager), Platform Engineering Manager
From: Security Review · Monday

## Can this PR ship Friday? **No.**

Three parts of the design move customer data (CUI) or our supply chain outside
the govhigh authorization boundary:
- **DR copy:** exports are copied to the commercial DR account.
- **Errors and traces:** they go to sentry.io.
- **Images:** they're served from Docker Hub.

These are *significant changes*. Security Review can't approve them, and they
need 10+ business days' notice to our FedRAMP partner before deployment. That
alone rules out Friday for the design as written.

Separately, the code as written lets **any user download any tenant's export**.
That comes from three things together: the JWT isn't verified, there's no
tenant check, and the bucket is readable by anyone who sends the right Referer
header. The CI workflow also gives govhigh deploy credentials to code from fork
PRs. Even with no deadline, I wouldn't merge these.

## What *can* ship Friday: a reduced, in-boundary export

The customer needs Parquet files of their own data, and nothing about that
requires leaving the boundary. If the scope below is done by **Wednesday EOD**,
I'll turn the review around the same day:

1. **Remove the cross-boundary pieces.** No DR replication (already removed on
   `review/maxwell-li`): exports can be regenerated from `raw-ingest`, so they
   don't need DR. Self-hosted Sentry,
   `send_default_pii=False`. Images built on the govhigh runner with OIDC and
   pushed to in-boundary ECR (copy `ingest-api.yml`).
2. **Tenant isolation.** Merge my fix on `review/maxwell-li` (JWT verification,
   tenant-scoped lookup, 15-minute URLs that are never logged). The portal
   re-issues a URL each time the user clicks Download, which also solves the
   weekend air-gap transfer. Add the same tenant check to the worker.
3. **Bucket and IAM**, also done on `review/maxwell-li` (Platform to run `terraform plan`):
   - **Bucket:** private bucket (all public access blocked, no Referer policy),
     SSE-KMS with the customer-data CMK, access logging, lifecycle.
   - **IRSA:** trust pinned to `exports:export-service` with `aud`.
   - **Policies:** partition-correct ARNs, KMS scoped to the two keys (the staging
     `AccessDenied` was the missing `customer_data` key grant), scoped SQS actions.
4. **Hygiene.**
   - **Secrets:** rotate the committed DB password and move it to Secrets Manager.
   - **RBAC:** no `cluster-admin`; the migrator gets namespaced RBAC.
   - **CODEOWNERS:** keep Security Review on the new paths.
   - **Image:** non-root, FIPS endpoints, patch pyarrow, gunicorn, PyJWT, setuptools.
5. **Show us the code that isn't in the PR yet** (`worker`, `migrate`).
   That's where pyarrow parses customer data.

It ships behind a feature flag. It's enabled **for this one customer only** once
Platform has run `terraform plan` and the scan gate is clean (fixable
Critical/High).

**If that slips:** an operator runs a one-off export for this customer's tenant
using the same worker code against in-boundary storage, then delivers it with a
short-lived presigned URL, logged and audited. That meets the contract milestone
without launching a self-service feature. I'd approve that as a documented
one-off.

**Not Friday** (separate track): GovCloud-to-GovCloud DR for exports if the
contract actually requires it, and portal previews (rebuilt server-side).

## Owners and asks

| Who | What | By |
|---|---|---|
| Data Products (author) | Items 1, 2 (worker side), 4, 5; update design doc | Wed EOD |
| Data Products manager | Confirm reduced scope with the customer / program office; decide by **Tue noon** whether we go with the plan or the one-off export | Tue noon |
| Platform | Review the item 3 Terraform on my branch; build the ECR/OIDC pipeline; run `terraform plan`; confirm `exports` namespace has default-deny; add libpq 17 to hardened image or approve in-boundary mirror | Wed |
| Platform / Security (both, today) | **Revoke and rotate** `GOVHIGH_DEPLOY_AWS_*` and `DOCKERHUB_TOKEN`; check CloudTrail for use from fork PR runs | Today |
| Security Review (me) | Same-day re-review; co-sign the libpq false-positive exception (RA-2026-014) with the Platform EM | Wed–Thu |
| Platform Eng Manager | Approve RA-2026-014; sponsor the boundary change record if commercial DR is still wanted | Thu |
| ISSO / compliance | Confirm presigned S3 download is covered by the current SSP (otherwise we serve through the portal) | Wed |

I'll join Tuesday's standup to walk through the review and answer questions.
