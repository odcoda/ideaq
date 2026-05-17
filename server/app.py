# /// script
# requires-python = ">=3.10"
# dependencies = ["flask", "gunicorn"]
# ///
"""HTTP API for syncing Idea Queue snapshots."""

from __future__ import annotations

import argparse
import hmac
import os
import sys
from pathlib import Path

from flask import Flask, current_app, jsonify, request

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from server.sync_core import (  # noqa: E402
    InvalidPathError,
    SQLiteSnapshotStore,
    SyncStoreError,
    UnknownBaseRevisionError,
    validate_store_id,
)


DEFAULT_DB_PATH = Path("ideaq-sync.sqlite3")


def create_app(
    db_path: str | Path | None = None,
    token: str | None = None,
    *,
    allow_missing_token: bool = False,
) -> Flask:
    app = Flask(__name__)
    resolved_db_path = Path(
        db_path or os.environ.get("IDEAQ_SERVER_DB") or DEFAULT_DB_PATH
    ).expanduser()
    resolved_db_path.parent.mkdir(parents=True, exist_ok=True)

    app.config.update(
        SYNC_STORE=SQLiteSnapshotStore(str(resolved_db_path)),
        SYNC_TOKEN=token if token is not None else os.environ.get("IDEAQ_SYNC_TOKEN", ""),
        ALLOW_MISSING_TOKEN=allow_missing_token,
    )

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify(ok=True)

    @app.route("/v1/stores/<store_id>/snapshot", methods=["GET"])
    def get_snapshot(store_id: str):
        auth_error = require_auth()
        if auth_error is not None:
            return auth_error

        try:
            snapshot = current_app.config["SYNC_STORE"].get_snapshot(validate_store_id(store_id))
        except ValueError as exc:
            return error_response(str(exc), 400)

        return jsonify(revision=snapshot.revision, files=snapshot.files)

    @app.route("/v1/stores/<store_id>/snapshot", methods=["PUT"])
    def put_snapshot(store_id: str):
        auth_error = require_auth()
        if auth_error is not None:
            return auth_error

        data = request.get_json(force=True, silent=True)
        if not isinstance(data, dict):
            return error_response("request body must be a JSON object", 400)

        base_revision = data.get("base_revision")
        files = data.get("files")
        client_base_files = data.get("client_base_files")
        if not isinstance(base_revision, str) or not isinstance(files, dict):
            return error_response("request must include base_revision and files", 400)
        if client_base_files is not None and not isinstance(client_base_files, dict):
            return error_response("client_base_files must be an object when provided", 400)

        try:
            snapshot = current_app.config["SYNC_STORE"].put_snapshot(
                validate_store_id(store_id),
                base_revision,
                files,
                client_base_files,
            )
        except ValueError as exc:
            return error_response(str(exc), 400)
        except InvalidPathError as exc:
            return error_response(str(exc), 400)
        except UnknownBaseRevisionError as exc:
            return error_response(str(exc), 409)
        except SyncStoreError as exc:
            return error_response(str(exc), 500)

        return jsonify(revision=snapshot.revision, files=snapshot.files)

    return app


def require_auth():
    expected = current_app.config["SYNC_TOKEN"]
    if not expected and current_app.config["ALLOW_MISSING_TOKEN"]:
        return None
    if not expected:
        return error_response("server auth token is not configured", 500)

    header = request.headers.get("Authorization", "")
    prefix = "Bearer "
    if not header.startswith(prefix):
        return error_response("missing bearer token", 401)

    actual = header[len(prefix):].strip()
    if not hmac.compare_digest(actual, expected):
        return error_response("invalid bearer token", 403)
    return None


def error_response(message: str, status: int):
    return jsonify(ok=False, error=message, message=message), status


def parse_args(argv: list[str] | None = None):
    parser = argparse.ArgumentParser(description="Run the Idea Queue sync server.")
    parser.add_argument("--db", type=Path, default=None, help="SQLite database path.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8050)
    parser.add_argument("--token", default=None, help="Bearer token. Defaults to IDEAQ_SYNC_TOKEN.")
    parser.add_argument("--allow-missing-token", action="store_true", help="Only for local development.")
    parser.add_argument("--no-debug", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None):
    args = parse_args(argv)
    create_app(args.db, args.token, allow_missing_token=args.allow_missing_token).run(
        host=args.host,
        port=args.port,
        debug=not args.no_debug,
    )


if __name__ == "__main__":
    main()
