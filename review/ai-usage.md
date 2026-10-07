# AI usage

**Tool:** Claude Code (model: Claude Opus 5.5), run in this repo.

I reviewed the PR myself first and wrote my own notes. I then used the tool to:
- check my notes against its own reading of the diff and `docs/`
- draft the four `review/` documents, which I then edited
- write both fix commits

**Verification I ran (not just the tool's say-so):**
- **Tests:** `pip install -r services/export-service/requirements-dev.txt &&
  pytest services/export-service` in a fresh venv: 14 passed.
- **Terraform:** `terraform init -backend=false && terraform validate` and
  `terraform fmt -check` pass. No `terraform plan` was run (no govhigh access).
- **Reasoning checked by hand:**
  - the KMS root cause (missing `customer_data` grant), against `ingest_api.tf`
    and `data.tf`
  - the libpq false positive (17.4 installed vs. a 17.3 upstream fix)
  - the claim that IRSA-signed presigned URLs can't outlive the STS session

**Where I corrected the tool:**
- **Terraform was in scope:** the tool first left Terraform unchanged, arguing
  that it couldn't run `terraform plan` without govhigh access. I pushed back:
  the exercise says no AWS account is needed, and `terraform validate` works
  offline. More importantly, its API-only fix didn't close the problem it was
  meant to fix: the bucket was still readable by anyone sending the portal's
  Referer header. The bucket/IAM commit came out of that.
- **Missing code:** my notes pointed out that the `worker` and `migrate`
  modules the chart invokes aren't in the PR. The tool's first pass missed this
  (now G1/B4).
- **Exception wording:** a draft of the libpq exception listed "credentials
  come from Secrets Manager" as a compensating control, but the password is
  still in plaintext. I changed it to a condition of approval.

**Where the tool corrected me:**
- **NetworkPolicy:** my notes said the chart "lacks the required default-deny
  NetworkPolicy". The platform baseline already applies default-deny per
  namespace. The real gap is the service's allow policy, and whether the new
  `exports` namespace gets the baseline at all (E4).
