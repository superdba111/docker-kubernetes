# Scan triage: export-service

Source: `ci-artifacts/export-service-scan.txt` (trivy). **First detected
2026-09-28**, so the policy §3 deadlines are:
- **Critical/High:** 2026-10-28
- **Medium:** 2026-12-27
- **Low:** 2027-03-27

**The scan isn't of the code under review.** It scanned
`docker.io/foundryeng/export-service:latest` built from `4c1e9a2`, not PR head
`fcbf06d`, and the CI step ended in `|| true`, so it could never block. Part 1
triages the artifact as delivered. Part 2 is what this branch changes, and
what is still unverified.

## Part 1: the scanned artifact (`python:3.12-slim`, debian 12.7)

### OS packages

| Package(s) | ID | Sev | Disposition | Reason |
|---|---|---|---|---|
| libpq5, postgresql-client-17 | CVE-2026-90011 | CRIT | **False positive** (these two packages) | 17.4 is installed; the advisory's fix is 17.3. Trivy matched the PGDG package against Debian's `postgresql-15` entry. RA-2026-014. **The CVE is not an FP for the image:** see the next row |
| *(not reported)* psycopg-binary 3.1.18's bundled libpq | CVE-2026-90011 | CRIT | **Fix now** | The wheel bundles **libpq 16.0** (below the 16.7 fix; `PQlibVersion` read from the manylinux wheel). Trivy scans the Python package's metadata, not the libraries bundled inside the wheel, so it missed this copy |
| openssl, libssl3 | CVE-2026-90021 | HIGH | **Fix now** | Fix available, so the new-image gate applies |
| curl, libcurl4 | CVE-2026-90034 | HIGH | **Fix now** | Fix available. Only used at build time to fetch the PGDG key; remove it |
| perl-base | CVE-2026-90045 | HIGH | **Fix within SLA**, VD exception if still unfixed on 2026-10-28 | No upstream fix, so not gated. The app runs no Perl |
| zlib1g | CVE-2026-90058 | CRIT | **Not applicable** | The vulnerable minizip code isn't built into `zlib1g` (advisory; Debian `will_not_fix`) |
| gnupg / gpgv | CVE-2026-90061 | MED | **Fix within SLA** | Build-time only; remove it |
| libc6 | CVE-2026-90052 | MED | **Fix within SLA** | No fix yet. The app resolves only configured AWS and RDS hosts |
| libsystemd0, libudev1 | CVE-2026-90063 | MED/LOW | **Fix within SLA** | No journald in the container |
| util-linux | CVE-2026-90065 | MED | **Fix within SLA** | `wall` unused; no TTY |
| tar | CVE-2026-90067 | MED | **Fix within SLA** | No archive extraction at runtime |
| coreutils | CVE-2026-90070 | LOW | **Fix within SLA** | `chroot --userspec` unused; Debian `will_not_fix` |
| ncurses-base, login, apt, libgcrypt20 | CVE-2026-90072/74/76/78 | LOW | **Fix within SLA** | Not reachable in a non-interactive container |

### Python packages

| Package | ID | Sev | Disposition | Reason |
|---|---|---|---|---|
| pyarrow 15.0.0 | CVE-2026-90101 | CRIT | **Fix now** | RCE on crafted Parquet/IPC metadata. The worker parses customer data. The worst row |
| gunicorn 21.2.0 | CVE-2026-90112 | HIGH | **Fix now** | Request smuggling. The service sits behind an ingress proxy |
| PyJWT 2.8.0 | CVE-2026-90118 | HIGH | **Fix now** | Issuer partial-match bypass. It matters once signatures are verified (review B1) |
| setuptools 69.5.1 | CVE-2026-90121 | HIGH | **Fix now** | Fix available, so gated. Low runtime exposure |
| starlette 0.36.3 | CVE-2026-90125 | MED | **Fix within SLA** | Multipart DoS. The API takes JSON only |
| requests 2.31.0, urllib3 1.26.18 | CVE-2026-90131/33 | MED | **Fix within SLA** | No proxy auth configured |
| pip 24.0 | CVE-2026-90137 | MED | **Fix within SLA** | Build-time tool |
| sentry-sdk 1.44.0 | CVE-2026-90140 | MED | **Fix within SLA** | Env vars in breadcrumbs, and `DB_PASSWORD` was in env |

### Repository (dev dependencies)

| Package | ID | Sev | Disposition | Reason |
|---|---|---|---|---|
| responses 0.23.1 | CVE-2026-90150 | CRIT | **N/A to image; fix within SLA** for CI | Not in the runtime image, but CI installed it with deploy secrets in scope (review C1) |
| moto 5.0.3 | CVE-2026-90152 | HIGH | **N/A to image; fix within SLA** for CI | Same |

## Part 2: status on `review/maxwell-li`

No image has been built from this branch, so nothing below is confirmed in an
image. **Package removal is expected, not proven.** Confirming it needs an
image inventory (SBOM, e.g. `trivy image --format cyclonedx`) of the SHA-tagged
ECR image, plus the gating rescan. Those are Platform's first build (decision,
enable gate 2).

| Item | Change in this branch | How it's verified |
|---|---|---|
| Bundled libpq (CVE-2026-90011) | psycopg[binary] 3.1.18 → 3.2.3 → **3.2.5** | The hash-locked manylinux wheel bundles **libpq 17.4** (`PQlibVersion` = 170004). 3.2.3 bundled 17.0, also affected. `tests/test_dependencies.py` asserts ≥ 17.3 in CI, because trivy can't see bundled copies |
| PGDG libpq5, postgresql-client-17, curl, gnupg | Dockerfile has no apt installs; hardened FIPS base | Dockerfile only. **SBOM needed** |
| openssl, perl, libc, other OS rows | Depend on the hardened base's contents | **Rescan needed** |
| pyarrow, gunicorn, PyJWT, requests, sentry-sdk, responses, moto | 15.0.2, 23.0.0, 2.10.1, 2.32.3, 2.19.2, 0.25.0, 5.0.9 | Hash lock; tests pass |
| setuptools, pip, starlette | Not changed: setuptools/pip come from the base; starlette moves with FastAPI | **Open.** Deadlines above |
| Scan gate | `trivy --exit-code 1 --ignore-unfixed --severity CRITICAL,HIGH` before push | Workflow only. First run on Platform's build |

**Not covered here:** `ingest-api` pins psycopg[binary] 3.2.3, which bundles
libpq 17.0. Same CVE, same fix. Tracked as review follow-up FU-6.

---

## Exception

| Field | Value |
|---|---|
| Exception ID | RA-2026-014 |
| Type | **FP** (False positive) |
| Finding(s) | CVE-2026-90011 (trivy) on the Debian packages `libpq5` and `postgresql-client-17` 17.4-1.pgdg120+2 in the scanned `export-service` image. **Not** the libpq bundled in psycopg-binary, which is affected and is fixed separately (Part 2) |
| Original severity | CRITICAL |
| Adjusted severity (if RA) | n/a (FP) |
| Environment(s) | govhigh (`111122223333`, us-gov-west-1) |
| Requested by | Maxwell Li (Security Review), on behalf of Data Products |
| Expires | 2027-01-04 (90 days), or earlier when an image without these packages passes the scan gate |

### Description
Trivy reports CVE-2026-90011, a SQL injection through invalid multibyte
encodings in libpq's quoting functions, as CRITICAL on two PGDG packages at
17.4. It lists "Fixed Version: 15.12-0+deb12u1".

### Justification / Evidence
1. **Upstream fix:** per the scan's advisory, libpq `< 17.3` is affected; the
   fix is in 17.3.
2. **Installed version:** 17.4-1.pgdg120+2, which is after the fix.
3. **Why trivy flagged it:** it compared the PGDG package with Debian's
   `postgresql-15` tracker entry. That's a different source package and
   version series.

**Scope:** this exception doesn't cover the image as a whole. The same image
also carries psycopg-binary 3.1.18's bundled libpq 16.0, which **is** affected
(Part 1). Approving this FP must not be read as "CVE-2026-90011 is closed".

**Evidence to attach before approval:** `dpkg -s libpq5 postgresql-client-17`
from the image actually under exception, and the PGDG 17.3+ changelog entry.

### Compensating controls
Not required for an FP. Suppression is limited in scope: a `.trivyignore` entry
for **this CVE on these two packages only**, citing this ID, so any other libpq
copy or version is still reported.

### Remediation plan
- **Data Products:** the branch removes both packages, because the app uses
  psycopg's own libpq. The exception **closes** when the SBOM of the first
  approved ECR image shows neither package and the gating scan passes.
  Expected by 2026-10-16.
- **If `psql` is needed again** (e.g. for `migrate`): install it from an
  in-boundary mirror and re-raise this exception with fresh evidence.

### Approvals
Policy §4: both are required.
- Security Reviewer:
- Platform Engineering Manager:
