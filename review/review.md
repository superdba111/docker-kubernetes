# Security review: `feature/data-export` → `main` (export-service)

Reviewer: @foundry/security-review (Maxwell Li) · Reviewed at PR head `fcbf06d`
Rules applied: `docs/authorization-boundary.md`, `docs/security-review-policy.md`.
Pattern baseline: `ingest-api` (SR-2026-031).

**Outcome: Changes requested.** 4 × Blocker (boundary), 13 × Blocker, 10 × Pre-prod,
4 × Follow-up, 2 × Nit, 9 × No action. See `decision.md` for what can ship Friday.

Line numbers refer to the PR head (`fcbf06d`), not to my fix commit.

### How I ordered this

I put the boundary items first because they alone decide Friday. They are
significant changes (boundary §6, policy §5), so Security Review cannot
approve them and the 10+ business-day notice period can't be shortened.
Everything after them can be fixed this week. After that come the findings
where one bad request already exposes CUI or credentials: cross-tenant access,
a public bucket, and a CI workflow that hands out secrets. Then wildcard
access, then hardening.

---

## A. Blocker (boundary): new data flows outside the authorization boundary

### A1. `terraform/envs/govhigh/data_export.tf:3-7, 62-119`: DR replication to the commercial partition
**Blocker (boundary)**

`dr_exports_bucket_arn` defaults to `arn:aws:s3:::foundry-dr-customer-exports`
in the **commercial** DR account (`us-east-2`). `aws_s3_bucket_replication_configuration.exports_dr`
copies every customer export, including delete markers, into it. Customer data
in govhigh is CUI and must not be "stored, replicated … outside the boundary"
(boundary §2). The only in-boundary DR is GovCloud `us-gov-east-1` / `444455556666` (§1).
This is "a new storage location for customer data" (§6), so it needs a boundary
change record and advance notice.

In practice, replication from an `aws-us-gov` bucket to a commercial bucket
won't work: the two partitions are isolated. The intent is still the problem,
and the design doc states it as the plan.

**Instead:** delete the replication config, its role, and the variable. Exports
are a **derived, regenerable** artifact: the source of truth is `raw-ingest`,
which is already durable and versioned. They don't need DR. If the customer
contract requires DR for exports, replicate to the GovCloud DR account as a
follow-up.

### A2. `helm/charts/export-service/values.yaml:20-21`, `app/main.py:21-26`: errors and traces go to sentry.io (SaaS)
**Blocker (boundary)**

`SENTRY_DSN` points at `o448812.ingest.sentry.io`, with `send_default_pii=True`
and `traces_sample_rate=1.0`. That sends request bodies, headers (including the
user's `Authorization` JWT), local variables, and 100% of traces to a SaaS
outside the boundary. Boundary §2 says, verbatim: "Error payloads, logs, and
traces count as data." Self-hosted Sentry exists for this purpose (§1).
"So on-call sees govhigh and commercial errors in one place" is the exact
cross-boundary data flow the rule exists to prevent.

**Instead:** source the DSN from Secrets Manager via External Secrets, pointing
at `sentry.govhigh.internal` as `ingest-api` does. Set `send_default_pii=False`
and a low trace sample rate. Upgrade `sentry-sdk` (see scan triage).

### A3. `values.yaml:3-6`, `.github/workflows/export-service.yml:25-42`, `Dockerfile`: images built and served from Docker Hub
**Blocker (boundary)**

The govhigh cluster would pull its runtime image from `docker.io/foundryeng`,
built by a GitHub-hosted runner. The only allowed registry is ECR in
`111122223333` (§1), and Docker Hub is named explicitly as out of boundary.
That makes this a new external interconnection (§6). It's also a supply-chain
problem: anyone with the `DOCKERHUB_TOKEN` (see C1) can change what runs in govhigh.
DP-2291 ("mirror later") turns a launch requirement into an optional follow-up.

**Instead:** build on the govhigh self-hosted runner, push to
`111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/foundry/export-service:${GITHUB_SHA}`.
Copy `ingest-api.yml`.

### A4. Design: customers download directly from S3 via presigned URL
**Blocker (boundary) — needs a decision, not necessarily a change**

Delivering data to its owner over TLS through an authenticated path is allowed
(boundary §2). However, §5 says the only internet-facing entry point is the
`portal` ingress, behind WAF. Presigned S3 URLs make the S3 endpoint itself the
customer download path. That may already be covered by the SSP, or it may be a
new interconnection. **ISSO / FedRAMP partner to confirm this week.** If it
isn't covered, the fallback is to stream the download through the portal.

---

## B. Blocker: cross-tenant data access

### B1. `services/export-service/app/main.py:42-46`: JWT signature not verified
**Blocker** · *fixed in this branch*

`jwt.decode(token, options={"verify_signature": False})` accepts any token
anyone can type. "The portal ingress verifies the signature" is only true if
nothing else can reach the pod. This chart ships no NetworkPolicy, and the SG
(`:224-229`) allows the ingress controller in, so that assumption isn't
enforced anywhere. Any workload that can reach the Service can claim any
`tenant_id`. `PyJWT` 2.8.0 also lacks the `[crypto]` extra, so RS256
verification couldn't have worked even if it had been switched on.

**Fix (done):** verify against the portal JWKS with pinned `RS256`, and require
`iss`, `aud`, `exp`, `iat`, `sub`, and `tenant_id`. Bad tokens get 401. If the
JWKS endpoint is unreachable, the service returns 503 rather than falling back.

### B2. `app/main.py:69-71`, `app/db.py:33-41`: download doesn't check that the export belongs to the caller
**Blocker** · *fixed in this branch*

`get_export(export_id)` looks up by ID only. Any authenticated user (or, given
B1, anyone at all) can request a URL for another tenant's export. UUIDv4 IDs are
hard to guess, but they show up in logs, Sentry, browser history, and support
tickets. They're identifiers, not secrets.

**Fix (done):** `WHERE id = %s AND tenant_id = %s`, using the tenant from the
verified token. Another tenant's export returns 404, the same as a missing one,
so export IDs can't be probed. `export_id` is now typed as a UUID.

### B3. `app/main.py:38, 80`, `values.yaml:18`: 7-day presigned URLs, written to logs
**Blocker** · *fixed in this branch*

A presigned URL is a bearer credential. `log.info("issued download url … %s", url)`
writes it, along with `LOG_LEVEL: DEBUG`, into Loki/CloudWatch, where everyone
with log access can download the export for 7 days.

The 7-day TTL also **doesn't work**. A URL signed with IRSA (STS session)
credentials stops working when that session expires, which is hours, not days.
So the UAT problem ("links kept expiring") wasn't caused by the TTL setting.

**Fix (done):** stop logging the URL, default the TTL to 15 minutes, and cap it
at 1 hour in code. The portal requests a fresh URL each time the user clicks
Download. That handles the weekend air-gap transfer: the customer clicks again
on Monday.

### B4. `data_export.tf:189-194`: worker can read all tenants' raw data
**Blocker** (paired with B1/B2)

`ReadRawIngest` grants `GetObject`/`ListBucket` on the whole `raw-ingest` bucket.
The worker takes `tenant_id` from the SQS message, so the API is now the only
thing keeping tenants apart. Anyone who can send to the queue, and `sqs:*` (E2)
lets the role do exactly that, can export any tenant's data.

**Instead:** at minimum, the worker must only read under the tenant's prefix and
must check that the job row in the DB matches the message (`id`, `tenant_id`).
That code isn't in this PR (see G1). Longer term, tag objects by tenant and
scope access with ABAC or per-tenant prefix conditions.

---

## C. Blocker: credentials and supply chain

### C1. `.github/workflows/export-service.yml:3-42`: `pull_request_target` runs fork code with govhigh deploy secrets
**Blocker**

`pull_request_target` runs with the base repo's secrets. The job then checks out
`github.event.pull_request.head.sha` (`:17`), the **fork's** code, and runs
`pip install -r requirements-dev.txt` and `pytest` on it, *after* configuring
long-lived govhigh AWS keys (`:19-23`) and logging into Docker Hub (`:25-28`).
Any contractor (or anyone, on a public repo) can open a PR whose `conftest.py`
reads `~/.aws` and the Docker credentials. Those credentials then let them
change the image govhigh runs (A3).

On top of that:
- **Long-lived keys:** `GOVHIGH_DEPLOY_AWS_*` are long-lived IAM access keys,
  which are banned (boundary §4: "CI authenticates to AWS with GitHub OIDC").
- **No scan gate:** the scan ends in `|| true` (`:38`) and runs without
  `--exit-code 1`, so it can never block. That's why a 5-Critical image got this far.
- **Unpinned and mutable:** `:latest` tags are pushed, actions aren't pinned to
  SHAs, there's no `permissions:` block, and the job runs on GitHub-hosted runners.

**Instead:** copy `ingest-api.yml`: `pull_request` (no secrets) for fork PRs;
`push` to main on `[self-hosted, govhigh-builder]` with OIDC
`role-to-assume`; `trivy --exit-code 1 --ignore-unfixed --severity CRITICAL,HIGH`;
SHA tags; pinned actions. **Revoke and rotate** `GOVHIGH_DEPLOY_AWS_*` and
`DOCKERHUB_TOKEN` now. If this workflow has ever run against a fork PR, treat
both as compromised and check CloudTrail.

### C2. `helm/charts/export-service/values-govhigh.yaml:9`: production DB password committed
**Blocker**

`password: "Xp0rt-svc!2026-govhigh"` is in git, so it's in every clone and in
history. The PR checklist says "No secrets committed", which is false, and that
lowers how far I trust the rest of the checklist. Related problems:
- **Sentry DSN:** committed in `values.yaml:20`.
- **Migration hook:** passes the password as a **plain env value**
  (`migration-job.yaml:55-56`), so it shows up in the rendered manifest and the
  Helm release secret.
- **Chart Secret:** `templates/secret.yaml` renders it from values too.

**Instead:** **rotate the password in RDS**. Deleting the line doesn't help; it's
in history. Replace `secret.yaml` with an `ExternalSecret`, as in `ingest-api`,
keyed at `govhigh/export-service/db-password`. Have the migration job use
`secretKeyRef`.

### C3. `CODEOWNERS:13-17`: Security Review removed as a required reviewer on the new paths
**Blocker**

"Last matching pattern wins." The new entries make `@foundry/data-products` the
**only** owner of `/helm/charts/export-service/`, `/.github/workflows/export-service.yml`,
and `/services/export-service/`. That overrides `/helm/` and `/.github/workflows/`,
which require Platform and Security Review. Two consequences:
- **Separation of duties:** Data Products could change their own deploy
  workflow, the one holding govhigh credentials (C1), with no outside reviewer.
  Policy §1 says nobody may change CODEOWNERS to remove a required reviewer
  without Security Review approval. **I do not approve this hunk.**
- **Export code paths:** policy §1 requires security review on "data
  export/download code paths", and `/services/export-service/` is one.

**Instead:**
```
/services/export-service/             @foundry/data-products @foundry/security-review
/helm/charts/export-service/          @foundry/data-products @foundry/platform @foundry/security-review
/.github/workflows/export-service.yml @foundry/data-products @foundry/platform @foundry/security-review
```

### C4. `helm/charts/export-service/templates/migration-job.yaml:13-28`: `cluster-admin` bound to a workload
**Blocker**

Boundary §4: "`cluster-admin` … is never bound to workloads." "It's short-lived"
doesn't help:
- **Running image:** the Job runs the same `:latest` Docker Hub image that
  anyone with the Docker Hub token can replace (A3/C1).
- **Binding lifetime:** with `hook-delete-policy: before-hook-creation`, the
  ClusterRoleBinding and its ServiceAccount are **not deleted after the hook**.
  They stay in the cluster until the next deploy, so the binding is effectively
  permanent.

**Instead:** split the two jobs.
- **DB migration** needs no Kubernetes permissions at all.
- **Seeding `export-config` ConfigMaps** needs `create/get/patch` on
  `configmaps` only, ideally with `resourceNames: [export-config]`. Grant that
  through a namespaced Role and RoleBinding per tenant namespace, or better,
  have each tenant read config from the export DB and drop the ConfigMaps.
  Any ClusterRole needs Security Review (§4).

---

## D. Blocker: export bucket (`data_export.tf:9-60`)

### D1. `:39-60, :31-37`: bucket readable by anyone who sends the portal's Referer header
**Blocker**

`Principal: *`, `s3:GetObject` on `bucket/*`, conditioned on `aws:Referer`.
Referer is a header the client chooses: `curl -H 'Referer: https://portal.foundry-gov.example/x'`
fetches **any tenant's export** with no credentials. AWS documents that Referer
must not be used to protect data. `block_public_policy = false` and
`restrict_public_buckets = false` were turned off to allow this, which makes
the bucket public in practice.

**Instead:** delete `PortalPreviews`. Turn all four public-access-block settings
back on. Previews should be generated server-side (the export service can write
a thumbnail object) and served through the same tenant-checked presigned URL
path. Add the `DenyInsecureTransport` statement from `ingest_api.tf`.

### D2. `:22-29`: SSE-S3 (AES256) instead of the customer-data CMK
**Blocker**

Boundary §2: "SSE-S3 (`AES256`) is not accepted for customer data." Use
`aws:kms` with `data.aws_kms_key.customer_data.arn` and `bucket_key_enabled`,
exactly as `raw_ingest` does.

### D3. Missing access logging and lifecycle
**Blocker**

Boundary §2 requires both for customer-data buckets.
- **Logging:** add `aws_s3_bucket_logging` → `data.aws_s3_bucket.access_logs`,
  prefix `customer-exports/`.
- **Lifecycle:** exports can be regenerated, so keep them only briefly. Suggest
  expiring after 14 days, with `noncurrent_version_expiration` 1 day. Data
  Products to confirm what the contract requires.

---

## E. IAM / network (`data_export.tf:151-244`)

### E1. `:155-167`: IRSA trust allows any namespace and doesn't check `aud`
**Blocker**

`StringLike` on `system:serviceaccount:*:export-service`, with no `:aud`
condition. Anyone who can create a ServiceAccount named `export-service` in
**any** namespace gets this role, and with it all tenants' raw and exported
data. Boundary §4 requires both pinned. **Instead:** `StringEquals` `:aud` =
`sts.amazonaws.com`, `StringEquals` `:sub` = `system:serviceaccount:exports:export-service`.

### E2. `:181-206`: hardcoded `arn:aws:` ARNs, `kms:*` on `*`, `sqs:*`
**Blocker**

- **Hardcoded partition:** `arn:aws:s3:::…` (`:185-186, :193`) violates §4.
  It's also **broken in govhigh**: the partition is `aws-us-gov`, so these
  statements never match. It only worked in staging because staging is the
  commercial account.
- **KMS on `*`:** has no documented exception. I believe the staging
  `AccessDenied` that led to this came from the worker reading `raw-ingest`,
  which is encrypted with the **`customer_data`** CMK, while the scoped policy
  only granted the new queue key. That matches "failed once the worker started
  processing jobs". **Instead:** grant `kms:Decrypt` on `customer_data` (to read
  raw objects and exports) and `kms:GenerateDataKey`/`Decrypt` on
  `aws_kms_key.exports` (for the queue). `customer_data` also needs
  `GenerateDataKey` once D2 makes the bucket SSE-KMS.
- **SQS:** `sqs:*` → `SendMessage`, `ReceiveMessage`, `DeleteMessage`,
  `ChangeMessageVisibility`, `GetQueueAttributes`.
- **ARN construction:** build all ARNs from the resource attributes
  (`aws_s3_bucket.exports.arn`, `aws_s3_bucket.raw_ingest.arn`).

### E3. `:229-235`: SG egress `0.0.0.0/0:443` ("S3, SQS, Sentry")
**Pre-prod**

Boundary §5 says AWS services go through VPC endpoints and NAT egress is
allow-listed. Once A2 is fixed, nothing legitimate needs the internet. Restrict
egress to the VPC endpoint prefix lists / VPC CIDR, plus the in-cluster Sentry.

### E4. Missing service NetworkPolicy
**Pre-prod**

The platform baseline applies namespace default-deny. The chart needs its own
allow policy, as `ingest-api` has: ingress from `ingress-nginx` only, egress to
`sentry` plus VPC endpoints and RDS. **Platform to confirm** that the new
`exports` namespace actually gets the baseline default-deny. If it doesn't, the
pod is reachable from everywhere in the cluster.

---

## F. Pre-prod: workload and image hardening

| # | Where | Finding | Instead |
|---|---|---|---|
| F1 | `Dockerfile:1,7` | `python:3.12-slim` from Docker Hub, not the hardened FIPS image (boundary §3). This base also accounts for most of the OS findings in the scan | `…/hardened/python:3.12-fips`. For libpq 17, ask Platform to add it to the hardened image, or install from an in-boundary mirror |
| F2 | `values.yaml:14`, `main.py:28-32` | `S3_ENDPOINT_URL` overrides the endpoint with a **non-FIPS** URL, and `AWS_USE_FIPS_ENDPOINT` isn't set (boundary §3: "do not override endpoints with non-FIPS URLs") | Remove `S3_ENDPOINT_URL`; set `AWS_USE_FIPS_ENDPOINT: "true"` |
| F3 | `values.yaml:36`, `deployment.yaml`, `Dockerfile` | Empty `securityContext`, no `USER`, so the pod runs as root with a writable root filesystem and all capabilities | Copy `ingest-api`: `runAsNonRoot`, `runAsUser: 10001`, seccomp `RuntimeDefault`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`, drop ALL, `/tmp` emptyDir |
| F4 | `values.yaml:4-6` | `tag: latest`, `pullPolicy: Always`, so you can't tell what's running and can't roll back | `tag: ""` + `required` in the template, set to the git SHA by CI; `IfNotPresent` |
| F5 | `values.yaml:19`, `main.py` | `LOG_LEVEL: DEBUG` in govhigh: boto/urllib3 debug output includes signed request details | `INFO` |
| F6 | `requirements*.txt`, `Dockerfile:5` | No hash pinning (`--require-hashes`), unlike the reference | `pip-compile --generate-hashes` |
| F7 | `serviceaccount.yaml` | No `automountServiceAccountToken: false` on the SA | Match `ingest-api` |

---

## G. Follow-up

- **G1 (Pre-prod, not Follow-up). Missing code:** the `worker` and `migrate` modules invoked by the chart
  (`deployment.yaml:34`, `migration-job.yaml:47`) are **not in the PR**. The
  code that reads `raw-ingest`, runs pyarrow on customer data, and creates
  ConfigMaps across namespaces hasn't been reviewed. I can't approve a
  deployment of code I haven't seen. It can merge with
  the flag off, but **must be reviewed before prod rollout**.
- **G2. Unverified testing claims:** `terraform plan` was never run against
  govhigh, and all testing happened in the **commercial** staging account. That
  says little about govhigh behaviour, as E2's `arn:aws:` shows. Platform runs
  the plan once A–E are addressed.
- **G3. Unbounded exports:** there's no limit on export size or date range per
  request and no per-tenant concurrency limit. One request for "12 months" from
  every user is a cost and DoS risk. Suggest a max range and one active export
  per tenant.
- **G4. Audit logging:** the access log line should be an audit event (who,
  which tenant, which export, when, from where) sent to the in-boundary audit
  stream. It's fine as `log.info` for now.
- **G5. Weak DLQ:** the DLQ has no alarm and uses default retention. Add a
  CloudWatch alarm on DLQ depth.

## H. Nit

- **H1. Error responses:** `HTTPException(404)` responses have no body. Add a
  short `detail`; it helps the portal team.
- **H2. Design doc staleness:** `docs/design/data-export.md` should be updated
  to match whatever ships (no DR, no SaaS Sentry, short-lived URLs).

## I. No action: looked at and fine

- **SQL injection (`db.py`):** all queries use psycopg `%s` parameters with the
  values passed separately. No string formatting, so no injection.
- **DB TLS (`db.py:17`):** `sslmode="require"`. Data in transit to RDS is encrypted.
- **SQS queues (`data_export.tf:138-150`):** queue and DLQ both use a CMK, with
  `maxReceiveCount=5`, and a 900s visibility timeout for long-running jobs.
- **KMS key (`data_export.tf:121-136`):** rotation enabled. The key policy grants
  the account root `kms:*`, which is the AWS default pattern: it hands access
  control to IAM rather than granting anyone access directly. Needs no change
  once E2 is fixed.
- **Bucket basics:** versioning is enabled, and so are `block_public_acls` and
  `ignore_public_acls`.
- **Role ARN (`values-govhigh.yaml:2`):** uses `arn:aws-us-gov:`, the correct
  partition.
- **PGDG apt repo (`Dockerfile:10-13`):** fetched over `http://` but pinned with
  `signed-by=` to the PGDG key, so packages are signature-checked. Acceptable,
  though F1 should replace the repo anyway.
- **Database port egress:** port 5432 is limited to `10.40.0.0/16`, which is
  reasonable pending E3.
- **Export ID generation:** `uuid4()` export IDs come from a CSPRNG. They're
  fine as identifiers, though not as authorization (B2).

---

## The fix I implemented (`review/maxwell-li`, commit "fix(export-service): verify session JWTs and scope downloads to tenant")

Changes:
- **`app/main.py`:**
  - JWKS-based JWT verification (RS256 pinned; `iss`/`aud`/`exp`/`iat`/`sub`/`tenant_id` required)
  - 401/503 handling
  - typed request body (no 500 on missing keys; rejects reversed ranges)
  - `export_id: UUID`
  - TTL default 15 min, capped at 1 h
  - URL no longer logged
- **`app/db.py`:** `get_export(export_id, tenant_id)` filters by tenant in SQL.
- **`requirements.txt`:** `PyJWT[crypto]==2.10.1`. This also fixes scan
  finding CVE-2026-90118 (issuer partial match), which would have mattered as
  soon as issuer checks were on, and adds the crypto backend RS256 needs.
- **`values.yaml` / `values-govhigh.yaml`:** `JWT_ISSUER`, `JWT_AUDIENCE`,
  `JWT_JWKS_URL`; TTL 900. The service **fails to start** if these are unset
  rather than silently accepting tokens. The govhigh JWKS URL is marked
  TODO for the portal team to confirm.
- **`tests/test_auth.py`:** 14 tests covering owner allowed, other tenant 404,
  forged signature, `alg=none`, wrong/partial-match issuer, wrong audience,
  expired token, missing/empty tenant, URL absent from logs. All pass locally.

**Why this one.** It's the only finding that combines all three of these:
1. It lets **any user read any tenant's CUI today**. B1 and B2 together turn a
   UUID into a download link.
2. It **would survive the rest of the cleanup.** Moving to ECR, KMS, or
   in-boundary Sentry doesn't touch it, and a reviewer could easily approve a
   cleaned-up PR with it still there.
3. It's **code, not deletion.** The boundary items (A1–A3) are mostly "remove
   the line"; the author can do those in an hour. Getting JWT verification right
   (pinned algorithms, required claims, issuer exact-match, JWKS failure
   behaviour) is easy to get subtly wrong, so it's where a reviewer adds the
   most.

It's also on the critical path for the reduced Friday scope in `decision.md`.
Whatever ships has to have this.

I deliberately did **not** change Terraform. I can't run `terraform plan`
against govhigh, and an unverified IAM/bucket diff is worse than a precise
review comment. D1–D3 and E1–E2 are mechanical copies of `ingest_api.tf`.
