"""Keep the foundation change separate from production export deployment."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
DEFERRED = ROOT / "review" / "deferred"


class DeliveryScopeTests(unittest.TestCase):
    def test_export_terraform_is_not_active(self):
        self.assertFalse((ROOT / "terraform/envs/govhigh/data_export.tf").exists())
        self.assertTrue((DEFERRED / "data_export.tf.txt").is_file())

    def test_export_chart_is_not_installable(self):
        self.assertFalse((ROOT / "helm/charts/export-service/Chart.yaml").exists())
        self.assertTrue(
            (DEFERRED / "helm/charts/export-service/Chart.yaml.txt").is_file()
        )

    def test_deferred_assets_have_no_deployment_extensions(self):
        for asset in DEFERRED.rglob("*"):
            if asset.is_file():
                self.assertIn(asset.suffix, {".txt", ".md"}, str(asset))

    def test_export_workflow_has_no_publish_authority(self):
        workflow = (ROOT / ".github/workflows/export-service.yml").read_text()
        for forbidden in (
            "self-hosted", "id-token:", "secrets.", "pull_request_target",
            "configure-aws-credentials", "docker build", "docker push",
            "terraform apply", "helm upgrade", "helm install",
        ):
            self.assertNotIn(forbidden, workflow)


if __name__ == "__main__":
    unittest.main()
