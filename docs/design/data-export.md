# Design: Customer Bulk Data Export (govhigh)

Author: Data Products team  ·  Status: Ready for review  ·  Target: **this Friday**

## Why

Our largest federal customer (a DoD program office) has a contract milestone
this Friday. It requires them to pull 12 months of line-level production data
into their own analysis environment as Parquet. Today they can only export CSV
through the portal, 10k rows at a time. Leadership has committed to the date.

## What

A new service, `export-service`, runs in the `exports` namespace:

1. A user in the portal clicks **Export** and picks a date range. The portal
   calls `POST /exports`.
2. `export-service` puts a job on SQS (`export-jobs`). A worker in the same
   deployment reads the tenant's raw objects from `raw-ingest`, converts them
   to Parquet with `pyarrow`, and writes the result to the new
   `customer-exports` bucket.
3. When the job is done, the portal calls `GET /exports/{id}/download`. That
   returns a **presigned S3 URL**, and the user downloads straight from S3.

### Decisions and trade-offs

- **Presigned URLs valid for 7 days.** The customer moves files into an
  air-gapped network using a manual transfer process that often runs over the
  weekend. Short-lived links kept expiring in UAT.
- **Portal previews.** The portal shows a small preview (first 50 rows as a
  thumbnail image) that it loads straight from the bucket. We added a bucket
  policy that allows `GetObject` when the `Referer` is the portal, so the
  browser can load previews without a presigned URL per thumbnail.
- **DR.** Exports are replicated to our existing DR bucket in the commercial
  DR account (`us-east-2`). Standing up replication into the GovCloud DR
  account would mean new account plumbing we can't do by Friday, and the
  commercial DR bucket already exists.
- **Error tracking.** We report errors to our team's existing Sentry project,
  so the Data Products on-call rotation sees govhigh and commercial errors in
  one place.
- **KMS.** We created a new CMK for the export queue. In staging, the IAM
  policy scoped to the new key's ARN kept failing with KMS `AccessDenied`
  once the worker started processing jobs. We widened it to `*` to unblock and
  will tighten it after launch.
- **Migrations.** A Helm pre-install hook runs migrations. It creates the
  `exports` schema and a `export-config` ConfigMap in each tenant namespace.
  Because it touches many namespaces, the hook runs as `cluster-admin`. It's
  short-lived and only runs during deploys.
- **Images.** Data Products builds images in our team pipeline and pushes them
  to Docker Hub (`foundryeng/`). Mirroring to ECR is a follow-up ticket
  (DP-2291).
- **Reads `raw-ingest`.** The export worker needs read access to the raw
  ingest bucket. That's the source data, so this is expected.
- **CODEOWNERS.** We added Data Products as owners of the new service paths so
  we can iterate quickly without blocking the Platform team.

## Testing

- Tested end-to-end in `staging` (commercial account) with synthetic data.
- Load tested with a 40 GB export.

## Rollout

Merge Wednesday, deploy Thursday, customer pulls Friday.
