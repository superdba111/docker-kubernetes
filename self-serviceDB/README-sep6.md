# PostgreSQL Self-Service Database Platform

## Overview

This project provides a reusable, secure, and governed self-service PostgreSQL provisioning platform on AWS.

The goal is to allow application teams to request PostgreSQL databases through a simple service interface without requiring developers to understand or directly configure low-level AWS RDS infrastructure.

The platform separates infrastructure implementation from the developer experience.

```text
Developer
   |
   v
Self-Service Portal
React / TypeScript
   |
   v
FastAPI
   |
   v
Provisioning Workflow
   |
   v
Terraform
   |
   v
Reusable PostgreSQL Module
   |
   v
Amazon RDS PostgreSQL
```

The Terraform module is built first and acts as the core infrastructure product. The API and portal are added later as thin self-service layers.

---

# Architecture Principles

The platform follows several design principles:

* Infrastructure as Code using Terraform
* Reusable and versioned Terraform modules
* Private databases by default
* Encryption by default
* Least-privilege access
* Environment-based guardrails
* Automated backup and recovery
* Small Terraform state blast radius
* Separation between developer inputs and AWS implementation details
* Git-based version control and auditability
* Asynchronous database provisioning
* Self-service without allowing unrestricted infrastructure configuration

---

# High-Level Architecture

```text
                         Developers
                             |
                             v
                  +----------------------+
                  | Self-Service Portal  |
                  | React / TypeScript   |
                  +----------+-----------+
                             |
                             | HTTPS / REST
                             v
                  +----------------------+
                  |       FastAPI        |
                  |    Python Backend    |
                  +----------+-----------+
                             |
             +---------------+----------------+
             |                                |
             v                                v
        DynamoDB                             SQS
   Request / Status DB                Provisioning Queue
                                              |
                                              v
                                   +---------------------+
                                   | Terraform Worker    |
                                   | CodeBuild / ECS     |
                                   +----------+----------+
                                              |
                                              v
                                   Terraform Service Module
                                              |
                                              v
                                   Reusable RDS Module
                                              |
                                              v
                                  Amazon RDS PostgreSQL
                                              |
                    +-------------------------+--------------------+
                    |                         |                    |
                    v                         v                    v
             Secrets Manager           CloudWatch /          AWS Backup /
                                        Database Insights     RDS Backups
```

Terraform state is stored separately in Amazon S3.

```text
Terraform
    |
    v
S3 Remote Backend
    |
    +-- Encryption
    +-- Versioning
    +-- Native state locking
    +-- Block Public Access
```

---

# Implementation Order

The platform should not begin with the web portal.

The recommended implementation sequence is:

```text
1. Define Service Contract
           |
           v
2. Build Terraform Module
           |
           v
3. Build PostgreSQL Product Wrapper
           |
           v
4. Add State + CI/CD + Policy
           |
           v
5. Build FastAPI Service
           |
           v
6. Build React Portal
```

## Phase 1 - Define the Service Contract

First define what developers are allowed to request.

Example:

```yaml
application: orders-api
environment: prod
database_name: orders
size: medium
owner: payments-team
cost_center: CC1023
```

The developer should not directly configure parameters such as:

```text
db.m7g.large
allocated_storage
Multi-AZ
KMS key
backup retention
security groups
public accessibility
subnet groups
```

Those values are controlled by the platform.

---

# Developer Experience

A developer requests a database using a small number of business-level inputs.

Example:

```text
Application:     orders-api
Environment:     Production
Database Name:   orders
Size:            Medium
Owner:           Payments Team
Cost Center:     CC1023
```

The platform automatically converts those values into approved infrastructure.

Example:

```text
Medium + Production
        |
        v
db.m7g.large
200 GB storage
Multi-AZ enabled
30-day backup retention
Deletion protection enabled
KMS encryption enabled
Private networking
CloudWatch monitoring enabled
```

---

# Terraform Module Design

The platform uses two Terraform module layers.

```text
postgresql-service
       |
       v
rds-postgresql
       |
       v
AWS Resources
```

## Engineering Module

The lower-level module provides reusable RDS PostgreSQL functionality.

```text
modules/rds-postgresql
```

It manages resources such as:

* `aws_db_instance`
* `aws_db_subnet_group`
* `aws_security_group`
* security group ingress rules
* encryption configuration
* backup configuration
* logging
* IAM database authentication
* Secrets Manager integration

This module may expose more technical configuration because it is intended for the platform engineering team.

---

# PostgreSQL Service Module

The upper-level module represents the actual database product offered to application teams.

```text
modules/postgresql-service
```

This module exposes only approved developer-facing inputs.

For example:

```hcl
module "postgresql" {
  source = "./modules/postgresql-service"

  application   = "orders"
  database_name = "orders"
  environment   = "prod"

  size = "medium"

  owner       = "payments-team"
  cost_center = "CC1023"
}
```

The module converts T-shirt sizes into infrastructure configurations.

Example:

```hcl
locals {
  sizes = {
    small = {
      instance_class = "db.t4g.medium"
      storage         = 50
      max_storage     = 200
    }

    medium = {
      instance_class = "db.m7g.large"
      storage         = 200
      max_storage     = 500
    }

    large = {
      instance_class = "db.r7g.xlarge"
      storage         = 500
      max_storage     = 2000
    }
  }
}
```

---

# Environment Guardrails

Production settings should be automatically enforced.

Example:

```hcl
locals {
  is_prod = var.environment == "prod"
}
```

Then:

```hcl
multi_az = local.is_prod

backup_retention_period = local.is_prod ? 30 : 7

deletion_protection = local.is_prod

skip_final_snapshot = !local.is_prod
```

This prevents an application developer from accidentally creating a production database without high availability or sufficient backups.

---

# Security Architecture

Security is built into the module rather than left to individual application teams.

## Networking

All databases should run inside private subnets.

```hcl
publicly_accessible = false
```

Applications access PostgreSQL through approved security groups.

Do not allow broad ingress such as:

```text
0.0.0.0/0 -> TCP 5432
```

Prefer security-group-to-security-group rules.

```text
Application Security Group
          |
          | TCP 5432
          v
Database Security Group
```

---

# Encryption

RDS storage should always be encrypted.

```hcl
storage_encrypted = true
kms_key_id        = var.kms_key_arn
```

Encryption should also be used for:

* RDS storage
* snapshots
* Secrets Manager
* Terraform state
* application traffic

---

# Credentials and Secrets

Database passwords should not be passed into Terraform as normal variables.

Avoid:

```hcl
variable "database_password" {
  type = string
}
```

Instead, allow Amazon RDS to manage the master password through AWS Secrets Manager.

Example:

```hcl
manage_master_user_password = true
```

Terraform should expose only the secret ARN.

```hcl
output "master_user_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}
```

Applications should not normally use the master database account.

Create separate identities such as:

```text
orders_app
reporting_ro
migration_user
dba_admin
```

Access should follow least privilege.

---

# IAM Database Authentication

Where appropriate, IAM database authentication can be enabled.

```hcl
iam_database_authentication_enabled = true
```

This allows supported applications and administrators to authenticate using AWS IAM rather than long-lived passwords.

---

# Backup and Disaster Recovery

Production databases should include:

* automated backups
* point-in-time recovery
* final snapshots
* deletion protection
* Multi-AZ deployment
* backup retention policies
* restore testing

Example production configuration:

```text
Multi-AZ                Enabled
Backup retention        30 days
Deletion protection     Enabled
Final snapshot          Required
Storage encryption      Enabled
```

Development environments can use less expensive configurations.

Example:

```text
Multi-AZ                Optional / Disabled
Backup retention        7 days
Deletion protection     Disabled
Final snapshot          Optional
```

---

# Observability

The platform should automatically enable database monitoring.

Recommended services include:

* Amazon CloudWatch
* CloudWatch Database Insights
* PostgreSQL logs
* CloudWatch alarms
* EventBridge notifications
* application metrics

Important metrics include:

```text
CPUUtilization
DatabaseConnections
FreeStorageSpace
FreeableMemory
ReadLatency
WriteLatency
ReadIOPS
WriteIOPS
Deadlocks
ReplicaLag
```

Alerts can be generated for:

```text
High CPU
Low storage
Excessive connections
High latency
Database failover
Backup failure
Replication lag
```

---

# Terraform Repository Structure

Recommended repository structure:

```text
database-platform/
│
├── modules/
│   │
│   ├── rds-postgresql/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── README.md
│   │
│   └── postgresql-service/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
│
├── environments/
│   ├── dev/
│   ├── stage/
│   └── prod/
│
├── tests/
│
├── portal/
│
├── api/
│
└── .github/
    └── workflows/
        └── terraform.yml
```

---

# Terraform Module Versioning

Terraform modules should be version controlled using Git.

Example releases:

```text
v1.0.0
v1.1.0
v1.2.0
v2.0.0
```

Consumers should pin module versions.

Example:

```hcl
module "postgresql" {
  source = "git::https://github.com/company/terraform-aws-postgresql.git?ref=v1.4.0"
}
```

Avoid consuming directly from:

```text
main
master
latest
```

because module changes could unexpectedly affect production databases.

---

# Terraform State

Terraform state is stored in Amazon S3.

Example:

```hcl
terraform {
  backend "s3" {
    bucket       = "company-terraform-state"
    key          = "databases/orders-prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

The S3 bucket should use:

* versioning
* encryption
* block public access
* restricted IAM policies
* CloudTrail auditing

---

# State Isolation

Avoid managing all databases in a single Terraform state file.

Bad:

```text
databases.tfstate

orders
billing
inventory
customers
payments
analytics
```

Preferred:

```text
orders-prod.tfstate
billing-prod.tfstate
inventory-dev.tfstate
```

or separate Terraform workspaces/runs.

Example:

```text
orders-prod-db

billing-prod-db

inventory-dev-db
```

This reduces the Terraform blast radius.

A failure or configuration issue with one database should not affect every database managed by the platform.

---

# CI/CD

Changes to the Terraform module should go through a controlled CI/CD workflow.

```text
Developer
    |
    v
Pull Request
    |
    +--> terraform fmt
    |
    +--> terraform validate
    |
    +--> tflint
    |
    +--> security scanning
    |
    +--> terraform test
    |
    +--> terraform plan
    |
    +--> policy checks
    |
    v
Peer Review
    |
    v
Merge
    |
    v
Release Tag
```

Possible tools include:

* GitHub Actions
* GitLab CI
* AWS CodeBuild
* TFLint
* Checkov
* tfsec
* OPA
* Terraform test

---

# Policy as Code

The platform should prevent unsafe database configurations.

Example policies:

```text
DENY:
publicly_accessible = true
```

```text
DENY:
storage_encrypted = false
```

```text
DENY:
0.0.0.0/0 -> PostgreSQL 5432
```

For production:

```text
DENY:
multi_az = false
```

```text
DENY:
backup_retention_period < 14
```

```text
DENY:
deletion_protection = false
```

Required metadata can also be enforced:

```text
Owner
Environment
Application
CostCenter
ManagedBy
```

Policy enforcement can be implemented using:

* Terraform validation
* OPA
* Checkov
* AWS Service Control Policies
* AWS Config
* CI/CD pipeline rules

---

# FastAPI Service

After the Terraform product is stable, a lightweight API can provide a consistent service interface.

Example request:

```http
POST /api/databases
```

Payload:

```json
{
  "application": "orders-api",
  "environment": "prod",
  "database_name": "orders",
  "size": "medium",
  "owner": "payments-team",
  "cost_center": "CC1023"
}
```

Example response:

```json
{
  "request_id": "DB-10243",
  "status": "PENDING"
}
```

The API should not wait for Terraform to finish.

Terraform provisioning may take several minutes, so provisioning should be asynchronous.

---

# Asynchronous Provisioning

Avoid:

```text
HTTP Request
    |
FastAPI
    |
terraform apply
    |
User waits for several minutes
```

Preferred:

```text
HTTP Request
    |
FastAPI
    |
Create Request
    |
SQS
    |
Terraform Worker
    |
terraform apply
```

FastAPI immediately returns a request ID.

Example:

```json
{
  "request_id": "DB-10243",
  "status": "PENDING"
}
```

The frontend can query:

```http
GET /api/databases/DB-10243
```

Possible states:

```text
PENDING
APPROVED
PROVISIONING
READY
FAILED
DELETING
DELETED
```

---

# Request Tracking

Amazon DynamoDB can be used to track self-service requests.

Example item:

```text
PK              REQUEST#DB-10243

application     orders-api
environment     prod
database_name   orders
size            medium
owner           payments-team
status          PROVISIONING
created_at      2026-09-06T12:00:00Z
```

DynamoDB works well because the primary access pattern is typically:

```text
request_id -> request status
```

---

# Terraform Worker

Terraform should run outside the FastAPI process.

Possible execution environments:

* AWS CodeBuild
* ECS Fargate
* GitHub Actions
* GitLab Runner

Example:

```text
SQS
 |
 v
Terraform Worker
 |
 +-- git checkout
 |
 +-- terraform init
 |
 +-- terraform plan
 |
 +-- policy validation
 |
 +-- terraform apply
 |
 v
AWS RDS
```

---

# Self-Service Portal

The web portal should be built after the Terraform service and API contract are stable.

Recommended technologies:

```text
Frontend:
React + TypeScript

Backend:
FastAPI + Python
```

Example UI:

```text
+--------------------------------------+
|      PostgreSQL Self-Service         |
+--------------------------------------+
|                                      |
| Application:   [ orders-api      ]   |
|                                      |
| Environment:   [ Production      ]   |
|                                      |
| Database:      [ orders          ]   |
|                                      |
| Size:                                |
|                                      |
|      ○ Small                         |
|      ● Medium                        |
|      ○ Large                         |
|                                      |
| Owner:         [ Payments Team   ]   |
|                                      |
| Cost Center:   [ CC1023          ]   |
|                                      |
|        [ Create PostgreSQL ]          |
+--------------------------------------+
```

The portal should not expose low-level AWS settings.

---

# Portal Authentication

Authentication should integrate with enterprise identity providers.

Examples:

* Microsoft Entra ID
* Okta
* AWS Cognito

Do not implement a separate local username/password system unless required.

Example:

```text
Employee
   |
Company SSO
   |
Portal
   |
JWT
   |
FastAPI
```

---

# Authorization

Role-based access control can distinguish between different user types.

Example:

```text
Developer
---------
Create DEV database
Create TEST database
View owned databases
Request PROD database
```

```text
DBA / Platform Engineer
-----------------------
Approve production changes
Resize databases
Perform restore
Manage engine upgrades
Emergency access
```

```text
Platform Administrator
-----------------------
Manage Terraform modules
Manage policies
Manage networking
Manage KMS
Manage platform configuration
```

---

# Development vs Production Workflow

Development databases can use fully automated provisioning.

```text
Developer
    |
Portal
    |
FastAPI
    |
SQS
    |
Terraform
    |
DEV PostgreSQL
```

Production provisioning should include additional controls.

```text
Developer
    |
Portal
    |
Request
    |
Policy Validation
    |
Approval
    |
Terraform Plan
    |
Terraform Apply
    |
PROD PostgreSQL
```

---

# Optional GitOps Workflow

For environments requiring stronger auditability, the portal can create a Git pull request rather than directly running Terraform.

```text
Portal
   |
FastAPI
   |
Generate Terraform configuration
   |
Create Git Pull Request
   |
Terraform Plan
   |
Peer / DBA Approval
   |
Merge
   |
Terraform Apply
```

Example generated configuration:

```hcl
module "orders_prod" {
  source = "../../modules/postgresql-service"

  application   = "orders"
  database_name = "orders"
  environment   = "prod"

  size = "medium"

  owner       = "payments-team"
  cost_center = "CC1023"
}
```

This provides:

* peer review
* approval history
* Git audit trail
* Terraform plan review
* rollback visibility
* compliance evidence

---

# RDS Proxy

For workloads with high connection concurrency, RDS Proxy can optionally be added.

Example:

```text
Application
     |
     v
RDS Proxy
     |
     v
RDS PostgreSQL
```

This is especially useful for:

* Lambda
* serverless applications
* large microservice environments
* applications with frequent connection creation

RDS Proxy should be implemented as an optional module rather than automatically enabled for every database.

---

# Example Platform Flow

A typical provisioning workflow looks like this:

```text
1. Developer logs into portal.

2. Developer requests:
      Application = Orders
      Environment = Production
      Size = Medium

3. FastAPI validates request.

4. Platform verifies authorization.

5. Request stored in DynamoDB.

6. Production request goes through approval.

7. Provisioning request placed on SQS.

8. Terraform worker receives request.

9. Worker executes:
      terraform init
      terraform plan
      policy checks
      terraform apply

10. Terraform creates:
      RDS PostgreSQL
      subnet group
      security group
      encryption
      backup configuration
      Secrets Manager secret
      monitoring

11. Request status becomes READY.

12. Portal displays:
      database endpoint
      port
      database name
      secret reference

13. Application accesses database using
    approved authentication.
```

---

# Technology Stack

| Component              | Technology                             |
| ---------------------- | -------------------------------------- |
| Cloud                  | AWS                                    |
| Database               | Amazon RDS PostgreSQL                  |
| Infrastructure as Code | Terraform                              |
| Terraform state        | Amazon S3                              |
| Module source          | GitHub / GitLab                        |
| Frontend               | React / TypeScript                     |
| Backend                | FastAPI / Python                       |
| Provisioning queue     | Amazon SQS                             |
| Request metadata       | DynamoDB                               |
| Terraform execution    | CodeBuild / ECS / GitHub Actions       |
| Secrets                | AWS Secrets Manager                    |
| Encryption             | AWS KMS                                |
| Monitoring             | CloudWatch / Database Insights         |
| Authentication         | Entra ID / Okta / Cognito              |
| CI/CD                  | GitHub Actions / GitLab CI / CodeBuild |

---

# Future Enhancements

Possible future capabilities include:

* Aurora PostgreSQL support
* PostgreSQL read replicas
* RDS Proxy
* automated engine upgrades
* automated restore requests
* cloning databases from snapshots
* automated non-production refreshes
* cost estimation
* automated expiration of temporary databases
* database user provisioning
* schema deployment integration
* Flyway / Liquibase integration
* database performance dashboards
* ServiceNow integration
* Slack / Teams notifications
* approval workflows
* automatic resizing recommendations
* AI-assisted troubleshooting
* RAG-based DBA knowledge assistant

---

# Summary

The PostgreSQL self-service platform is designed around a simple principle:

> Developers request a database service rather than directly configuring database infrastructure.

Terraform provides the reusable provisioning engine.

The PostgreSQL service module provides governance and standardization.

FastAPI provides the service API.

React provides the developer experience.

AWS provides the runtime infrastructure.

The recommended development sequence is:

```text
Service Contract
      ↓
Terraform Module
      ↓
Governed Product Module
      ↓
CI/CD + State + Policy
      ↓
FastAPI
      ↓
React Portal
```

This architecture provides a secure and scalable internal Database-as-a-Service platform while maintaining strong infrastructure governance, automation, auditability, and developer self-service.
