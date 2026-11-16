"""Unit tests for scripts/gen_inventory.py  (run: python3 -m unittest discover -s tests -v)"""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("gen_inventory", ROOT / "scripts" / "gen_inventory.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

SAMPLE = {
    "web_public_ip": {"value": "3.120.1.10", "type": "string", "sensitive": False},
    "web_private_ip": {"value": "10.0.1.10", "type": "string", "sensitive": False},
    "db_public_ip": {"value": "3.120.1.20", "type": "string", "sensitive": False},
    "db_private_ip": {"value": "10.0.1.20", "type": "string", "sensitive": False},
    "s3_bucket_name": {"value": "devops-final-backups-ab12cd34", "type": "string", "sensitive": False},
    "aws_region": {"value": "eu-central-1", "type": "string", "sensitive": False},
    "ssh_user": {"value": "ubuntu", "type": "string", "sensitive": False},
}


class GenInventoryTests(unittest.TestCase):
    def run_main(self, data):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "out.json"
            dst = Path(tmp) / "inv" / "hosts.ini"
            src.write_text(json.dumps(data))
            code = gen.main(["--from-json", str(src), "--output", str(dst),
                             "--ssh-key", f"{tmp}/key", "--known-hosts", f"{tmp}/kh"])
            return code, (dst.read_text() if dst.exists() else None)

    def test_generates_expected_inventory(self):
        code, text = self.run_main(SAMPLE)
        self.assertEqual(code, 0)
        self.assertIn("[web]\nweb-server ansible_host=3.120.1.10 private_ip=10.0.1.10", text)
        self.assertIn("[db]\ndb-server ansible_host=3.120.1.20 private_ip=10.0.1.20", text)
        self.assertIn("ansible_user=ubuntu", text)
        self.assertIn("s3_bucket=devops-final-backups-ab12cd34", text)
        self.assertIn("aws_region=eu-central-1", text)

    def test_output_is_deterministic(self):
        a = gen.render_inventory(gen.flatten(SAMPLE), Path("/k"), Path("/h"), "ubuntu")
        b = gen.render_inventory(gen.flatten(SAMPLE), Path("/k"), Path("/h"), "ubuntu")
        self.assertEqual(a, b)

    def test_missing_output_fails(self):
        broken = {k: v for k, v in SAMPLE.items() if k != "db_private_ip"}
        code, text = self.run_main(broken)
        self.assertEqual(code, 1)
        self.assertIsNone(text)

    def test_invalid_ip_fails(self):
        broken = json.loads(json.dumps(SAMPLE))
        broken["web_public_ip"]["value"] = "not-an-ip"
        code, _ = self.run_main(broken)
        self.assertEqual(code, 1)

    def test_no_secrets_in_inventory(self):
        _, text = self.run_main(SAMPLE)
        self.assertNotIn("password", text.lower())


if __name__ == "__main__":
    unittest.main()
