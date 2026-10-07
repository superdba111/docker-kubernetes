# PR B: deferred production export proposal

These files preserve the prior deployment proposal as review evidence, not
active infrastructure. Terraform, chart files, scripts and the publishing
workflow have `.txt` extensions. They are outside active Terraform, Helm and
GitHub Actions paths. Do not restore or execute them as an approval shortcut.

## PR A: the current foundation

Retains application tenant checks, dependency locks, tests, Dockerfile and
review findings. Its export workflow only tests on a hosted runner: no image
build/push, AWS OIDC or production deployment. It adds no export Terraform
resources, installable export chart, secrets synchronization or migration hook.
It is not a customer export release. Existing ingest infrastructure is unchanged.

## PR B: required before restoring deployment

1. Platform + Security resolve A5 through a boundary change record, advance
   notice and required lead time, or establish explicit existing authorization
   through that process. Include any DR and customer-delivery changes.
2. Data Products supplies worker and migration code, including tenant selection,
   scoped credentials, retry/idempotency, parsing limits and state transitions.
3. Platform confirms endpoints, private DNS, pod ENIs, security groups, namespace
   default-deny, DB identity/TLS, package mirror and OIDC/runner isolation.
4. Remediate bundled DB TLS FIPS or approve/register RA-2026-015. Do not treat a
   draft as approval. Confirm dependency versions inside the final built image.
5. Build the hardened image, inventory it, enforce the scan gate, review the
   GovCloud plan and rendered manifests, then validate deployment and rollback.
6. Confirm credential revocation/password rotation and required reviews. Restore
   publishing only in the separately reviewed PR B, not through a repository
   variable that silently turns it on in PR A.

The archived workflow and chart are proposals, not verified runnable artifacts.
The Terraform-to-Helm script still needs deploy-pipeline integration. Worker
session-tag selection remains a compromised-worker risk until independently
enforced. RA-2026-016 is also deferred, not executable under PR A.

## Handoff

On the current review branch, PR A is represented by removing active deployment
assets and preserving them here. No second Git branch or GitHub PR was created.
A maintainer can open PR B from the merged foundation and restore reviewed
assets from these text references. Every restoration must include the actual
approvals and validation evidence; moving files back is not sufficient.

The scope tests detect this split's known paths and privilege-bearing workflow
strings; they are regression tripwires, not a comprehensive policy engine.
Security review still must inspect the complete diff and deployment mechanisms.

This strategy assumes the export feature was never deployed. If any resources
exist in Terraform state or a Helm release, stop: removing configuration could
plan destruction or affect existing workloads. Review state/plan and use a
separate, approved migration/decommission plan instead of applying this split.
