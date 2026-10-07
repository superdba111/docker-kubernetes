# AI usage

I used **Claude Code** (Claude Opus 5.5) in this repo. I reviewed the PR myself
first, then used the tool to check my notes against the diff, draft the
`review/` documents (which I edited), and write the fix commits. I reviewed its
output in several passes and sent corrections each time.

I verified results myself and didn't rely on the tool's word:
- **Tests:** 33 passed in a fresh Python 3.12 venv, plus 4 against a
  disposable Postgres.
- **Terraform:** `terraform validate` and `fmt` pass.
- **Helm:** `helm lint` and `helm template` pass.
- **FIPS endpoints:** botocore endpoint resolution checked offline.

**One correction:** the tool's CI rewrite, copied from the reference
`ingest-api.yml`, still ran pull-request code on the govhigh self-hosted runner
with `id-token: write`. I rejected it. Only main-branch publishes now get OIDC
or the govhigh runner (review C5). In other places it was right and I was
wrong. For example, I'd flagged the SQS queue URL as a non-FIPS endpoint, and
it showed that the SDK sends requests to the resolved FIPS endpoint instead.
