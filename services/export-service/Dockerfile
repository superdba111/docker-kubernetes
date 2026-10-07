# Hardened, FIPS-enabled base image maintained by Platform (in-boundary ECR).
#
# No apt installs: the app talks to Postgres through psycopg[binary], which
# bundles its own libpq (16.x; works with the RDS 17 cluster). The PGDG libpq 17
# / postgresql-client-17 packages were never used by the app, and pulled from a
# public repo outside the boundary.
FROM 111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/python:3.12-fips AS builder
WORKDIR /build
# Every package is pinned and hash-verified (requirements.txt is generated from
# requirements.in), and comes only from the approved package mirror.
#   - PIP_INDEX_URL is mandatory: the build fails rather than fall back to
#     public PyPI. TODO(Platform): name the approved in-boundary mirror.
#   - It must not carry credentials (build args end up in image history). If
#     the mirror needs auth, pass a netrc as the BuildKit secret "pip_netrc";
#     it is mounted only for this step and never stored in a layer.
#   - PIP_CONFIG_FILE=/dev/null ignores any pip config in the base image, so
#     nothing can add an extra index.
ARG PIP_INDEX_URL
COPY requirements.txt .
RUN --mount=type=secret,id=pip_netrc,target=/root/.netrc,required=false \
    set -eu; \
    case "${PIP_INDEX_URL:-}" in \
      "")  echo "PIP_INDEX_URL (approved package mirror) is required" >&2; exit 1 ;; \
      *@*) echo "PIP_INDEX_URL must not contain credentials; use the pip_netrc secret" >&2; exit 1 ;; \
    esac; \
    PIP_CONFIG_FILE=/dev/null PIP_EXTRA_INDEX_URL= \
      pip install --no-cache-dir --require-hashes --only-binary=:all: \
        --index-url "$PIP_INDEX_URL" \
        --prefix=/install -r requirements.txt

FROM 111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/python:3.12-fips
COPY --from=builder /install /usr/local
COPY app/ /app
WORKDIR /app
ENV PYTHONUNBUFFERED=1
USER 10001
EXPOSE 8080
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8080", "main:app"]
