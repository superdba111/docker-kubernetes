# foundry-platform

Infrastructure and deployment configuration for **Foundry Analytics** services
running in the `govhigh` environment (AWS GovCloud, FedRAMP High-aligned).

> Foundry Analytics is a fictional company. All names, account IDs, domains and
> identifiers in this repository are made up.

## Layout

```
docs/                         Policies every change must follow
  authorization-boundary.md   What is (and is not) inside the govhigh boundary
  security-review-policy.md   When security review is required, SLAs, exceptions
  templates/                  Risk acceptance / exception template
terraform/envs/govhigh/       Terraform root module for the govhigh environment
helm/charts/                  Helm charts, one per service
services/                     Service source + Dockerfiles
.github/workflows/            CI (build, scan, push to in-boundary ECR)
CODEOWNERS                    Required reviewers per path
```

## Reference implementation

`ingest-api` is the reference service. It has passed security review and is in
production. New services are expected to follow its patterns (IRSA, SSE-KMS,
External Secrets, NetworkPolicy, hardened FIPS base image, OIDC-based CI).

## Environments

| Env       | Partition     | Region          | Account        |
|-----------|---------------|-----------------|----------------|
| govhigh   | aws-us-gov    | us-gov-west-1   | 111122223333   |
| govhigh-dr| aws-us-gov    | us-gov-east-1   | 444455556666   |
| commercial| aws           | us-east-1       | 777788889999   |

The `commercial` environment is **outside** the govhigh authorization boundary.
See `docs/authorization-boundary.md`.
