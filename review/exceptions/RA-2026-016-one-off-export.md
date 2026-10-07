# Risk Acceptance / Exception Request

**Status: DRAFT. Used only if the enable gates slip (decision.md, fallback).**
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
- **Not a boundary change. This exception cannot make it one:**
  - **Inside govhigh:** everything runs, stores and is delivered inside
    govhigh.
  - **Hard condition:** the ISSO confirms in writing that the in-boundary
    `customer-exports` bucket isn't a §6 "new storage location". If they say it
    is, a boundary change record and notice are required. Neither this
    exception nor the self-service launch can go ahead before that.

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
- **Network and FIPS:** the run uses the chart's NetworkPolicy and pod
  security group, plus FIPS endpoints. DB use needs RA-2026-015 approved;
  otherwise the script doesn't touch the DB.
- **Delivery:**
  - **Path:** the customer downloads through the portal (the export API's
    streaming download, enabled for this tenant only).
  - **Worker off:** `workerReplicaCount: 0`, so no self-service job runs.
  - **No presigned S3** unless the ISSO has approved it (review A4).
- **Record:** the ticket, CloudTrail for the role session, and the S3 access
  log are attached here. The object expires under the bucket's 14-day
  lifecycle.
- **Prerequisites** (the decision's merge gates): CI credentials revoked and
  the DB password rotated.

## Remediation plan
Data Products gets the worker through review (G1). Self-service export is
then enabled under the normal gates, and this exception closes. Owner: Data
Products. Due: 2026-10-23.

## Approvals
Both are required (policy §4).
- Security Reviewer:
- Platform Engineering Manager:
