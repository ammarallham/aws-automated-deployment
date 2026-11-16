"""Tiny Flask app that talks to Postgres.

GET /        -> HTML page with a visit counter stored in Postgres (proves web -> db works)
GET /health  -> 200 {"status": "ok"} when the app AND the database are reachable, else 503
"""
import os
import socket

import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)


def get_conn():
    """Open a new DB connection using settings from environment variables."""
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=3,
    )


@app.get("/")
def index():
    conn = get_conn()
    try:
        with conn, conn.cursor() as cur:  # `with conn` commits the transaction
            cur.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                "id SERIAL PRIMARY KEY, visited_at TIMESTAMPTZ NOT NULL DEFAULT now())"
            )
            cur.execute("INSERT INTO visits DEFAULT VALUES")
            cur.execute("SELECT count(*) FROM visits")
            total = cur.fetchone()[0]
    finally:
        conn.close()

    return (
        "<!doctype html><title>Automated Deployment</title>"
        "<h1>Automated Deployment on AWS</h1>"
        "<p>Terraform + Ansible + Docker Compose (Flask + Nginx + Postgres)</p>"
        f"<p>Visits stored in Postgres: <b>{total}</b></p>"
        f"<p>Served by container: {socket.gethostname()}</p>"
    )


@app.get("/health")
def health():
    try:
        conn = get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        finally:
            conn.close()
    except Exception as exc:  # noqa: BLE001 - any failure means "not healthy"
        app.logger.warning("health check failed: %s", exc)
        return jsonify(status="degraded", database="down"), 503
    return jsonify(status="ok", database="up"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
