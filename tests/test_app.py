"""Unit tests for the Flask app with a fake database (no Postgres needed).

Run:  pip install flask psycopg2-binary && python3 -m unittest discover -s tests -v
"""
import importlib.util
import os
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent

try:
    spec = importlib.util.spec_from_file_location("flask_app", ROOT / "app" / "flask" / "app.py")
    flask_app = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flask_app)
except ModuleNotFoundError:  # flask / psycopg2 not installed on this machine
    flask_app = None


class FakeCursor:
    def __init__(self):
        self.last = ""

    def execute(self, sql, *args):
        self.last = sql

    def fetchone(self):
        return (42,)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeConn:
    def cursor(self):
        return FakeCursor()

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


@unittest.skipIf(flask_app is None, "flask/psycopg2 not installed")
class AppTests(unittest.TestCase):
    def setUp(self):
        self.client = flask_app.app.test_client()

    def test_health_ok_when_db_up(self):
        with mock.patch.object(flask_app, "get_conn", return_value=FakeConn()):
            resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json()["status"], "ok")

    def test_health_503_when_db_down(self):
        with mock.patch.object(flask_app, "get_conn", side_effect=RuntimeError("boom")):
            resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 503)
        self.assertNotIn("boom", resp.get_data(as_text=True))  # no internal details leaked

    def test_index_shows_counter(self):
        with mock.patch.object(flask_app, "get_conn", return_value=FakeConn()):
            resp = self.client.get("/")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("42", resp.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
