# AWS Serverless Self-Service Database Platform

A full-stack AWS Database-as-a-Service (DBaaS) platform built by extending the existing **FastAPI + Vue.js Admin Portal** architecture.

The platform provides a self-service interface for developers to request standardized PostgreSQL and Microsoft SQL Server databases while maintaining centralized security, governance, Terraform state management, monitoring, and operational controls.

## Supported Database Engines

- Amazon RDS for PostgreSQL
- Amazon RDS for Microsoft SQL Server

Future support can include:

- Aurora PostgreSQL
- Aurora MySQL
- RDS MySQL
- DynamoDB
- ElastiCache / Redis
- Neptune

---

# Existing Project Reuse

This project builds directly on the existing `FastAPIs` application.

Existing components retained:

```text
Vue 3
FastAPI
API Gateway
AWS Lambda
Mangum
CloudFront
S3
Secrets Manager
SQLAlchemy
Terraform
```

The existing user administration APIs remain available.

```text
/users/
```

The new self-service database APIs are added alongside them:

```text
/databases/
```

---

# Architecture

```text
                               Developers
                                   |
                                   v
                         CloudFront Distribution
                                   |
                                   v
                            Private S3 Bucket
                                   |
                                   v
                              Vue 3 Portal
                                   |
                                   | HTTPS
                                   v
                             API Gateway
                                   |
                                   v
                      FastAPI Lambda + Mangum
                                   |
                +------------------+------------------+
                |                                     |
                v                                     v
        Existing User APIs                       DBaaS APIs
            /users/*                           /databases/*
                |                                     |
                v                            +--------+--------+
        Existing PostgreSQL                  |                 |
                                             v                 v
                                         DynamoDB             SQS
                                       Request State      Provision Queue
                                                               |
                                                               v
                                                        Worker Lambda
                                                               |
                                                               v
                                                        AWS CodeBuild
                                                               |
                                                               v
                                                           Terraform
                                                               |
                                              +----------------+---------------+
                                              |                                |
                                              v                                v
                                      PostgreSQL Module                SQL Server Module
                                              |                                |
                                              v                                v
                                      RDS PostgreSQL                   RDS SQL Server
                                              |                                |
                                 +------------+------------+      +------------+------------+
                                 |            |            |      |            |            |
                                 v            v            v      v            v            v
                              Secrets     CloudWatch     Backup Secrets     CloudWatch     Backup
                              Manager                              Manager
```

---

# Design Principle

Developers request a **database service**, not raw AWS infrastructure.

A developer supplies:

```json
{
  "application": "orders-api",
  "engine": "postgresql",
  "environment": "prod",
  "database_name": "orders",
  "size": "medium",
  "owner": "payments-team",
  "cost_center": "CC1023"
}
```

The developer does not choose:

```text
AWS instance class
VPC
subnets
security groups
KMS key
Multi-AZ
backup retention
storage configuration
parameter groups
option groups
public accessibility
```

Those values are managed by the platform.

---

# Repository Structure

```text
FastAPIs/
│
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── models.py
│   │   ├── schemas.py
│   │   │
│   │   ├── database_requests.py
│   │   ├── database_schemas.py
│   │   ├── request_store.py
│   │   └── queue_service.py
│   │
│   └── bootstrap.py
│
├── frontend/
│   └── src/
│       ├── App.vue
│       ├── main.js
│       └── components/
│           ├── UserAdmin.vue
│           ├── DatabaseRequest.vue
│           └── DatabaseStatus.vue
│
├── worker/
│   └── start_build.py
│
├── terraform/
│   │
│   ├── modules/
│   │   ├── frontend/
│   │   ├── backend/
│   │   ├── apigateway/
│   │   │
│   │   ├── dbaas-control-plane/
│   │   ├── terraform-runner/
│   │   │
│   │   ├── rds-postgresql/
│   │   ├── postgresql-service/
│   │   │
│   │   ├── rds-sqlserver/
│   │   └── sqlserver-service/
│   │
│   ├── database-instance/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── backend.tf
│   │
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf
│
└── README.md
```

---

# Existing FastAPI APIs

Existing endpoints remain unchanged:

```text
POST   /users/
GET    /users/
GET    /users/{id}
PATCH  /users/{id}
DELETE /users/{id}
```

These continue to use the existing SQLAlchemy/PostgreSQL implementation.

---

# New DBaaS APIs

Add:

```text
POST   /databases/
GET    /databases/
GET    /databases/{request_id}
DELETE /databases/{request_id}
```

Future APIs:

```text
POST /databases/{id}/resize
POST /databases/{id}/restore
POST /databases/{id}/snapshot
POST /databases/{id}/upgrade
```

---

# Database Request Model

Example Pydantic model:

```python
from typing import Literal, Optional
from pydantic import BaseModel


class DatabaseRequest(BaseModel):

    application: str

    engine: Literal[
        "postgresql",
        "sqlserver"
    ]

    environment: Literal[
        "dev",
        "test",
        "stage",
        "prod"
    ]

    database_name: str

    size: Literal[
        "small",
        "medium",
        "large"
    ]

    owner: str

    cost_center: str

    edition: Optional[str] = None
```

---

# FastAPI Provisioning Endpoint

The FastAPI Lambda does not run Terraform directly.

```python
@app.post("/databases/")
def create_database(request: DatabaseRequest):

    request_id = create_request(request)

    save_request(
        request_id=request_id,
        request=request,
        status="PENDING"
    )

    send_to_queue(
        request_id=request_id,
        request=request
    )

    return {
        "request_id": request_id,
        "status": "PENDING"
    }
```

---

# Why Terraform Does Not Run Inside FastAPI

Avoid:

```text
API Gateway
     |
FastAPI Lambda
     |
terraform apply
```

Terraform database provisioning may take many minutes.

Instead:

```text
API Gateway
     |
FastAPI
     |
     +---- DynamoDB
     |
     +---- SQS
             |
             v
        Worker Lambda
             |
             v
         CodeBuild
             |
             v
         Terraform
```

The API returns immediately.

Example:

```json
{
  "request_id": "DB-10243",
  "status": "PENDING"
}
```

---

# DynamoDB Request Store

DynamoDB tracks provisioning state.

Example:

```text
PK              REQUEST#DB-10243

request_id      DB-10243
engine          postgresql
application     orders-api
environment     prod
database_name   orders
size            medium
owner           payments-team
cost_center     CC1023

status          PROVISIONING

created_at      timestamp
updated_at      timestamp
```

Supported statuses:

```text
PENDING
APPROVAL_REQUIRED
APPROVED
PLANNING
PROVISIONING
READY
FAILED
DELETING
DELETED
```

---

# SQS

FastAPI sends a provisioning request to SQS.

Example:

```json
{
  "request_id": "DB-10243",
  "engine": "postgresql",
  "application": "orders-api",
  "environment": "prod",
  "database_name": "orders",
  "size": "medium",
  "owner": "payments-team"
}
```

SQS decouples the API from Terraform provisioning.

---

# Worker Lambda

The worker consumes SQS messages.

The Lambda should **not execute Terraform itself**.

Its responsibility is to start an AWS CodeBuild job.

Example:

```python
import boto3

codebuild = boto3.client("codebuild")


def handler(event, context):

    for record in event["Records"]:

        message = record["body"]

        codebuild.start_build(
            projectName="dbaas-terraform-runner",
            environmentVariablesOverride=[
                {
                    "name": "DB_REQUEST",
                    "value": message,
                    "type": "PLAINTEXT"
                }
            ]
        )
```

---

# Terraform Runner

AWS CodeBuild executes:

```text
terraform init

terraform validate

terraform plan

policy validation

terraform apply

terraform output
```

CodeBuild then updates DynamoDB with either:

```text
READY
```

or:

```text
FAILED
```

---

# Terraform State

Terraform state is stored in S3.

Each database receives its own state path.

Example:

```text
dbaas/postgresql/prod/orders/terraform.tfstate

dbaas/postgresql/dev/inventory/terraform.tfstate

dbaas/sqlserver/prod/finance/terraform.tfstate
```

This minimizes blast radius.

Do not use:

```text
all-databases.tfstate
```

for every database.

---

# Dynamic Backend

CodeBuild can initialize Terraform with a database-specific state key.

Example:

```bash
terraform init \
  -backend-config="bucket=my-terraform-state" \
  -backend-config="region=us-east-1" \
  -backend-config="key=dbaas/${ENGINE}/${ENVIRONMENT}/${DATABASE_NAME}/terraform.tfstate"
```

---

# PostgreSQL Modules

Two layers are used:

```text
postgresql-service
       |
       v
rds-postgresql
       |
       v
Amazon RDS PostgreSQL
```

The low-level module owns AWS configuration.

The service module exposes business-level inputs.

---

# PostgreSQL Service Sizes

Example:

```hcl
locals {

  postgresql_sizes = {

    small = {
      instance_class = "db.t4g.medium"
      storage        = 50
    }

    medium = {
      instance_class = "db.m7g.large"
      storage        = 200
    }

    large = {
      instance_class = "db.r7g.xlarge"
      storage        = 500
    }
  }
}
```

---

# PostgreSQL Production Defaults

Production automatically enables:

```text
Multi-AZ
KMS encryption
private networking
30-day backups
PITR
deletion protection
final snapshot
CloudWatch logs
Database Insights
Secrets Manager
```

---

# SQL Server Modules

SQL Server follows the same product model:

```text
sqlserver-service
       |
       v
rds-sqlserver
       |
       v
Amazon RDS SQL Server
```

---

# SQL Server Editions

Supported portal options can include:

```text
Express
Web
Standard
Enterprise
```

Terraform mappings:

```text
Express       -> sqlserver-ex
Web           -> sqlserver-web
Standard      -> sqlserver-se
Enterprise    -> sqlserver-ee
```

Enterprise edition can require additional approval because of licensing cost.

---

# SQL Server Features

The SQL Server module can support:

```text
Multi-AZ
KMS encryption
Secrets Manager
parameter groups
option groups
SQL Server Agent
native .bak backup/restore
S3 backup integration
CloudWatch logging
Database Insights
Windows Authentication
```

---

# Common Security Controls

All databases must enforce:

```text
publicly_accessible = false
```

Require:

```text
storage encryption
KMS
private subnets
approved security groups
Secrets Manager
backup policies
mandatory tags
```

Never allow:

```text
0.0.0.0/0 -> 5432
```

or:

```text
0.0.0.0/0 -> 1433
```

---

# Portal

The existing Vue application becomes a multi-function administration portal.

Example navigation:

```text
+-------------------------------------------+
| AWS Platform Admin                        |
+-------------------------------------------+
|                                           |
| Users                                     |
|                                           |
| Database Self-Service                     |
|                                           |
| My Database Requests                      |
|                                           |
| Platform Status                           |
|                                           |
+-------------------------------------------+
```

---

# Database Request UI

```text
+------------------------------------------------+
|          Request New Database                  |
+------------------------------------------------+
|                                                |
| Application       [ orders-api             ]   |
|                                                |
| Engine            [ PostgreSQL            ▼]   |
|                                                |
| Database Name     [ orders                 ]   |
|                                                |
| Environment       [ Production            ▼]   |
|                                                |
| Size              [ Medium                ▼]   |
|                                                |
| Owner             [ Payments Team          ]   |
|                                                |
| Cost Center       [ CC1023                 ]   |
|                                                |
|              [ Create Database ]               |
+------------------------------------------------+
```

If SQL Server is selected:

```text
Edition

[ Standard ▼ ]
```

is displayed.

---

# JavaScript / Vue API Call

Example:

```javascript
async function createDatabase() {

  const request = {
    application: form.application,
    engine: form.engine,
    environment: form.environment,
    database_name: form.databaseName,
    size: form.size,
    owner: form.owner,
    cost_center: form.costCenter,
    edition: form.edition
  }

  const response = await axios.post(
    `${apiUrl}/databases/`,
    request
  )

  requestId.value = response.data.request_id
}
```

---

# Database Status Page

Example:

```text
Request ID       DB-10243

Engine           PostgreSQL

Database         orders

Environment      Production

Size             Medium

Status           PROVISIONING
```

When completed:

```text
Status           READY

Endpoint         orders.xxxxxx.us-east-1.rds.amazonaws.com

Port             5432

Credentials      AWS Secrets Manager
```

Passwords are never returned through the frontend.

---

# Existing Secrets Manager Integration

The current project already retrieves PostgreSQL credentials dynamically from Secrets Manager.

That implementation remains useful for the existing admin application.

The DBaaS platform extends the same security principle:

```text
Terraform
    |
    v
RDS-managed master credentials
    |
    v
Secrets Manager
```

The portal returns only a secret reference or ARN.

---

# Development vs Production

## Development

```text
Portal
   |
API
   |
SQS
   |
Terraform
   |
Automatic provisioning
```

## Production

```text
Portal
   |
API
   |
Policy check
   |
Approval
   |
Terraform plan
   |
Terraform apply
```

Production automatically enforces stronger HA, backup, and deletion-protection policies.

---

# CI/CD

Terraform module changes should run:

```text
terraform fmt

terraform validate

TFLint

Checkov

terraform test

terraform plan
```

Then:

```text
Pull Request
     |
Review
     |
Merge
     |
Version Tag
```

---

# Recommended Implementation Phases

## Phase 1

Keep the existing application working.

Add:

```text
rds-postgresql
postgresql-service
rds-sqlserver
sqlserver-service
```

Test both engines directly using Terraform.

## Phase 2

Add:

```text
DynamoDB request table
SQS queue
CodeBuild Terraform runner
worker Lambda
```

## Phase 3

Extend FastAPI:

```text
POST /databases/
GET /databases/
GET /databases/{id}
```

## Phase 4

Extend the existing Vue portal:

```text
Database Request
Database Status
My Databases
```

## Phase 5

Add:

```text
Cognito / enterprise SSO
RBAC
production approval
restore
resize
snapshot
upgrade
cost estimation
```

---

# Final Architecture

```text
                            Vue 3 Portal
                                 |
                          CloudFront + S3
                                 |
                                 v
                            API Gateway
                                 |
                                 v
                         FastAPI + Mangum
                           AWS Lambda
                                 |
           +---------------------+---------------------+
           |                                           |
           v                                           v
    Existing User APIs                          Database APIs
           |                                           |
           v                                   +-------+-------+
Existing PostgreSQL                            |               |
                                               v               v
                                           DynamoDB           SQS
                                                               |
                                                               v
                                                        Worker Lambda
                                                               |
                                                               v
                                                          CodeBuild
                                                               |
                                                               v
                                                          Terraform
                                                     /               \
                                                    v                 v
                                            RDS PostgreSQL       RDS SQL Server

                                                      |
                                             Terraform State
                                                      |
                                                      v
                                                     S3
```

# Summary

This project evolves the original FastAPI/Vue AWS application into a reusable internal Database-as-a-Service platform.

Existing components are preserved:

```text
Vue 3
CloudFront
S3
API Gateway
FastAPI
Lambda
Mangum
Secrets Manager
Terraform
```

New capabilities are added:

```text
DynamoDB
SQS
CodeBuild
DB provisioning worker
PostgreSQL service module
SQL Server service module
database request APIs
self-service database UI
```

The key architectural principle remains:

> Developers request standardized database products instead of directly configuring AWS database infrastructure.

This provides self-service while preserving security, governance, standardization, cost control, auditability, and database engineering best practices.