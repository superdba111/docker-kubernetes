# Scan triage: export-service

Source: `ci-artifacts/export-service-scan.txt` (trivy, 2026-09-28).

## First: this scan isn't of the code under review

- **Wrong commit:** it scanned `docker.io/foundryeng/export-service:latest`
  built from **`4c1e9a2`**, but the PR head is **`fcbf06d`**. A mutable
  `:latest` on Docker Hub gives no guarantee about which code was scanned.
- **No gate:** the CI step ends in `|| true`, so the scan has never been able
  to block.

The triage below is valid as an indication only. The real gate is a rescan of
the SHA-tagged ECR image built from the fixed branch, with
`--exit-code 1 --ignore-unfixed --severity CRITICAL,HIGH`.

## What applies

- **New-image gate (policy §3):** a new service can't launch with a Critical or
  High finding *that has a fix available*, unless there's an approved exception.
- **SLAs (§3):** Critical and High 30 days, Medium 90 days, Low 180 days.

Moving to the hardened FIPS base image (review F1) is expected to remove or
change most of the OS-package rows. `curl`/`libcurl4` and `gnupg` are in the
image **only** to add the PGDG apt repo at build time. Dispositions below are
for the image as built.

## OS packages (debian 12.7)

| Package(s) | ID | Sev | Disposition | Reason |
|---|---|---|---|---|
| libpq5, postgresql-client-17 | CVE-2026-90011 | CRITICAL | **False positive** | 17.4 is installed, and the advisory says the bug is fixed upstream in 17.3. The scanner is comparing a PGDG 17.x package against Debian's `postgresql-15` fixed version (15.12). Exception RA-2026-014 below |
| openssl, libssl3 | CVE-2026-90021 | HIGH | **Fix now** | Fix available (3.0.16), so the new-image gate applies. RSA-OAEP timing side-channel on the TLS stack. Rebuilding on a patched or hardened base fixes it |
| curl, libcurl4 | CVE-2026-90034 | HIGH | **Fix now** | Fix available, so gated. Better still, remove it: curl is only needed at build time to fetch the PGDG key. Do that in a builder stage, or use the hardened image |
| perl-base | CVE-2026-90045 | HIGH | **Fix within SLA (track as VD)** | No fix upstream, so the new-image gate doesn't apply. The 30-day High SLA still runs. If no fix lands by day 30, raise a VD exception. Reachable only if something runs Perl regexes on attacker input, and the app doesn't use Perl |
| zlib1g | CVE-2026-90058 | CRITICAL | **Not applicable** | Vulnerable code is in contrib/minizip, which Debian doesn't build into `zlib1g`, so the code isn't in the image. Record with that evidence; no exception needed beyond a suppression note |
| gnupg / gpgv | CVE-2026-90061 | MEDIUM | **Fix within SLA** | DoS via crafted key block. Only used at build time; remove from the runtime image |
| libc6 | CVE-2026-90052 | MEDIUM | **Fix within SLA** | No fix yet. Requires attacker-controlled long hostnames to `getaddrinfo`, and the app resolves only configured AWS and RDS hosts. Track |
| libsystemd0, libudev1 | CVE-2026-90063 | MEDIUM / LOW | **Fix within SLA** | Local DoS in journal parsing. No systemd/journald runs in the container. Track; likely goes away with the hardened base |
| util-linux | CVE-2026-90065 | MEDIUM | **Fix within SLA** | `wall(1)` isn't used in the container, and no TTYs are attached |
| tar | CVE-2026-90067 | MEDIUM | **Fix within SLA** | App doesn't extract archives at runtime |
| coreutils | CVE-2026-90070 | LOW | **Fix within SLA** | `chroot --userspec` isn't used. Debian says `will_not_fix`; revisit with the hardened base |
| ncurses-base, login, apt, libgcrypt20 | CVE-2026-90072/74/76/78 | LOW | **Fix within SLA** | Not reachable in a non-interactive service container (no terminfo parsing, no `su`, no apt at runtime, libgcrypt unused by Python or OpenSSL). 180-day SLA; expect removal by the hardened/distroless base |

## Python packages (runtime image)

| Package | ID | Sev | Disposition | Reason |
|---|---|---|---|---|
| pyarrow 15.0.0 | CVE-2026-90101 | CRITICAL | **Fix now** | RCE when reading crafted Parquet/IPC metadata. **This is the worst row in the scan.** The worker uses pyarrow on data that comes from customer edge gateways via `raw-ingest`. Upgrade to ≥15.0.2 (or 16.1.0) |
| gunicorn 21.2.0 | CVE-2026-90112 | HIGH | **Fix now** | Request smuggling, and the service sits behind an ingress proxy, which is the exact setup where smuggling works. → 22.0.0+ (the reference uses 23.0.0) |
| PyJWT 2.8.0 | CVE-2026-90118 | HIGH | **Fix now** (done in `review/maxwell-li`) | Issuer partial-match bypass. It didn't matter while signatures weren't verified at all, but it would have the moment they were. Upgraded to 2.10.1 in my fix, with a test for a partial-match issuer |
| setuptools 69.5.1 | CVE-2026-90121 | HIGH | **Fix now** | Fix available, so gated. Exploitable only via `package_index` downloads (build time), so low runtime exposure, but it's a one-line bump |
| starlette 0.36.3 | CVE-2026-90125 | MEDIUM | **Fix within SLA** | Multipart DoS. The API only takes JSON, but upgrade with FastAPI (reference is at 0.115.x) |
| requests 2.31.0, urllib3 1.26.18 | CVE-2026-90131/33 | MEDIUM | **Fix within SLA** | Proxy-Authorization leak on redirect. No proxy auth is configured. Bump together |
| pip 24.0 | CVE-2026-90137 | MEDIUM | **Fix within SLA** | Build-time tool, Mercurial URLs not used. Bump the base image's pip |
| sentry-sdk 1.44.0 | CVE-2026-90140 | MEDIUM | **Fix within SLA** | Env vars captured in breadcrumbs, which matters because `DB_PASSWORD` is in env. Upgrade to 2.x along with the move to in-boundary Sentry (review A2) |

## Repository filesystem (dev dependencies)

| Package | ID | Sev | Disposition | Reason |
|---|---|---|---|---|
| responses 0.23.1 | CVE-2026-90150 | CRITICAL | **Not applicable** to the image; **fix within SLA** for CI | `requirements-dev.txt` only, not installed in the runtime image. However, CI runs `pip install -r requirements-dev.txt` with deploy secrets in scope (review C1). Bump to 0.25.0 |
| moto 5.0.3 | CVE-2026-90152 | HIGH | **Not applicable** to the image; **fix within SLA** for CI | Same reasoning. → 5.0.9 |

**Before launch:** the two OS fix-now rows (openssl via a rebuild, curl by
removing it) plus pyarrow, gunicorn, PyJWT, and setuptools. That's under an hour of
work. Only one Critical needs paperwork, below.

---

## Exception

| Field | Value |
|---|---|
| Exception ID | RA-2026-014 |
| Type | **FP** (False positive) |
| Finding(s) | CVE-2026-90011 (trivy) on `libpq5` and `postgresql-client-17` 17.4-1.pgdg120+2, in `export-service` image |
| Original severity | CRITICAL |
| Adjusted severity (if RA) | n/a (FP) |
| Environment(s) | govhigh (`111122223333`, us-gov-west-1); govhigh-dr if deployed |
| Requested by | Maxwell Li (Security Review), on behalf of Data Products |
| Expires | 2027-01-04 (90 days), or earlier on base-image change, whichever comes first |

### Description
The trivy scan reports CVE-2026-90011, a SQL injection via invalid multibyte
encodings in libpq's quoting functions, as CRITICAL on two packages in the
export-service image: `libpq5` and `postgresql-client-17`. Both are version
17.4 from the PostgreSQL (PGDG) apt repository. The scanner shows "Fixed
Version: 15.12-0+deb12u1".

### Justification / Evidence
The installed version is not affected:
1. **Upstream fix:** per the scan's own advisory, PostgreSQL libpq versions
   `< 17.3` are affected, and the fix is in **17.3** (also 16.7 and 15.11).
2. **Installed version:** 17.4 (`17.4-1.pgdg120+2`), which is after the 17.3 fix.
3. **Why the scanner flagged it:** it matched the package against the **Debian
   `postgresql-15`** tracker entry (`fixed in 15.12-0+deb12u1`). The PGDG
   package is a different source package and version series, and Debian's
   version comparison incorrectly treats 17.4-1.pgdg as needing the 15.12 fix.
4. **Code usage:** the app uses psycopg 3 with server-side parameter binding
   (`db.py`). It doesn't call libpq's client-side quoting functions
   (`PQescapeLiteral` etc.) directly, so even an affected libpq would be hard to
   reach. This is supporting context only; the FP stands on points 1–3.

Evidence to attach before approval:
- `dpkg -s libpq5 postgresql-client-17` from the **ECR image built from the
  approved commit**, showing 17.4. This scan was of a Docker Hub image from a
  different commit and can't be the evidence.
- The PGDG 17.3 or later changelog entry referencing the fix.

### Compensating controls
Not needed for an FP, but in place or required anyway:
- **Least-privilege DB credentials:** the app connects as `export_svc` with
  `sslmode=require`. Credentials come from Secrets Manager (review C2).
- **Parameterized queries only:** dynamic SQL is rejected in code review.
- **Scope of suppression:** a trivy `.trivyignore` entry scoped to **this CVE
  and these two packages** only, with this exception ID in the comment, so a
  different libpq version or package is still reported.

### Remediation plan
- **Closes when:** the scanner reports correctly, or the image moves to a
  hardened FIPS base with libpq 17 provided by Platform. At that point the
  finding should disappear, and the suppression is removed.
- **Owner:** Platform (hardened image), Data Products (remove suppression).
- **Revisit by:** 2027-01-04, or on any change to the `libpq5` version.

### Approvals
- Security Reviewer:
- Platform Engineering Manager:
