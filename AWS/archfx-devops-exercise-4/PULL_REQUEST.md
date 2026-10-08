# feat(export-service): customer bulk data export for govhigh

**Author:** @foundry/data-products (Data Products engineer)
**Base:** `main` ← **Head:** `feature/data-export`
**Reviewers requested:** @foundry/security-review, @foundry/platform
**Labels:** `govhigh`, `customer-commitment`, `urgent`

---

## Summary

Adds `export-service` so customers can bulk-export line data as Parquet and
download it from S3 through presigned URLs. Needed for the program office
customer's milestone on **Friday**. See `docs/design/data-export.md` for the
design and trade-offs.

## Changes

- `terraform/envs/govhigh/data_export.tf`: exports bucket, DR replication,
  SQS job queue + DLQ, KMS key, IRSA role, security group
- `helm/charts/export-service/`: new chart (API + worker containers,
  migration hook)
- `services/export-service/`: service code + Dockerfile
- `.github/workflows/export-service.yml`: build/scan/push pipeline
- `CODEOWNERS`: Data Products owns the new service paths
- `docs/design/data-export.md`: design doc

## Testing

- [x] End-to-end in `staging` with synthetic data
- [x] 40 GB export load test
- [x] `helm lint` passes
- [ ] `terraform plan` against govhigh (no access, Platform please run)

## Security considerations

Follows existing patterns (IRSA, KMS-encrypted queue, private subnets). Known
follow-ups are tracked: DP-2291 (ECR mirror), DP-2297 (KMS scope-down).

## Checklist

- [x] Design doc linked
- [x] No secrets committed
- [x] Tests pass
