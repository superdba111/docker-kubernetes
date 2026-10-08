# Security Review Policy

Owner: Security Review (Platform)  ·  Last reviewed: 2026-08-14

## 1. When review is required

A security reviewer approval is required on any PR that touches:

- `terraform/`, `helm/`, `.github/workflows/`, `CODEOWNERS`, or `docs/`
- any Dockerfile
- authentication, authorization, or data export/download code paths

`CODEOWNERS` enforces this. PR authors may not approve their own changes, and
no one may change `CODEOWNERS` to remove a required reviewer without Security
Review approval (separation of duties).

## 2. Review outcomes

Each finding is labeled with one of:

| Label        | Meaning                                                              |
|--------------|----------------------------------------------------------------------|
| **Blocker**  | Must be fixed before merge                                            |
| **Pre-prod** | May merge behind a disabled flag, but must be fixed before prod rollout |
| **Follow-up**| Tracked ticket with owner + due date; does not block                  |
| **Nit**      | Optional                                                              |
| **No action**| Looked at, and it's fine. Say why                                     |

## 3. Vulnerability remediation SLAs (govhigh)

Measured from first detection:

| Severity | Remediate within |
|----------|------------------|
| Critical | 30 days          |
| High     | 30 days          |
| Medium   | 90 days          |
| Low      | 180 days         |

**New-image gate:** a *new* service must not launch in govhigh with a Critical
or High finding that has a fix available, unless an approved exception exists.

## 4. Exceptions and risk acceptance

Every exception uses `docs/templates/risk-acceptance.md` and falls into one of
these types:

- **False positive (FP):** the finding does not apply. Needs evidence.
- **Operational requirement (OR):** we can't remediate without breaking a
  required function. Needs compensating controls.
- **Vendor dependency (VD):** no fix available upstream. Needs a check-back date.
- **Risk adjustment (RA):** severity lowered because of context. Needs justification.

Approval requires **both** a Security Reviewer and the Platform Engineering
Manager. Exceptions expire after at most 90 days and are listed on the POA&M.

## 5. Significant changes

Changes defined as significant in `authorization-boundary.md` §6 cannot be
approved by Security Review alone. They need a boundary change record and
advance notice to our FedRAMP partner. Review can mark them **Blocker (boundary)**.
