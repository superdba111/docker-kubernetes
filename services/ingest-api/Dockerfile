# Hardened, FIPS-enabled base image maintained by Platform (in-boundary ECR).
FROM 111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/python:3.12-fips AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --require-hashes --prefix=/install -r requirements.txt

FROM 111122223333.dkr.ecr.us-gov-west-1.amazonaws.com/hardened/python:3.12-fips
COPY --from=builder /install /usr/local
COPY app/ /app
WORKDIR /app
USER 10001
EXPOSE 8080
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8080", "main:app"]
