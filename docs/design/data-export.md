# Customer export: foundation only (PR A)

The customer still needs a bulk Parquet export, but this change does not launch
that feature. It retains tested application security fixes and a test-only
workflow while deferring production infrastructure and deployment to PR B.

## Included

- JWT verification, tenant-scoped job lookup and object-prefix validation.
- Dependency locks, API tests and optional disposable-PostgreSQL tests.
- Hardened-image Dockerfile as source only; no automatic image publishing.
- Security review, scan triage and explicit deferred-launch ownership.

## Not deployable in this change

No active export Terraform, Helm chart, worker/migration launch, production
secrets synchronization, AWS publishing identity or customer enablement.
Deployment proposals are text-only references under `review/deferred/`.
The original design is preserved there for audit/review context.

## Later production flow

Portal → authenticated API → job metadata + SQS → tenant-scoped worker →
private CMK-encrypted export storage → authorized streaming via the portal.
This is a target architecture, not a verified running service. Worker and
migration implementations remain absent. The base worker can choose a session
tag, so the proposed IAM is not complete isolation against worker compromise.

## Gates

PR A still needs credential containment/rotation confirmation, required
reviewers and passing checks. It does not grant exception or compliance approval.
PR B must resolve the new-storage boundary change before deployment, provide
missing code, close DB TLS FIPS, and validate the built image and GovCloud plan,
network, identities and rollout. See `review/decision.md` and
`review/deferred/README.md`. Friday's self-service export remains no-ship.
