# Security review: `feature/data-export` → `main` (export-service)

Reviewer: @foundry/security-review (Maxwell Li) · Reviewed at PR head `fcbf06d`
Rules applied: `docs/authorization-boundary.md`, `docs/security-review-policy.md`.
Pattern baseline: `ingest-api` (SR-2026-031).

**Outcome: Changes requested.** 4 × Blocker (boundary), 15 × Blocker, 17 × Pre-prod,
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
**Blocker (boundary)** · *fixed in this branch*

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
**Blocker (boundary)** · *fixed in this branch*

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
**Blocker (boundary)** · *fixed in this branch* (CI pushes to ECR; image built on the hardened base, F1)

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

**Status (done in this branch, `d0fd221`):** streaming through the portal is
now the **default** (`download.mode: stream`). Presigned S3 links are off. The
chart refuses to render `presigned` without `download.issoApprovalRef`. That
check is **presence-only**, a breadcrumb, not proof of approval. The real
control is review: `helm/` is owned by Platform and Security Review (C3), so
flipping the mode is a reviewed change, and the reviewer checks the referenced
approval exists.

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

**Why the flag alone isn't enough:** the flag decides *whether* exports run.
Once a tenant is on, the worker role still reached every tenant. A static IAM
policy can't follow "the tenant of the current job", so access has to be scoped
per job.

**Status: IAM side done (`1f5770a`); worker side not reviewable (G1).**
- **Worker's own role:** no access to customer data. It can only consume the
  queue and assume `export-job`.
- **`export-job` role:** the session must carry exactly one tag, `tenant_id`.
  S3 access is limited through `${aws:PrincipalTag/tenant_id}` to
  `raw-ingest/<tenant>/*` and `customer-exports/<tenant>/*`; KMS only through
  S3. I used session tags rather than an inline session policy, so the role's
  own policy enforces the prefix and worker code can't widen it.
- **What the worker code must do (to verify at G1 review):** read the job row
  by `id` and use *its* `tenant_id`, never the SQS message's; do all S3 work
  with the `export-job` credentials; re-assume for jobs over 1 hour (the
  role-chaining limit).

**Limits, stated rather than hidden:**
- **A compromised worker can still pick any tenant's tag.** The job row helps
  against bugs, not against a compromised worker. Closing it needs a broker
  that issues the per-job session from the verified request (e.g. the API).
  That's a design follow-up, and the reason the worker review is a hard gate.
- **Key layout:** assumes `raw-ingest` keys are `<tenant_id>/...`. The ingest
  code is in another repo; Ingest team to confirm.

### B5. `values-govhigh.yaml`, NetworkPolicy: JWKS fetched from the public portal hostname
**Pre-prod** · *fixed in this branch* (`d0fd221`) · found in third-pass review

My B1 fix pointed `JWT_JWKS_URL` at `https://portal.foundry-gov.example/...`,
while the NetworkPolicy I wrote (E4) only allowed egress to `sentry` and RDS.
In govhigh the key fetch would be blocked, and **every request would fail
closed with 503**. That's safe, but broken. The URL now points at the in-cluster
portal service, and the API alone gets egress to the `portal` namespace on 443.
Portal team to confirm the service name and the token issuer.

### B6. `app/main.py` download: the API trusts the DB row's `s3_key`
**Pre-prod** · *fixed in this branch* (`49af428`) · found in fifth-pass review

The lookup is tenant-scoped, but the API then streams or signs whatever
`s3_key` the row holds, and its role can read the whole exports bucket. A worker
bug or a tampered row would hand one tenant another tenant's file.

**Fix (done):**
- **Key check:** the key must be under the caller's `<tenant_id>/` prefix;
  otherwise 404, plus an error log.
- **Strict tenant format:** `tenant_id` must match
  `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`. It's used as an S3 prefix and an IAM
  session tag, so no `/`, wildcards or lookalikes (`tenant-a` vs `tenant-ab`).
- **Tests:** rogue key, lookalike prefixes, malformed tenants.

### B7. `app/db.py`: one database connection shared by every request thread
**Pre-prod** · *fixed in this branch* (`59436f8`) · found while fixing G3

The PR's `db.py` opened one global psycopg connection and shared it across
FastAPI's request threads. Statements from concurrent requests could land in
each other's transactions, so neither tenant scoping nor any lock could be
relied on.

**Fix (done):** a connection pool, one connection per request. That's also what
makes the G3 concurrency fix work.

---

## C. Blocker: credentials and supply chain

### C1. `.github/workflows/export-service.yml:3-42`: `pull_request_target` runs fork code with govhigh deploy secrets
**Blocker** · *fixed in this branch*; **credential revocation still outstanding (ops)**

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
**Blocker** · *fixed in this branch*; **rotation in RDS still outstanding (ops)**

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
**Blocker** · *fixed in this branch*

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
**Blocker** · *fixed in this branch* (ConfigMap seeding removed; see C4 note in the fix section)

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

### C5. `.github/workflows/export-service.yml`: untrusted PR code on the govhigh runner, with `id-token: write`
**Pre-prod** · *fixed in this branch* · found in second-pass review

Even after C1, my first rewrite (copying `ingest-api.yml`) ran PR code on the
`govhigh-builder` self-hosted runner in a job granted `id-token: write`. PR code
then ran on infrastructure inside the boundary, next to whatever ambient
credentials or cached images the runner has. It could request an OIDC token;
only the role's trust policy stood between it and AWS.

**Fix (done):**
- **`test` job:** unit tests only, on an ephemeral GitHub-hosted runner with
  `contents: read`. Public code only, no secrets, no CUI.
- **`publish` job:** runs only on push to `main`. It's the only job on the
  govhigh runner, and the only one with `id-token: write`. It logs in to ECR
  with OIDC before building, so pulling the base image doesn't rely on ambient
  runner credentials.
- **Trade-off:** PRs no longer build or scan the image, because the hardened
  base is in private ECR. The scan still gates every image before it reaches
  ECR.
- **Follow-up for Platform:** confirm `govhigh-builder` runners are ephemeral
  and have no instance-profile credentials. **`ingest-api.yml` has the same
  pattern.**

---

## D. Blocker: export bucket (`data_export.tf:9-60`)

### D1. `:39-60, :31-37`: bucket readable by anyone who sends the portal's Referer header
**Blocker** · *fixed in this branch*

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
**Blocker** · *fixed in this branch*

Boundary §2: "SSE-S3 (`AES256`) is not accepted for customer data." Use
`aws:kms` with `data.aws_kms_key.customer_data.arn` and `bucket_key_enabled`,
exactly as `raw_ingest` does.

### D3. Missing access logging and lifecycle
**Blocker** · *fixed in this branch*

Boundary §2 requires both for customer-data buckets.
- **Logging:** add `aws_s3_bucket_logging` → `data.aws_s3_bucket.access_logs`,
  prefix `customer-exports/`.
- **Lifecycle:** exports can be regenerated, so keep them only briefly. Suggest
  expiring after 14 days, with `noncurrent_version_expiration` 1 day. Data
  Products to confirm what the contract requires.

---

## E. IAM / network (`data_export.tf:151-244`)

### E1. `:155-167`: IRSA trust allows any namespace and doesn't check `aud`
**Blocker** · *fixed in this branch*

`StringLike` on `system:serviceaccount:*:export-service`, with no `:aud`
condition. Anyone who can create a ServiceAccount named `export-service` in
**any** namespace gets this role, and with it all tenants' raw and exported
data. Boundary §4 requires both pinned. **Instead:** `StringEquals` `:aud` =
`sts.amazonaws.com`, `StringEquals` `:sub` = `system:serviceaccount:exports:export-service`.

### E2. `:181-206`: hardcoded `arn:aws:` ARNs, `kms:*` on `*`, `sqs:*`
**Blocker** · *fixed in this branch*

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
**Blocker** · *fixed in this branch* (raised from Pre-prod in second-pass review: §5 says NAT egress must be allow-listed, and there's no exception for it)

Boundary §5 says AWS services go through VPC endpoints and NAT egress is
allow-listed. Once A2 is fixed, nothing legitimate needs the internet.

**Fix (done, two steps):**
- **`b63f93d`:** removed `0.0.0.0/0`.
- **`00cd76d`:** replaced the remaining CIDR rules (443 to the whole VPC, 5432
  to `10.40.0.0/16`) with named destinations: the S3 gateway prefix list, the
  interface-endpoint SG, the EKS cluster SG (in-cluster Sentry, portal JWKS,
  DNS), and the exports RDS SG.

Platform to confirm the two SG names I assumed (`foundry-govhigh-vpc-endpoints`,
`foundry-govhigh-exports-db`).

**E6, Pre-prod, found in fifth-pass review, fixed in `030593b`:** none of this
governed anything, because nothing attached the SG to the pods. Now:
- **Attachment:** a `SecurityGroupPolicy` in the chart selects the api,
  worker and migrate pods. Rendering fails if a tenant is enabled without it.
- **Matching ingress rules:** SG-to-SG rules need both sides, so the cluster,
  endpoint and RDS SGs get ingress from the export SG. I didn't add the cluster
  SG to the pods, because that would bring its allow-all egress.
- **Probes:** ingress from the cluster SG on 8080 for kubelet probes.
- **Platform to confirm** `ENABLE_POD_ENI` on the VPC CNI. The Kubernetes NetworkPolicy still uses an
`ipBlock` for RDS, because NetworkPolicy can't reference AWS security groups;
the pod SG is the precise control.

### E7. NetworkPolicies didn't allow DNS or the AWS endpoints
**Pre-prod** · *fixed in this branch* (`dbf566a`) · found in sixth-pass review

My policies assumed a "platform-egress" policy would provide DNS and AWS API
access. Nothing in the repo shows that policy exists. Under default-deny, every
DNS lookup and AWS call from the api and worker would fail.

**Fix (done):**
- **DNS:** every policy now allows `kube-dns` on 53 UDP/TCP.
- **AWS endpoints:** api and worker allow 443 to the interface-endpoint
  addresses, which Terraform outputs as `export_service_endpoint_cidrs`.
- **Render gate:** the chart refuses to enable a tenant without those
  addresses.
- **Keeping them in sync (seventh-pass review, `5a5f715`):** endpoint addresses change if an
  endpoint or its subnets are recreated, and a stale list silently breaks AWS
  calls. `helm/charts/export-service/scripts/tf-values.py` turns
  `terraform output -json` into the values file, so nobody copies addresses by
  hand. `--check` compares against `helm get values` and exits 1 on drift.
  **Platform to wire both into the deploy job**; the repo has no Helm deploy
  pipeline today.

### E8. FIPS S3 calls had no network path
**Pre-prod** · *fixed in this branch* (`dbf566a`) · found in sixth-pass review

With `AWS_USE_FIPS_ENDPOINT=true` the SDK calls `s3-fips.us-gov-west-1`
(verified with botocore). The SG only allowed the S3 **gateway** endpoint, which
doesn't serve the FIPS host. My F2 fix turned FIPS on without a route to it.

**Fix (done):** Terraform now looks up the interface endpoints for exactly the
hosts the SDK resolves: `s3-fips`, `sqs`, `sts`. The pods never call KMS
directly; S3 and SQS do that for them.
- **Plan fails** if any endpoint is missing, isn't an Interface endpoint, or
  lacks private DNS.
- **Security groups:** rules target those endpoints' own SGs, which also
  removes the endpoint-SG name I'd guessed.
- **Platform:** create any missing endpoint. Plan will name it.

### E4. Missing service NetworkPolicy
**Pre-prod** · *fixed in this branch*

The platform baseline applies namespace default-deny. The chart needs its own
allow policy, as `ingest-api` has: ingress from `ingress-nginx` only, egress to
`sentry` plus VPC endpoints and RDS. **Platform to confirm** that the new
`exports` namespace actually gets the baseline default-deny. If it doesn't, the
pod is reachable from everywhere in the cluster.

### E5. `deployment.yaml:17`, `data_export.tf` IRSA: API and worker share one pod and one role
**Blocker** · *fixed in this branch* · found in a second-pass review, not my first pass

The `api` and `worker` containers run in the same pod under one service
account, so the portal-facing API holds the worker's permissions: read access
to **every tenant's** raw data and write access to the export bucket. Any bug
in the API (say an SSRF or a library RCE like the gunicorn/pyarrow rows in the
scan) is then a bug with cross-tenant data access.

**Fix (done):** separate Deployments, ServiceAccounts and IRSA roles.
- **API (`exports:export-api`):** `s3:GetObject` and `kms:Decrypt` on exports,
  the minimum for signing download URLs (a presigned URL carries the signer's
  permissions); `sqs:SendMessage`. No access to `raw-ingest`.
- **Worker (`exports:export-worker`):** read `raw-ingest`, put exports,
  consume the queue.

The worker's own role was later reduced further, to queue access plus a
tenant-scoped per-job role (B4).

---

## F. Pre-prod: workload and image hardening

✅ = fixed in this branch.

| # | Where | Finding | Instead |
|---|---|---|---|
| F1 ✅ | `Dockerfile:1,7` | `python:3.12-slim` from Docker Hub, not the hardened FIPS image (boundary §3). This base also accounts for most of the OS findings in the scan | `…/hardened/python:3.12-fips`. **libpq 17 isn't needed:** I checked, and the app uses psycopg[binary]'s bundled libpq 16.1, so the PGDG packages were dead weight. Removed, along with the public apt repo (fetched over `http`) |
| F2 ✅ | `values.yaml:14`, `main.py:28-32` | `S3_ENDPOINT_URL` overrides the endpoint with a **non-FIPS** URL, and `AWS_USE_FIPS_ENDPOINT` isn't set (boundary §3: "do not override endpoints with non-FIPS URLs") | Remove `S3_ENDPOINT_URL`; set `AWS_USE_FIPS_ENDPOINT: "true"`. The SQS `EXPORT_QUEUE_URL` is **not** a problem: I checked botocore 1.34, which sends SQS requests to the resolved client endpoint, not the QueueUrl host. In GovCloud the SQS FIPS endpoint *is* `sqs.us-gov-west-1.amazonaws.com` |
| F3 ✅ | `values.yaml:36`, `deployment.yaml`, `Dockerfile` | Empty `securityContext`, no `USER`, so the pod runs as root with a writable root filesystem and all capabilities | Copy `ingest-api`: `runAsNonRoot`, `runAsUser: 10001`, seccomp `RuntimeDefault`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`, drop ALL, `/tmp` emptyDir |
| F4 ✅ | `values.yaml:4-6` | `tag: latest`, `pullPolicy: Always`, so you can't tell what's running and can't roll back | `tag: ""` + `required` in the template, set to the git SHA by CI; `IfNotPresent` |
| F5 ✅ | `values.yaml:19`, `main.py` | `LOG_LEVEL: DEBUG` in govhigh: boto/urllib3 debug output includes signed request details | `INFO` |
| F6 ✅ | `requirements*.txt`, `Dockerfile:5` | No hash pinning (`--require-hashes`), unlike the reference, and no defined package source | `requirements.in` → hash-locked `requirements.txt` (`uv pip compile --generate-hashes`, linux/py3.12); `pip --require-hashes --only-binary=:all:`; index from `PIP_INDEX_URL`, **mandatory** (build fails if unset or if it carries credentials; pip config and extra indexes ignored; mirror auth only via a BuildKit secret, `5cba6d7`). **Platform to name the approved mirror** (`vars.GOVHIGH_PIP_INDEX_URL`) |
| F7 ✅ | `serviceaccount.yaml` | No `automountServiceAccountToken: false` on the SA | Match `ingest-api` |

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
- **G3. Unbounded exports:** there was no limit on date range and no per-tenant
  concurrency limit, a cost and DoS risk. *Mostly fixed (`49af428`):*
  - **Range:** at most 366 days.
  - **Concurrency:** one active export per tenant (429).
  - **Enqueue failure:** marks the job failed (503) instead of leaving it
    `queued`.

  - **Race:** *fixed (`59436f8`)*. Check and insert now run in one
    transaction under a per-tenant advisory lock, with no schema change. Tested
    against real Postgres 15: under 20 concurrent requests the old pattern
    admitted several, the new one exactly one.

  **Still open:**
  - **Size:** no cap on the output file yet.
  - **Duplicate requests:** no `Idempotency-Key`, so a double-click can still
    create two requests; the second gets 429.
- **G4. Audit logging:** the access log line should be an audit event (who,
  which tenant, which export, when, from where) sent to the in-boundary audit
  stream. It's fine as `log.info` for now.
- **G5. Weak DLQ:** the DLQ has no alarm and uses default retention. Add a
  CloudWatch alarm on DLQ depth.
- **G6 (Pre-prod, raised in third-pass review). psycopg[binary] bundles its own
  OpenSSL.** The wheel ships `libpq`, `libssl` and `libcrypto` (verified
  locally), so DB TLS doesn't use the hardened image's FIPS-validated OpenSSL.
  The PR's pin, 3.1.18, was worse: its Linux wheel bundles **OpenSSL 1.1, which
  has been end-of-life since 2023**. I bumped it to 3.2.3 (bundles OpenSSL 3;
  same as `ingest-api`), which fixes the end-of-life part but not the FIPS part.
  Boundary §3 requires FIPS modules in transit. `ingest-api` doing the same is
  **not** a justification: the rule wins over the reference. Before any tenant
  is enabled, one of these:
  - **Remediate:** Platform confirms the hardened image ships libpq linked to
    its FIPS OpenSSL, and we switch to `psycopg` (pure Python, uses system
    libpq) or `psycopg[c]`.
  - **Approved exception:** drafted as **RA-2026-015** in
    `review/exceptions/RA-2026-015-psycopg-openssl.md`. It applies to
    `ingest-api` too.

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
- **PGDG apt repo (original `Dockerfile:10-13`):** fetched over `http://` but
  pinned with `signed-by=` to the PGDG key, so packages were signature-checked.
  It was a boundary problem, not an integrity one, and is now removed (F1).
- **Export ID generation:** `uuid4()` export IDs come from a CSPRNG. They're
  fine as identifiers, though not as authorization (B2).

---

## What I fixed on this branch

### The fix I chose, and why
**Primary fix: tenant isolation for exports.** That's B1–B3 (the API) and D1–D3,
E1–E2, A1 (the bucket and IAM behind it), in commits `70fce0a` and `42eec9f`. If
I could only land one thing, it would be this, because:
1. **Impact today:** any user (B1+B2), or anyone at all (D1), can read any
   tenant's CUI.
2. **It would survive cleanup:** removing Sentry SaaS or Docker Hub doesn't
   touch it, and a reviewer could approve a tidied PR with it still there.
3. **It's where review adds the most:** getting JWT verification right (pinned
   algorithms, required claims, exact issuer match, fail-closed on JWKS errors)
   and finding the real KMS root cause are easy to get subtly wrong.

The API and bucket halves have to ship together. Fixing only the API leaves
every export readable with a faked `Referer` header; fixing only the bucket
leaves any user able to request a URL for another tenant's export.

### Everything else that's done
After a second-pass review, I also fixed the other findings that could be
fixed in-repo, mostly by copying `ingest-api`. One commit per theme:

| Commit | Findings | What changed |
|---|---|---|
| `70fce0a` | B1–B3 | JWT verified against JWKS (RS256, `iss`/`aud`/`exp`/`iat`/`sub`/`tenant_id` required, fails closed); lookup by `(id, tenant_id)`; 15-min URLs, never logged; `PyJWT[crypto]` 2.10.1; 14 tests |
| `42eec9f` | D1–D3, A1, E1, E2 | Bucket private + TLS-only + SSE-KMS (CMK) + logging + 14-day lifecycle; commercial replication removed; IRSA `aud`/`sub` pinned; partition-correct ARNs; KMS scoped to two keys; `sqs:*` removed |
| `06976c9` | E5, F2 | Separate API/worker Deployments, SAs and IRSA roles; FIPS endpoints via the SDK, no S3 override |
| `a94ddf8` | A2, C2 | ExternalSecret for `DB_PASSWORD`/`SENTRY_DSN` (pre-install hook, so migrations can use it); plaintext password and sentry.io DSN removed; `send_default_pii=False`, no request bodies; sentry-sdk 2.19.2 |
| `27d8e75` | C4, E4, F3–F5, F7 | Migrator has no K8s permissions (no cluster-admin, no token); pod/container hardening; NetworkPolicies; ECR image, required immutable tag; `LOG_LEVEL=INFO` |
| `089a611` | C1, A3 (CI), C3, scan | `pull_request` + OIDC + govhigh runner + ECR, gating trivy, pinned actions; CODEOWNERS keeps Platform/Security; `USER 10001`; pyarrow 15.0.2, gunicorn 23.0.0, requests 2.32.3, responses/moto bumped |
| `b63f93d` | F1, A3, E3 | Hardened FIPS base from ECR; PGDG repo, libpq 17, psql client, curl, gnupg removed (unused); SG egress limited to the S3 prefix list and VPC CIDR |
| `8fb1c5a` | B4/G1 gate | Per-tenant feature flag (`exports.enabledTenants`), empty by default: API returns 404 and queues nothing, worker at 0 replicas, migration hook off |
| `35e1fe1` | C5 | PR code tested on an ephemeral hosted runner with no OIDC; only main-branch publish uses the govhigh runner and `id-token: write` |
| `d0fd221` | A4, B5 | Download streamed through the portal by default; presigned only with `download.issoApprovalRef`; JWKS from the in-cluster portal, API-only egress to it |
| `00cd76d` | E3 | SG egress by security group / prefix list; no CIDR rules |
| `1f5770a` | B4 (IAM) | Worker role has no data access; per-job `export-job` role scoped by `tenant_id` session tag |
| `0ed306f` | F6 | Hash-locked requirements; `--require-hashes --only-binary=:all:`; package index from a build arg |
| `dd0fff4` | G6 | psycopg 3.1.18 → 3.2.3 (bundled OpenSSL 1.1 EOL → 3); RA-2026-015 drafted for the FIPS gap |
| `5cba6d7` | F6 | Package mirror mandatory; no credentials in build args (BuildKit secret instead) |
| `030593b` | E6 | `SecurityGroupPolicy` attaches the SG; matching ingress on destination SGs; probe ingress; migrate pods labelled + NetworkPolicy |
| `49af428` | B6, G3 | S3 key must be under the tenant prefix; strict `tenant_id` format; stream closes S3 body; range/concurrency limits; enqueue-failure handling; 32 tests |
| `dbf566a` | E7, E8 | Interface endpoints (s3-fips, sqs, sts) looked up, plan fails if missing / no private DNS; SG rules target their SGs; NetworkPolicy allows DNS + endpoint addresses, render gate |
| `59436f8` | B7, G3 | Connection pool; per-tenant advisory lock around check + insert; real-Postgres concurrency tests (opt-in) |
| `5a5f715` | E7 | `scripts/tf-values.py`: Terraform outputs → Helm values, plus `--check` drift detection |

**One behaviour change the author must confirm (C4).** The migrator no longer
seeds `export-config` ConfigMaps into tenant namespaces. That was the only
reason it had cluster-admin, and the code doing it isn't in the PR. If something
consumes those ConfigMaps, it needs a namespaced Role per tenant namespace,
reviewed by Security. Until then, the export service shouldn't depend on it.

### How to verify (no AWS account needed)
```
python3.12 -m venv .venv && .venv/bin/pip install --require-hashes -r services/export-service/requirements-dev.txt
.venv/bin/pytest services/export-service               # 32 passed, 4 skipped (DB tests)
# with a disposable Postgres: EXPORT_TEST_PG=1 DB_HOST=... DB_PORT=... DB_NAME=... DB_USER=... DB_PASSWORD=... DB_SSLMODE=disable  -> 36 passed
helm lint helm/charts/export-service -f helm/charts/export-service/values-govhigh.yaml --set image.tag=x
helm template t helm/charts/export-service -f helm/charts/export-service/values-govhigh.yaml   # fails: image.tag is required (intended)
cd terraform/envs/govhigh
terraform init -backend=false && terraform validate && terraform fmt -check   # init downloads the AWS provider; no credentials needed
```
I also checked FIPS endpoint resolution with botocore 1.34 and
`AWS_USE_FIPS_ENDPOINT=true`. S3 and presigned URLs resolve to
`s3-fips.us-gov-west-1.amazonaws.com`. SQS requests go to the resolved
`sqs.us-gov-west-1.amazonaws.com` even with a different `QueueUrl` host.

**Not verified:** no `terraform plan`, no image build, no trivy rescan, no
deploy. Platform needs to do those before this goes anywhere near govhigh.

### Still open: the decision stays no-ship until these are done
**Merge:** OK in the disabled state, after required reviews. The flag is off,
the worker runs 0 replicas, migrations are off, and delivery is streaming only.

**Enable any tenant:** not yet. That needs:

| # | What | Why it's not in this branch | Owner |
|---|---|---|---|
| 1 | **G1/B4: the `worker` and `migrate` code**, reviewed, with the worker taking `tenant_id` from the DB job row and doing all S3 work with `export-job` credentials | Code isn't in the PR. IAM side is done | Data Products |
| 2 | **Revoke** `GOVHIGH_DEPLOY_AWS_*` and `DOCKERHUB_TOKEN`; check CloudTrail for fork-PR runs | Operational, today | Platform + Security |
| 3 | **Rotate** the RDS password (still in git history); populate `govhigh/export-service/db-password` and the in-boundary Sentry DSN | Operational | Data Products + Platform |
| 4 | **G6: FIPS for DB TLS. A production gate.** RA-2026-015 is a draft and grants nothing until both approvers sign; otherwise remediate (system libpq on the hardened image) | Needs Platform's hardened-image answer and two approvers | Platform + Security + Platform EM |
| 5 | Confirm `raw-ingest` keys are `<tenant_id>/...` (B4 assumption) | ingest code is in another repo | Ingest team |
| 6 | Platform inputs: OIDC role `gha-ecr-push-export-service`, ECR repo, approved pip mirror (build fails without it), **`s3-fips`/`sqs`/`sts` interface endpoints with private DNS (plan fails without them, E8)**, exports RDS SG name (E3), review of the ingress rules added to baseline SGs and `ENABLE_POD_ENI` (E6), runner isolation (C5), `exports` namespace default-deny | Needs Platform | Platform |
| 7 | Portal: confirm in-cluster JWKS service name and token issuer (B5) | Portal team | Portal team |
| 8 | `terraform plan`, first image build, trivy rescan on the hardened base; wire `scripts/tf-values.py` (generate + `--check`) into the deploy job | Needs #6 | Platform |
| 9 | **A4:** only if presigned links are wanted, ISSO approval reference | Streaming works without it | ISSO |
| 10 | Export size cap and idempotency key (G3); scan Mediums/Lows within SLA; G4–G5 | Lower priority | Data Products |

### What I'd do next, in order
Items 2 and 3 today. Then 1, the real gate, alongside 4–7. Then 8, and enable
the launch tenant only after all of 1–8.
