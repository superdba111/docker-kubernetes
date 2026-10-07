# AI usage

**Tool:** Claude Code (model: Claude Opus 5.5), run in this repo.

I reviewed the PR myself first and wrote my own notes. I then used the tool to:
- check my notes against its own reading of the diff and `docs/`
- draft the four `review/` documents, which I then edited
- write the fix commits

I reviewed its output three times and sent corrections back each time.

**Verification run (not just the tool's say-so):**
- **Tests:** `pip install -r services/export-service/requirements-dev.txt &&
  pytest services/export-service` in a fresh venv: 16 passed.
- **Terraform:** `terraform init -backend=false && terraform validate` and
  `terraform fmt -check` pass. No `terraform plan` (no govhigh access).
- **Helm:** `helm lint` / `helm template` pass with an image tag. Rendering
  without one fails, which is intended.
- **FIPS endpoints:** checked with botocore 1.34 offline (request URLs captured
  before sending).
- **Reasoning checked by hand:**
  - the KMS root cause (missing `customer_data` grant)
  - the libpq false positive (17.4 vs. a 17.3 fix)
  - the claim that IRSA-signed presigned URLs can't outlive the STS session

**Where I corrected the tool:**
- **Terraform was in scope:** it first left Terraform unchanged because it
  "couldn't run `terraform plan`". The exercise needs no AWS account, and
  `terraform validate` works offline. Also, its API-only fix didn't close the
  hole it was meant to close: the bucket was still readable via a faked Referer
  header.
- **Shared identity (new finding E5):** my second pass found that the API and
  worker share one pod and one IAM role, so the internet-facing API had
  read access to every tenant's raw data. The tool had flagged the worker's
  broad access (B4) but missed that the API inherited it.
- **FIPS endpoints:** my second pass flagged the non-FIPS endpoints, which the
  tool had listed only as a Pre-prod table row.
- **Third pass: boundary and egress:** the tool had treated the
  `python:3.12-slim` base / PGDG repo as "Platform's problem" (its drafts
  assumed the hardened image would need libpq 17 added), and the `0.0.0.0/0`
  egress as Pre-prod. I held both as boundary blockers. When it checked, the
  libpq 17 assumption was wrong: psycopg[binary] uses its own bundled libpq
  16.1, so the PGDG packages were unused and could be dropped. The same check
  found that the wheel bundles its own non-FIPS OpenSSL, now platform-wide
  follow-up G6 (`ingest-api` does the same).
- **Third pass: runner exposure:** the tool's CI rewrite, copied from
  `ingest-api.yml`, still ran PR code on the govhigh self-hosted runner with
  `id-token: write`. It's now split so only main-branch publishes get OIDC
  (C5). The reference workflow has the same issue.
- **Third pass: "don't enable until the worker is reviewed":** the decision
  doc said "behind a feature flag", but the code had no flag. There's now a
  per-tenant flag, off by default.
- **Inconsistent fallback:** `decision.md` offered a presigned-S3 one-off as
  the fallback while also saying the ISSO had to approve presigned S3. It's now
  conditional, with portal-mediated delivery as the default.
- **Missing code:** my notes pointed out that the `worker` and `migrate`
  modules aren't in the PR (G1). The tool's first pass missed this.
- **Exception wording:** the libpq exception claimed Secrets Manager as an
  existing control while the password was still plaintext.

**Where the tool corrected me:**
- **SQS endpoint:** I'd flagged both the S3 and SQS endpoints as non-FIPS. The
  tool tested it: S3 was a real violation, but the SQS queue URL is only an
  identifier. Requests go to the SDK-resolved endpoint, and in GovCloud the SQS
  FIPS endpoint is `sqs.us-gov-west-1.amazonaws.com`.
- **NetworkPolicy:** I'd written "lacks the required default-deny". The
  baseline already applies default-deny per namespace. The gap was the
  service's own allow policy.
- **Tenant prefixes:** I'd asked for "scope S3 to tenant prefixes". The tool
  pointed out that a static IAM policy can't follow the tenant of each job; it
  needs a per-job session policy (B4).
