# AI usage

I used **Claude Code** (Claude Opus 5.5) in this repo. I reviewed the PR myself
first, then used the tool to check my notes against the diff, draft the
`review/` documents (which I edited), and write the fix commits. I reviewed its
output in several passes and sent corrections each time.

I subsequently used **Codex** to independently review the branch, revise the
boundary/fallback/POA&M documentation, and prepare explanatory notes. On my
request it split the current change into a source-and-test-only PR A, with
deployment proposals preserved as text for PR B. It removed automatic export
publishing and added scope regression tests. This does not assert external
approval, credential rotation, or a completed production deployment.

I verified results myself and didn't rely on the tool's word:
- **Tests:** 33 passed in a fresh Python 3.12 venv, plus 4 against a
  disposable Postgres.
- **Terraform:** `terraform validate` and `fmt` pass.
- **Helm:** `helm lint` and `helm template` pass.
- **FIPS endpoints:** botocore endpoint resolution checked offline.

**One correction:** the tool's CI rewrite, copied from the reference
`ingest-api.yml`, still ran pull-request code on the govhigh self-hosted runner
with `id-token: write`. I rejected it. Only main-branch publishes now get OIDC
or the govhigh runner in the deferred PR B proposal; PR A now has no publish
job. In other places it was right and I was
wrong. For example, I'd flagged the SQS queue URL as a non-FIPS endpoint, and
it showed that the SDK sends requests to the resolved FIPS endpoint instead.

For the PR A split, Codex ran four standard-library scope regression tests,
Terraform formatting and whitespace checks, and confirmed active Terraform
matches `main`. It also checked the deferred Terraform/Helm references against
the previously committed contents. It did not rerun the dependency-based
Python suite, build an image, apply Terraform or deploy anything in this pass.
