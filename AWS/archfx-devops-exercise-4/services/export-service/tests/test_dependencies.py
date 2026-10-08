"""Properties of the installed dependencies that the scan triage relies on."""
import psycopg


def test_libpq_is_past_cve_2026_90011_fix():
    # psycopg[binary] bundles its own libpq, so removing the Debian libpq5
    # package doesn't remove the finding; the bundled copy must be >= 17.3.
    # Runs in CI against the hash-locked Linux wheel the image installs.
    assert psycopg.pq.version() >= 170003, psycopg.pq.version()
