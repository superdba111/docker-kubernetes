# Security review: `feature/data-export` → `main` (export-service)

Reviewer: @foundry/security-review (Maxwell Li) · PR head `fcbf06d` (line
numbers refer to it) · Rules: `docs/authorization-boundary.md`,
`docs/security-review-policy.md` · Baseline: `ingest-api` (SR-2026-031)

**Outcome: Changes requested.**
- **Counts:** 4 × Blocker (boundary), 15 × Blocker, 14 × Pre-prod,
  12 × Follow-up, 2 × Nit, 8 × No action.
- **Friday:** see `decision.md`.

**Status at merge** (policy §2: Blockers are fixed before merge). Every Blocker
is fixed in `review/maxwell-li`, with these qualifications:
- **A4:** resolved. Presigned S3 isn't part of what merges.
- **B4:** IAM fixed. The worker-code check is Pre-prod (G1), because the code
  isn't in the PR. Merging disabled is safe: the worker runs 0 replicas, and
  no role in the merged state can read `raw-ingest` on its own.
- **C1 / C2:** fixed in code. **Credential revocation and password rotation
  are merge gates**, because merging puts the old password into `main`'s
  history.

**Order:** boundary items first, because they alone decide Friday and Security
Review can't approve them (policy §5). Next come findings where one request
exposes CUI or credentials, then over-broad access, then hardening.

---

## Blocker (boundary)

### A1. `terraform/envs/govhigh/data_export.tf:3-7, 62-119`: replication to the commercial DR account
Every export, including delete markers, replicates to
`arn:aws:s3:::foundry-dr-customer-exports` (commercial, us-east-2). CUI must
not be stored or replicated outside the boundary (boundary §2). This is a new
storage location (§6). Cross-partition replication wouldn't even work, but
the design doc states it as the plan.
**Instead:** remove the replication, its role and the variable. Exports can be
regenerated from `raw-ingest`, which is durable. If the contract requires DR,
use GovCloud us-gov-east-1 as a follow-up.

### A2. `values.yaml:20-21`, `app/main.py:21-26`: errors and traces to sentry.io
The DSN is SaaS, with `send_default_pii=True` and `traces_sample_rate=1.0`.
Error events (stack frames with locals, request data, user details) and every
trace leave the boundary. "Error payloads, logs, and traces count as data"
(boundary §2). I haven't checked whether the SDK's default scrubbing drops the
`Authorization` header. The finding doesn't depend on it.
**Instead:** in-boundary `sentry.govhigh.internal`, with the DSN from Secrets
Manager; `send_default_pii=False`; low sample rate.

### A3. `values.yaml:3-6`, workflow, `Dockerfile`: images built on and served from Docker Hub
govhigh would pull `docker.io/foundryeng/...:latest`. Only ECR in
`111122223333` is allowed (§1), and Docker Hub is named as out of boundary.
Anyone holding `DOCKERHUB_TOKEN` (C1) could change what runs.
**Instead:** build on the govhigh runner from the hardened base and push
SHA-tagged images to ECR, as `ingest-api` does.

### A4. Design: customers download directly from S3 via presigned URL
The only internet-facing entry point is the portal behind WAF (§5). A
presigned URL makes the S3 endpoint the download path, which may or may not
be covered by the SSP.
**Instead:** stream through the portal. Presigned stays off unless the ISSO
confirms coverage.

## Blocker

### B1. `app/main.py:42-46`: JWT signature not verified
`verify_signature: False` accepts any token. "The ingress verifies it" isn't
enforced: there's no NetworkPolicy, and the SG admits the ingress controller.
PyJWT also lacks `[crypto]`, so RS256 couldn't work.
**Instead:** verify against the portal JWKS: `RS256` pinned;
`iss`/`aud`/`exp`/`iat`/`sub`/`tenant_id` required; 401 on bad tokens; 503
(not fallback) if the JWKS is unreachable.

### B2. `app/main.py:69-71`, `app/db.py:33-41`: download doesn't check the caller's tenant
Lookup is by `export_id` only. UUIDs show up in logs and tickets; they're
identifiers, not authorization.
**Instead:** `WHERE id = %s AND tenant_id = %s`, with the tenant taken from the
verified token. Return 404 for both foreign and missing exports.

### B3. `app/main.py:38, 80`, `values.yaml:18`: 7-day presigned URLs, logged
A presigned URL is a bearer credential, and it's written to logs. The 7-day
TTL also doesn't work: IRSA-signed URLs die with the STS session, which
explains the UAT "links kept expiring".
**Instead:** never log it; TTL 15 min, capped at 1 h; the portal re-issues the
link on each click.

### B4. `data_export.tf:189-194`: worker can read every tenant's raw data
`ReadRawIngest` covers the whole bucket, and the worker trusts `tenant_id`
from the SQS message. The feature flag decides *whether* exports run, not
*whose* data a job can read.
**Instead:** the worker's own role gets no data access. A per-job
`export-job` role requires a `tenant_id` session tag and limits S3 to
`<tenant>/` prefixes through `${aws:PrincipalTag/tenant_id}`. The worker code
must take the tenant from the DB job row and use only those credentials,
verified under G1. **Residual risk:** a compromised worker can still pick any
tag. That needs a credential broker (FU-4). **Assumption:** `raw-ingest` keys
are `<tenant_id>/...`; Ingest team to confirm.

### C1. `.github/workflows/export-service.yml:3-42`: fork code runs with govhigh deploy secrets
`pull_request_target` + checkout of the PR head + `pip install`/`pytest`,
after long-lived govhigh AWS keys and Docker Hub login. A `conftest.py` in any
PR can steal both. Other problems:
- Long-lived keys are banned (§4).
- The scan ends in `|| true`.
- Actions aren't pinned.
- There's no `permissions:` block.

**Instead:**
- **Tests:** `pull_request` tests on a hosted runner with no secrets.
- **Publish:** a main-branch job on the govhigh runner, with OIDC, a gating
  trivy scan and pinned actions. Don't copy `ingest-api.yml` exactly: it also
  runs PR code on the govhigh runner with `id-token: write` (FU-7).
- **Today:** revoke `GOVHIGH_DEPLOY_AWS_*` and `DOCKERHUB_TOKEN`, and check
  CloudTrail.

### C2. `values-govhigh.yaml:9`: production DB password committed
It's in history, so deleting it isn't enough. The migration job also passes
it as a plain env value, and the Sentry DSN is committed too.
**Instead:** **rotate in RDS**. Serve the password and DSN through an
ExternalSecret, with `secretKeyRef` everywhere.

### C3. `CODEOWNERS:13-17`: Security Review removed from the new paths
Last match wins. Data Products would become sole owner of its own deploy
workflow and chart, and of export code paths that policy §1 says need
security review. **I don't approve this hunk.**
**Instead:** add `@foundry/platform @foundry/security-review` back on all
three paths.

### C4. `migration-job.yaml:13-28`: `cluster-admin` bound to a workload
Banned (§4). With `before-hook-creation`, the binding also outlives the hook
until the next deploy.
**Instead:** migrations get no Kubernetes permissions. ConfigMap seeding, if it
is still needed, gets a namespaced Role design reviewed by Security (FU-11).

### D1. `data_export.tf:39-60, 31-37`: bucket readable by anyone sending the portal Referer
`Principal: *` with an `aws:Referer` condition. `curl -H 'Referer: ...'`
fetches any export, and the public-access blocks are off.
**Instead:** delete the statement, turn all four blocks on, and add
`DenyInsecureTransport`. Previews are generated server-side.

### D2. `data_export.tf:22-29`: SSE-S3 for customer data
Not accepted (§2). **Instead:** SSE-KMS with the `customer_data` CMK and bucket
keys, as `raw_ingest` does.

### D3. Bucket: no access logging, no lifecycle
Both are required (§2). **Instead:** log to the access-logs bucket; expire
after 14 days (Data Products to confirm against the contract).

### E1. `data_export.tf:155-167`: IRSA trust allows any namespace and doesn't check `aud`
**Instead:** `StringEquals` on `aud` and an exact `sub` (§4).

### E2. `data_export.tf:181-206`: `arn:aws:` ARNs, `kms:*` on `*`, `sqs:*`
- **Partition:** `arn:aws:` never matches in `aws-us-gov` (it only worked in
  commercial staging).
- **KMS root cause:** the staging `AccessDenied` that led to `kms:*` was the
  missing `customer_data` grant for reading `raw-ingest`.

**Instead:** ARNs from resource attributes; KMS on the two named keys; the
five SQS actions actually used.

### E3. `data_export.tf:229-235`: SG egress `0.0.0.0/0:443`
NAT egress must be allow-listed (§5), and nothing legitimate needs the
internet once A2 is fixed. The SG also wasn't attached to any pod, so its
rules governed nothing.
**Instead:**
- **Egress:** only to named SGs (interface endpoints, cluster, exports RDS).
- **Attachment:** a `SecurityGroupPolicy` attaches the SG, with matching
  ingress on the destination SGs.

### E5. `deployment.yaml:17`, IRSA: API and worker share one pod and role
The internet-facing API holds the worker's cross-tenant read access. Any API
bug (SSRF, the scan's gunicorn row) becomes a data breach.
**Instead:** separate Deployments, ServiceAccounts and roles. The API gets
exports-bucket read and `SendMessage` only.

## Pre-prod

May merge disabled; must be fixed before any tenant is enabled.

| # | Where | Finding | Instead |
|---|---|---|---|
| G1 | chart `deployment.yaml:34`, `migration-job.yaml:47` | **`worker` and `migrate` modules aren't in the PR.** The code that reads CUI and runs pyarrow hasn't been reviewed | Submit and review it, including B4's worker side (tenant from the job row, `export-job` credentials only). Hard enable gate |
| G6 | `requirements.txt` | psycopg[binary] bundles its own OpenSSL, so DB TLS doesn't use the FIPS module (§3). The PR's 3.1.18 bundled end-of-life OpenSSL 1.1.1w | System libpq from the hardened image, or **RA-2026-015** approved by both signers. `ingest-api` doing the same isn't a justification |
| F9 | `requirements.txt` | psycopg[binary]'s **bundled libpq** is affected by CVE-2026-90011 (3.1.18: 16.0; 3.2.3: 17.0). Trivy can't see bundled copies (scan triage, Part 1) | 3.2.5, which bundles 17.4 (read from the hash-locked wheel). A CI test asserts ≥ 17.3 |
| B6 | `app/main.py` download | Tenant-scoped lookup, but then the row's `s3_key` is used with a bucket-wide role | Key must be under `<tenant_id>/`; strict `tenant_id` format |
| B7 | `app/db.py` | One global connection shared across request threads, so transactions interleave | Pool, one connection per request |
| E4 | chart | No NetworkPolicy of its own under default-deny | Explicit allow-lists, including DNS and the endpoint addresses. Migration prerequisites are pre-install hooks, so a fresh install works. Platform to confirm default-deny on `exports` |
| F1 | `Dockerfile:1,7` | `python:3.12-slim` from Docker Hub; public PGDG apt repo | Hardened FIPS base; no apt installs (PGDG packages unused) |
| F2 | `values.yaml:14`, `main.py:28-32` | Non-FIPS `S3_ENDPOINT_URL` override | Remove it; `AWS_USE_FIPS_ENDPOINT=true` (resolves `s3-fips`; SQS QueueUrl host is fine) |
| F3 | chart, Dockerfile | Runs as root; writable root FS; all capabilities | `ingest-api` securityContext; `USER 10001` |
| F4 | `values.yaml:4-6` | `latest`, `pullPolicy: Always` | Required SHA tag; `IfNotPresent` |
| F5 | `values.yaml:19` | `LOG_LEVEL: DEBUG` logs signed request details | `INFO` |
| F6 | `requirements*.txt` | No hash pinning, no defined package source | Hash-locked; required in-boundary mirror; credentials via BuildKit secret only. Platform to name the mirror |
| F7 | `serviceaccount.yaml` | SA token auto-mounted | `automountServiceAccountToken: false` |
| F8 | workflow | CI's AWS calls (STS, ECR) don't enable FIPS endpoints; the app setting doesn't cover CI | `AWS_USE_FIPS_ENDPOINT` on the job; registry `dkr.ecr-fips` for pull and push. Platform to confirm that host on the first build |

## Follow-up

Policy §2 requires a tracked ticket, an owner and a due date. Ticket IDs are
filed in the tracker at merge. Scan deadlines run from first detection on
**2026-09-28**. Findings first raised in this review run from **2026-10-07**.

| Ticket | Item | Owner | Due |
|---|---|---|---|
| FU-1 | G3: output size cap; `Idempotency-Key` (range and per-tenant concurrency limits are done) | Data Products | 2026-11-20 |
| FU-2 | G4: download/export audit events to the in-boundary audit stream | Data Products | 2026-11-20 |
| FU-3 | G5: DLQ depth alarm; explicit retention | Data Products | 2026-11-06 |
| FU-4 | B4 residual: credential broker, so a compromised worker can't pick its tenant | Data Products + Security | 2026-12-18 |
| FU-5 | G2: govhigh-equivalent test path (testing so far was commercial staging only) | Platform | 2026-11-30 |
| FU-6 | `ingest-api`: psycopg 3.2.3 bundles libpq 17.0 (CVE-2026-90011, Critical) | Ingest | 2026-11-06 |
| FU-7 | `ingest-api.yml`: PR code on the govhigh runner with `id-token: write`; no CI FIPS setting | Platform | 2026-10-30 |
| FU-8 | perl-base CVE-2026-90045 (High, no fix): VD exception if still unfixed | Platform | 2026-10-28 |
| FU-9 | Scan Mediums still open after the rebuild (libc6, gnupg, systemd, util-linux, tar, starlette, pip) | Data Products + Platform | 2026-12-27 |
| FU-10 | Scan Lows still open after the rebuild (coreutils, ncurses, login, apt, libgcrypt) | Platform | 2027-03-27 |
| FU-11 | C4: `export-config` seeding. Confirm it's unneeded, or design a namespaced Role | Data Products + Security | 2026-11-20 |
| FU-12 | A1: GovCloud-to-GovCloud DR, only if the contract requires it | Data Products | Decide by 2026-10-30 |

## Nit
- **H1:** 404s have no `detail`.
- **H2:** update `docs/design/data-export.md` to what ships.

## No action: looked at and fine
- **SQL (`db.py`):** parameterized throughout.
- **DB TLS (`db.py:17`):** `sslmode=require`. FIPS module is a separate issue (G6).
- **SQS:** CMK on queue and DLQ; `maxReceiveCount=5`; 900 s visibility.
- **KMS key policy:** root `kms:*` is the AWS default delegation to IAM;
  rotation is on.
- **Bucket:** versioning and ACL blocks are on.
- **`values-govhigh.yaml:2`:** `arn:aws-us-gov:` partition is correct.
- **PGDG repo over `http`:** signed-by pinned, so integrity was fine. It was a
  boundary issue (F1).
- **Export IDs:** `uuid4()` from a CSPRNG; fine as identifiers.

---

## The fix on this branch

**Chosen fix: tenant isolation.** B1–B3 in the API, plus D1–D3, E1, E2 and A1
in the bucket and IAM behind it (`70fce0a`, `42eec9f`). Why this one:
- **Live exposure:** today any user, or anyone at all, can read any tenant's
  CUI.
- **Survives cleanup:** removing Sentry SaaS or Docker Hub wouldn't touch it.
- **Easy to get subtly wrong:** JWT validation details, and the KMS root cause.

The halves must ship together: fixing only the API leaves the Referer hole,
and fixing only the bucket leaves cross-tenant URLs.

**Beyond the one fix.** I also fixed the other in-repo findings, one theme per
commit, so each can be reviewed, split into its own PR, or dropped:

| Theme | Findings | Commits |
|---|---|---|
| Boundary | A2, A3, F1 | `a94ddf8`, `b63f93d`, `089a611` |
| CI and ownership | C1, C3, F8 | `089a611`, `35e1fe1`, latest commit |
| Identity and per-tenant access | E5, B4 (IAM), flag | `06976c9`, `8fb1c5a`, `1f5770a` |
| Network | E3, E4 | `00cd76d`, `030593b`, `dbf566a`, `14daebe`, latest commit |
| Secrets and workload | C2, C4, F3–F5, F7 | `a94ddf8`, `27d8e75` |
| Delivery | A4 | `d0fd221` |
| Dependencies | F6, G6, F9, scan rows | `0ed306f`, `5cba6d7`, `dd0fff4`, latest commit |
| API robustness | B6, B7, G3 limits | `49af428`, `59436f8` |

Commit messages also mention B5, C5 and E6–E9. Those were defects in my own
fixes, caught in self-review and corrected (JWKS host, runner exposure, SG
attachment, DNS/endpoint egress, migration hook networking).

**Author to confirm (C4):** the migrator no longer seeds `export-config`
ConfigMaps.

### Verify (no AWS account needed)
```
python3.12 -m venv .venv && .venv/bin/pip install --require-hashes -r services/export-service/requirements-dev.txt
.venv/bin/pytest services/export-service     # 33 passed, 4 skipped; with EXPORT_TEST_PG=1 + a disposable Postgres the 4 run
helm lint helm/charts/export-service -f helm/charts/export-service/values-govhigh.yaml --set image.tag=x --set worker.jobRoleArn=x
cd terraform/envs/govhigh && terraform init -backend=false && terraform validate && terraform fmt -check
```
**Not verified:**
- **AWS and deploy:** no `terraform plan`, no image build, no SBOM, no trivy
  rescan, no deploy.
- **Hosts:** the `dkr.ecr-fips` registry host is unconfirmed.

Platform's first build closes these (decision, enable gate 2).
