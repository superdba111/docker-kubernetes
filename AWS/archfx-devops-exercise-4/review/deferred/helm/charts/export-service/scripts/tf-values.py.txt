#!/usr/bin/env python3
"""Turn the govhigh Terraform outputs into Helm values for export-service, so the
pod security group and the AWS endpoint addresses are never copied by hand.

Generate (deploy step):
    terraform -chdir=terraform/envs/govhigh output -json \\
      | python3 helm/charts/export-service/scripts/tf-values.py > tf-values.json
    helm upgrade ... -f values-govhigh.yaml -f tf-values.json

Check for drift (deploy step, or scheduled):
    terraform -chdir=terraform/envs/govhigh output -json \\
      | python3 helm/charts/export-service/scripts/tf-values.py \\
          --check <(helm get values export-service -n exports -o json)
    Exit 1 if the release uses different endpoint addresses or security group
    than Terraform says exist (e.g. an endpoint was recreated).

JSON is valid YAML, so the output can be passed to helm -f as is.
"""
import argparse
import json
import sys

OUTPUTS = {
    "export_service_security_group_id": ("podSecurityGroup", "groupIds"),
    "export_service_endpoint_cidrs": ("networkPolicy", "awsEndpointCidrs"),
}


def values_from_outputs(outputs: dict) -> dict:
    missing = [name for name in OUTPUTS if name not in outputs]
    if missing:
        raise SystemExit(f"terraform output is missing: {', '.join(missing)}")

    sg = outputs["export_service_security_group_id"]["value"]
    cidrs = outputs["export_service_endpoint_cidrs"]["value"]
    if not sg or not cidrs:
        raise SystemExit("terraform outputs are empty; refusing to render values that would disable egress checks")
    return {
        "podSecurityGroup": {"groupIds": [sg]},
        "networkPolicy": {"awsEndpointCidrs": sorted(cidrs)},
    }


def _get(values: dict, path: tuple) -> list:
    node = values
    for key in path:
        node = (node or {}).get(key)
    return sorted(node or [])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", metavar="RELEASE_VALUES_JSON",
                        help="compare against a release's values (helm get values -o json)")
    args = parser.parse_args()

    wanted = values_from_outputs(json.load(sys.stdin))

    if not args.check:
        json.dump(wanted, sys.stdout, indent=2)
        print()
        return 0

    with open(args.check) as f:
        deployed = json.load(f) or {}
    drift = []
    for path in OUTPUTS.values():
        want, have = _get(wanted, path), _get(deployed, path)
        if want != have:
            drift.append(f"{'.'.join(path)}: release has {have}, Terraform has {want}")
    if drift:
        print("export-service values are out of sync with Terraform:", file=sys.stderr)
        for line in drift:
            print(f"  {line}", file=sys.stderr)
        return 1
    print("export-service values match Terraform outputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
