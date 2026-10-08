"""ingest-api (excerpt). Full source lives in the ingest team's repo."""
from fastapi import FastAPI

app = FastAPI()


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True}
