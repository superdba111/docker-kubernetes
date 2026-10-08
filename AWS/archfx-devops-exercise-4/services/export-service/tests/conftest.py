import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

os.environ.setdefault("AWS_REGION", "us-gov-west-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("EXPORT_BUCKET", "test-exports")
os.environ.setdefault("EXPORT_QUEUE_URL", "https://sqs.us-gov-west-1.amazonaws.com/000000000000/test")
os.environ.setdefault("JWT_ISSUER", "https://portal.test")
os.environ.setdefault("JWT_AUDIENCE", "export-service")
os.environ.setdefault("JWT_JWKS_URL", "https://portal.test/.well-known/jwks.json")
os.environ.setdefault("EXPORT_ENABLED_TENANTS", "tenant-a, tenant-b")
os.environ.pop("SENTRY_DSN", None)
