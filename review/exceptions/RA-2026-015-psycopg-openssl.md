# Risk Acceptance / Exception Request

**Status: DRAFT. Not approved.** Raised so the decision is explicit (review G6).
No tenant is enabled while this is neither approved nor remediated.

| Field                    | Value |
|--------------------------|-------|
| Exception ID             | RA-2026-015 |
| Type                     | **OR** (Operational requirement) |
| Finding(s)               | Review finding G6: `psycopg[binary]` (psycopg-binary 3.2.3) bundles its own `libpq`, `libssl` and `libcrypto`, so Postgres TLS doesn't use the hardened image's FIPS-validated OpenSSL. Components: `export-service` (api, worker, migrate); also `ingest-api` (same dependency) |
| Original severity        | HIGH (boundary §3: FIPS-validated modules for data in transit) |
| Adjusted severity (if RA)| n/a |
| Environment(s)           | govhigh (`111122223333`, us-gov-west-1) |
| Requested by             | Maxwell Li (Security Review), on behalf of Data Products and Ingest |
| Expires                  | 2027-01-04 (≤ 90 days) |

## Description
The Postgres driver's binary wheel ships its own copy of OpenSSL. The TLS
session between the service and RDS is therefore negotiated by that bundled
OpenSSL, not by the FIPS-validated module in
`hardened/python:3.12-fips`. The connection is still encrypted
(`sslmode=require`), but the cryptographic module isn't the validated one, so
§3 isn't met.

## Justification / Evidence
- **Evidence:**
  - **Bundled libpq is what runs:** in a local install of
    `psycopg[binary]==3.2.3`, `psycopg.pq.__impl__ == "binary"` and
    `psycopg.pq.version() == 170000`.
  - **Linux wheel contents** (the one the image installs):
    `psycopg_binary.libs/` contains `libpq-….so.5.17`, `libssl-….so.3` and
    `libcrypto-….so.3`. That's a supported OpenSSL 3, but not the
    FIPS-validated build in the hardened image.
  - **Version history:** the PR's original pin, 3.1.18, bundled **OpenSSL 1.1**
    (end-of-life since September 2023). Bumping to 3.2.3 (`ingest-api`'s
    version) fixed the end-of-life part. The FIPS part is what this exception
    covers.
  - **To attach before approval:** the same check run inside the built ECR image.
- **Why it can't be fixed by this PR alone:** the fix is to use libpq linked
  against the hardened image's OpenSSL, either with `psycopg` (pure Python,
  loads system libpq) or by building `psycopg[c]`. Both need libpq in the
  hardened base image, which Platform owns. Whether it's there isn't visible
  from this repo.
- **Why OR rather than FP:** the finding is real. This is a time-boxed
  acceptance while Platform provides the dependency.

**Reviewer's note:** if Platform can confirm libpq in the hardened image this
week, remediate instead of accepting.

## Compensating controls
- **Path stays inside the VPC:** the connection to RDS runs from pod to RDS
  inside the VPC, limited by the export SG to the exports RDS SG on 5432 (E3).
  It never crosses a boundary or the internet.
- **TLS required on both ends:** `sslmode=require` on the client.
  **Condition:** Platform confirms `rds.force_ssl=1` on the exports cluster.
- **Data at rest:** RDS and all export data are encrypted with the
  customer-data CMK (FIPS-validated AWS KMS).
- **Credentials:** the DB password comes from Secrets Manager, and has been
  rotated after the git-history exposure (review C2). **Condition** of approval.
- **Scope:** the DB holds job metadata (tenant ID, date range, status, S3 key),
  not exported line data.

## Remediation plan
1. **Platform:** confirm or add libpq (linked to the image's FIPS OpenSSL) in
   `hardened/python:3.12-fips`. Due 2026-11-06.
2. **Data Products:** switch `requirements.in` from `psycopg[binary]` to
   `psycopg` (or `psycopg[c]`). Add an image test that asserts
   `psycopg.pq.__impl__ != "binary"`. Due 2 weeks after step 1.
3. **Ingest team:** same change for `ingest-api`. Due 2 weeks after step 1.
4. Close this exception when both images pass the new check.

## Approvals
- Security Reviewer:
- Platform Engineering Manager:
