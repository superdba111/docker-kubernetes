# AI usage

**Tool:** Claude Code (Claude Opus), run in this repo.

**What I used it for:**
- Reading the diff alongside the docs
- Producing a first findings list
- Drafting the four `review/` documents
- Writing the JWT/tenant-isolation fix and its tests, which I ran locally
  (14 passing)

I reviewed the PR myself first and wrote my own notes. I then had the tool
check my notes against its own reading, and edited the drafts.

**Where we disagreed or I corrected it:**
- **Missing modules:** my notes pointed out that the `worker` and `migrate`
  modules the Helm chart invokes aren't in the PR. The tool's first pass missed
  this. It's now G1, and it matters: the pyarrow RCE and the cluster-wide
  ConfigMap writes live in that unreviewed code.
- **NetworkPolicy (the correction went the other way):** my notes said the
  chart "lacks the required default-deny NetworkPolicy". The tool pointed out
  that the platform baseline already applies default-deny per namespace, so the
  real gap is the service's allow policy, and whether the new `exports`
  namespace gets the baseline at all. I agreed and reworded it (E4).
- **Inconsistent label:** a draft labeled "worker/migrate code not in PR" as
  Follow-up while also calling it required before sign-off. Caught on re-read
  and relabeled Pre-prod.

**What I verified myself rather than took on trust:**
- **KMS AccessDenied:** the explanation that it comes from the missing
  `customer_data` key grant, which I checked against `ingest_api.tf` and
  `data.tf`.
- **Presigned URL lifetime:** the claim that IRSA-signed presigned URLs can't
  outlive the STS session.
- **libpq false positive:** the version comparison (17.4 vs. a 17.3 upstream fix).

<!-- Maxwell: edit this to match exactly what you did vs. what the tool did. -->
