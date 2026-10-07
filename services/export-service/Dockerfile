FROM python:3.12-slim AS builder
RUN apt-get update && apt-get install -y build-essential libpq-dev
WORKDIR /build
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

FROM python:3.12-slim
# libpq 17 from the PostgreSQL (PGDG) apt repo — Debian 12 only ships libpq 15,
# which lacks the protocol features our RDS 17 cluster needs.
RUN apt-get update && apt-get install -y curl gnupg ca-certificates \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update && apt-get install -y libpq5 postgresql-client-17
COPY --from=builder /install /usr/local
COPY app/ /app
WORKDIR /app
ENV PYTHONUNBUFFERED=1
USER 10001
EXPOSE 8080
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8080", "main:app"]
