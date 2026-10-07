# Risk Acceptance / Exception Request

**Status: DRAFT. Used only if worker review slips (decision.md, fallback).**
It grants nothing until both approvers sign.

| Field                    | Value |
|--------------------------|-------|
| Exception ID             | RA-2026-016 |
| Type                     | **OR** (Operational requirement) |
| Finding(s)               | Review G1: worker code not reviewed, so self-service export can't be enabled. This exception covers **one** operator-run export for one tenant instead |
| Original severity        | HIGH (unreviewed code reading CUI) |
| Adjusted severity (if RA)| n/a |
| Environment(s)           | govhigh (`111122223333`, us-gov-west-1) |
| Requested by             | Data Products manager; drafted by Maxwell Li (Security Review) |
| Expires                  | When the one export is delivered, or 2026-10-23, whichever is first |

## Description
A federal customer's milestone needs one Parquet export of their own data by
Friday. If the worker can't pass review in time, an operator runs a single
export for that tenant using a reviewed script, and the customer collects it
through the portal.

## Justification / Evidence
- **Contract milestone:** the commitment is already made and the customer
  needs only its own data.
- **Smaller than the feature:** one tenant, one run, two people, with a
  short-lived script that's reviewed in full. Less unreviewed surface than
  enabling the worker.
- **Boundary change remains blocked (A5):** the new customer-data bucket is a
  significant change under §6, even inside GovCloud. Platform + Security must
  complete the boundary change record, advance notice to the FedRAMP partner
  and authorizing officials, and required lead time before deployment. Only
  explicit existing authorization covering this storage and flow, evidenced
  through that process, can establish that a new change is unnecessary.
  Neither this exception nor an ISSO interpretation alone waives §6.

## Compensating controls
- **Code:** a short export script, reviewed and approved by Security in the
  PR. It's built by the gated CI and run from the SHA-tagged ECR image that
  passed the scan gate.
- **Tenant scope:**
  - **Credentials:** the script runs under the `export-job` role with the
    `tenant_id` session tag fixed to the customer's tenant. IAM limits it to
    that tenant's prefixes.
  - **Tenant ID source:** the customer's verified request ticket, not the
    operator's typing.
- **Two people:** a Data Products operator runs it; Security Review watches
  and checks the tenant ID, row count and output key.
- **Network and FIPS:** the run uses reviewed NetworkPolicy and pod security
  group selectors matching the operator Job, plus FIPS endpoints. The required
  DB path uses system libpq with FIPS TLS, or approved RA-2026-015.
- **Migration and job registration:** the schema and migration code must be
  reviewed and applied before the run; only worker review is bypassed. A
  reviewed registration procedure uses scoped DB credentials and parameterized
  SQL to create the completed `exports.jobs` row with the verified tenant ID,
  export UUID, date range, `status='done'` and tenant-prefixed S3 key. Security
  checks the row against the output before portal delivery. The S3 job role
  alone does not provide DB credentials.
- **Delivery:**
  - **Path:** the customer downloads through the portal (the export API's
    streaming download, enabled for this tenant only).
  - **Worker off:** `workerReplicaCount: 0`, so no self-service job runs.
  - **Creation off:** Portal blocks customer `POST /exports` requests during
    the one-off window; enabling downloads also enables that API route, so
    zero worker replicas alone is not a creation control. Verify the block
    before enabling this tenant, then remove the tenant flag after delivery.
  - **No presigned S3** unless the ISSO has approved it (review A4).
- **Record:** the ticket, CloudTrail for the role session, and the S3 access
  log are attached here. The object expires under the bucket's 14-day
  lifecycle.
- **Prerequisites** (the decision's merge gates): CI credentials revoked and
  the DB password rotated. All other enable gates remain mandatory: approved
  build/SBOM/scan and infrastructure plan, network readiness, tenant prefixes,
  portal/JWKS configuration, migration review, DB FIPS and boundary clearance.

## Remediation plan
Data Products gets the worker through review (G1). Self-service export is
then enabled under the normal gates, and this exception closes. Owner: Data
Products. Due: 2026-10-23.

## POA&M lifecycle
**Owner: Security Review. Status: not registered; draft only.** Before the
one-off run, register RA-2026-016 on the POA&M with both approvals, boundary
clearance evidence, run owner and expiry; attach the entry reference here.
Security Review records the run and delivery evidence, flag removal and
closure on delivery or expiry, whichever is first. Do not execute or repeat
the run under an unregistered, unapproved or expired exception.

## Approvals
Both are required (policy §4).
- Security Reviewer:
- Platform Engineering Manager:
