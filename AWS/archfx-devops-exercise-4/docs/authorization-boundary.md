# govhigh Authorization Boundary

Owner: Platform / Security Review  ·  Last reviewed: 2026-08-14

This document summarizes the rules that keep the `govhigh` environment inside
its FedRAMP High-aligned authorization boundary. It is the source of truth for
security review. If a change conflicts with this document, the change is wrong
or the document must be updated through a boundary change (see
`security-review-policy.md` §5).

## 1. In-boundary infrastructure

| Component            | Location                                                   |
|----------------------|------------------------------------------------------------|
| Primary              | AWS GovCloud `us-gov-west-1`, account `111122223333`       |
| Disaster recovery    | AWS GovCloud `us-gov-east-1`, account `444455556666`       |
| Container registry   | ECR in `111122223333` only (`*.dkr.ecr.us-gov-west-1.amazonaws.com`) |
| Logs                 | In-boundary Loki + CloudWatch Logs (`us-gov-west-1`)       |
| Error tracking       | Self-hosted Sentry at `https://sentry.govhigh.internal`    |
| Secrets              | AWS Secrets Manager (GovCloud), synced by External Secrets Operator |

Anything not in this table is **outside** the boundary. That includes the
commercial AWS partition (`aws`), SaaS tools (sentry.io, Datadog, Docker Hub,
GitHub-hosted package registries, etc.), and developer laptops.

## 2. Data handling

- Customer data in govhigh is treated as CUI. It **must not** be stored,
  replicated, processed, or transmitted outside the boundary. Error payloads,
  logs, and traces count as data.
- Customer data may leave the boundary only when delivered **to the customer
  who owns it**, over TLS, through an authenticated and authorized path.
- Encryption at rest: SSE-KMS with a customer-managed key (CMK) owned by the
  govhigh account. SSE-S3 (`AES256`) is not accepted for customer data.
- Buckets holding customer data must have S3 server access logging enabled and
  a lifecycle policy that matches the data's retention requirement.

## 3. Cryptography

- FIPS 140-validated cryptographic modules for data in transit and at rest.
- AWS API calls must use FIPS endpoints (e.g. `s3-fips.us-gov-west-1.amazonaws.com`).
  In Terraform set `use_fips_endpoint = true`. In SDKs set
  `AWS_USE_FIPS_ENDPOINT=true` and do not override endpoints with non-FIPS URLs.
- Container images must be built from the hardened FIPS base images in ECR:
  `111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/<runtime>:<version>-fips`.

## 4. Identity and access

- Workloads get AWS access only through IRSA. Trust policies must pin both
  `:aud` (`sts.amazonaws.com`) and `:sub` (exact namespace + service account).
- IAM policies must be scoped to specific resources. Wildcard (`*`) resources
  need a documented exception, except for actions that do not support
  resource-level permissions.
- Always build ARNs from `data.aws_partition.current.partition`. Never
  hardcode `arn:aws:`.
- Kubernetes RBAC: namespace-scoped Roles by default. ClusterRoles and
  ClusterRoleBindings need security review. `cluster-admin` is reserved for
  break-glass human access and is never bound to workloads.
- CI authenticates to AWS with GitHub OIDC. Long-lived IAM access keys are not
  permitted.

## 5. Network

- Every namespace has a default-deny NetworkPolicy. Each service declares the
  ingress and egress it needs.
- AWS services are reached through VPC endpoints. NAT egress is limited to an
  allow-listed set of destinations maintained by Platform.
- Only the `portal` ingress (behind WAF) is internet-facing.

## 6. Change management

Some changes alter the boundary itself and count as **significant changes**:
a new external service, a new interconnection, new data flows that cross the
boundary, or new storage locations for customer data. These need advance
notice to our FedRAMP partner and authorizing officials **before** deployment.
Lead time is typically 10+ business days. See `security-review-policy.md` §5.
