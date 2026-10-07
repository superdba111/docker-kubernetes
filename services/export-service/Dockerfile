# Hardened, FIPS-enabled base image maintained by Platform (in-boundary ECR).
#
# No apt installs: the app talks to Postgres through psycopg[binary], which
# bundles its own libpq (16.x; works with the RDS 17 cluster). The PGDG libpq 17
# / postgresql-client-17 packages were never used by the app, and pulled from a
# public repo outside the boundary.
FROM 111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/python:3.12-fips AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM 111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/python:3.12-fips
COPY --from=builder /install /usr/local
COPY app/ /app
WORKDIR /app
ENV PYTHONUNBUFFERED=1
USER 10001
EXPOSE 8080
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8080", "main:app"]
