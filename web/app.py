# /// script
# requires-python = ">=3.10"
# dependencies = ["flask"]
# ///
"""Idea queue dashboard. Reads/writes JSON files in a configured data root."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from flask import Flask, current_app, jsonify, render_template, request

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from server.sync_core import (  # noqa: E402
    TRACKED_DIRECTORIES,
    InvalidPathError,
    normalize_files,
    validate_snapshot_path,
)


DEFAULT_DATA_ROOT = Path.cwd()


def get_data_root():
    return Path(current_app.config["DATA_ROOT"])


def get_queue_dir():
    return Path(current_app.config["QUEUE_DIR"])


def get_completed_dir():
    return Path(current_app.config["COMPLETED_DIR"])


def get_project_order_file():
    return Path(current_app.config["PROJECTS_ORDER_FILE"])


def write_json_file(path, data, *, ensure_ascii=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=ensure_ascii) + "\n")


def read_project_order():
    """Return ordered list of project names, or empty list if file missing."""
    try:
        return json.loads(get_project_order_file().read_text())
    except (json.JSONDecodeError, OSError, FileNotFoundError):
        return []


def write_project_order(order):
    write_json_file(get_project_order_file(), order)


def ordered_project_names(projects):
    order = read_project_order()
    known = set(order)
    for project_name in sorted(projects.keys()):
        if project_name not in known:
            order.append(project_name)
    return order


def read_all():
    """Return {project_name: [ideas]} for every .json in queue/."""
    projects = {}
    for f in sorted(get_queue_dir().glob("*.json")):
        if f.name == "PROJECTS.json":
            continue
        try:
            data = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            data = []
        projects[f.stem] = data
    return projects


def write_project(name, ideas):
    path = get_queue_dir() / f"{name}.json"
    write_json_file(path, ideas, ensure_ascii=False)


def rename_in_related(projects, old_name, new_name):
    """Update 'related' arrays across all projects when an idea is renamed."""
    changed = set()
    for proj, ideas in projects.items():
        for idea in ideas:
            rel = idea.get("related", [])
            if old_name in rel:
                idea["related"] = [new_name if r == old_name else r for r in rel]
                changed.add(proj)
    return changed


def get_web_state_dir():
    data_root_key = hashlib.sha256(str(get_data_root()).encode("utf-8")).hexdigest()[:16]
    state_root = Path(
        os.environ.get("IDEAQ_WEB_STATE_ROOT", Path.home() / ".local" / "state" / "ideaq")
    )
    return state_root / data_root_key


def load_tracked_files(root):
    files = {}
    for directory_name in TRACKED_DIRECTORIES:
        directory = Path(root) / directory_name
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*.json")):
            relative_path = path.relative_to(root).as_posix()
            validate_snapshot_path(relative_path)
            files[relative_path] = path.read_text(encoding="utf-8")
    return normalize_files(files)


def replace_tracked_files(root, files):
    files = normalize_files(files)
    root = Path(root)
    existing = load_tracked_files(root)
    for relative_path in sorted(set(existing).difference(files)):
        path = root / relative_path
        if path.exists():
            path.unlink()

    for relative_path, contents in files.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")


def load_base_tracked_files():
    base_dir = get_web_state_dir() / "base"
    if not base_dir.exists():
        return {}
    return load_tracked_files(base_dir)


def replace_base_tracked_files(files):
    base_dir = get_web_state_dir() / "base"
    base_dir.mkdir(parents=True, exist_ok=True)
    replace_tracked_files(base_dir, files)


def snapshot_url(server_url, store_id):
    cleaned_url = str(server_url).strip().rstrip("/")
    cleaned_store = str(store_id).strip()
    if not cleaned_url or not cleaned_store:
        raise ValueError("server URL and store ID are required")
    return f"{cleaned_url}/v1/stores/{quote(cleaned_store, safe='')}/snapshot"


def request_json(method, url, token="", payload=None):
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "IdeaQueue-Web",
    }
    cleaned_token = str(token).strip()
    if cleaned_token:
        headers["Authorization"] = f"Bearer {cleaned_token}"

    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    req = Request(url, data=body, headers=headers, method=method)
    try:
        with urlopen(req, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        try:
            data = json.loads(exc.read().decode("utf-8"))
            message = data.get("error") or data.get("message") or exc.reason
        except (json.JSONDecodeError, UnicodeDecodeError):
            message = exc.reason
        raise RuntimeError(f"sync server error: {message}") from exc
    except URLError as exc:
        raise RuntimeError(f"could not reach sync server: {exc.reason}") from exc


def sync_with_server(config):
    url = snapshot_url(config.get("server_url", ""), config.get("store_id", ""))
    token = config.get("token", "")
    local_files = load_tracked_files(get_data_root())
    base_files = load_base_tracked_files()
    server_snapshot = request_json("GET", url, token)
    server_files = normalize_files(server_snapshot.get("files", {}))
    changed_local_paths = sorted(
        path
        for path in set(local_files) | set(base_files)
        if local_files.get(path) != base_files.get(path)
    )

    if changed_local_paths:
        final_snapshot = request_json(
            "PUT",
            url,
            token,
            {
                "base_revision": server_snapshot["revision"],
                "files": local_files,
                "client_base_files": base_files,
            },
        )
    else:
        final_snapshot = server_snapshot

    final_files = normalize_files(final_snapshot.get("files", {}))
    replace_tracked_files(get_data_root(), final_files)
    replace_base_tracked_files(final_files)
    projects = read_all()
    return {
        "ok": True,
        "revision": final_snapshot["revision"],
        "files_count": len(final_files),
        "uploaded_count": len(changed_local_paths),
        "projects": projects,
        "project_order": ordered_project_names(projects),
    }


def create_app(data_root: str | Path | None = None):
    app = Flask(__name__)

    resolved_data_root = (
        Path(data_root).expanduser().resolve()
        if data_root is not None
        else DEFAULT_DATA_ROOT.resolve()
    )
    queue_dir = resolved_data_root / "queue"
    completed_dir = resolved_data_root / "completed"

    app.config.update(
        DATA_ROOT=resolved_data_root,
        QUEUE_DIR=queue_dir,
        COMPLETED_DIR=completed_dir,
        PROJECTS_ORDER_FILE=queue_dir / "PROJECTS.json",
    )

    queue_dir.mkdir(parents=True, exist_ok=True)
    completed_dir.mkdir(parents=True, exist_ok=True)

    @app.route("/")
    def index():
        projects = read_all()
        order = ordered_project_names(projects)
        return render_template("index.html", projects=projects, project_order=order)

    @app.route("/api/projects", methods=["GET"])
    def api_projects():
        return jsonify(read_all())

    @app.route("/api/save", methods=["POST"])
    def api_save():
        """Save projects included in body. Body: {project: [ideas], ...}."""
        data = request.get_json(force=True)
        for proj, ideas in data.items():
            write_project(proj, ideas)
        return jsonify(ok=True)

    @app.route("/api/update_idea", methods=["POST"])
    def api_update_idea():
        """Update a single idea field. Handles related-rename if name changes.
        Body: {project, index, field, value, old_value?}
        """
        data = request.get_json(force=True)
        proj = data["project"]
        idx = data["index"]
        field = data["field"]
        value = data["value"]

        projects = read_all()
        idea = projects[proj][idx]
        old_name = idea.get("name")
        idea[field] = value

        changed = set()
        if field == "name" and old_name != value:
            changed = rename_in_related(projects, old_name, value)

        changed.add(proj)
        for project_name in changed:
            write_project(project_name, projects[project_name])
        return jsonify(ok=True)

    @app.route("/api/move_idea", methods=["POST"])
    def api_move_idea():
        """Move idea between projects or reorder within.
        Body: {from_project, from_index, to_project, to_index}
        """
        data = request.get_json(force=True)
        projects = read_all()
        src = data["from_project"]
        dst = data["to_project"]
        from_index = data["from_index"]
        to_index = data["to_index"]

        idea = projects[src].pop(from_index)
        if dst not in projects:
            projects[dst] = []
        projects[dst].insert(to_index, idea)

        write_project(src, projects[src])
        write_project(dst, projects[dst])
        return jsonify(ok=True)

    @app.route("/api/new_project", methods=["POST"])
    def api_new_project():
        data = request.get_json(force=True)
        name = data["name"].strip()
        if not name:
            return jsonify(ok=False, error="empty name"), 400
        write_project(name, [])
        return jsonify(ok=True)

    @app.route("/api/new_idea", methods=["POST"])
    def api_new_idea():
        data = request.get_json(force=True)
        proj = data["project"]
        projects = read_all()
        if proj not in projects:
            projects[proj] = []
        projects[proj].append({
            "name": "new_idea",
            "human_idea": "",
            "description": "",
            "difficulty": "S",
            "related": [],
            "priority": "none",
        })
        write_project(proj, projects[proj])
        return jsonify(ok=True)

    @app.route("/api/project_order", methods=["POST"])
    def api_project_order():
        """Save project display order. Body: ["proj1", "proj2", ...]."""
        order = request.get_json(force=True)
        write_project_order(order)
        return jsonify(ok=True)

    @app.route("/api/complete_idea", methods=["POST"])
    def api_complete_idea():
        """Move idea from queue to completed. Body: {project, index}."""
        data = request.get_json(force=True)
        proj = data["project"]
        idx = data["index"]

        projects = read_all()
        idea = projects[proj].pop(idx)
        write_project(proj, projects[proj])

        comp_path = get_completed_dir() / f"{proj}.json"
        try:
            completed = json.loads(comp_path.read_text())
        except (json.JSONDecodeError, OSError, FileNotFoundError):
            completed = []
        completed.append(idea)
        write_json_file(comp_path, completed, ensure_ascii=False)

        return jsonify(ok=True)

    @app.route("/api/delete_idea", methods=["POST"])
    def api_delete_idea():
        """Delete idea from queue. Body: {project, index}."""
        data = request.get_json(force=True)
        proj = data["project"]
        idx = data["index"]

        projects = read_all()
        projects[proj].pop(idx)
        write_project(proj, projects[proj])
        return jsonify(ok=True)

    @app.route("/api/git_commit_push", methods=["POST"])
    def api_git_commit_push():
        """Commit all changes and push."""
        data_root = get_data_root()
        try:
            subprocess.run(
                ["git", "add", "-A"],
                cwd=data_root,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=data_root,
                capture_output=True,
                text=True,
            )
            if not result.stdout.strip():
                return jsonify(ok=True, message="Nothing to commit")
            subprocess.run(
                ["git", "commit", "-m", "Update queues from dashboard"],
                cwd=data_root,
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["git", "push", "origin", "main"],
                cwd=data_root,
                check=True,
                capture_output=True,
                text=True,
            )
            return jsonify(ok=True, message="Committed and pushed")
        except subprocess.CalledProcessError as exc:
            return jsonify(ok=False, error=exc.stderr or str(exc)), 500

    @app.route("/api/sync", methods=["POST"])
    def api_sync():
        data = request.get_json(force=True)
        try:
            return jsonify(sync_with_server(data))
        except (InvalidPathError, ValueError, RuntimeError, KeyError) as exc:
            return jsonify(ok=False, error=str(exc)), 400

    return app


def parse_args(argv: list[str] | None = None):
    parser = argparse.ArgumentParser(description="Run the Idea Queue dashboard.")
    parser.add_argument(
        "--data-root",
        type=Path,
        required=True,
        help="Directory containing queue/, completed/, and projects/.",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5050)
    parser.add_argument("--no-debug", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None):
    args = parse_args(argv)
    create_app(args.data_root).run(
        host=args.host,
        port=args.port,
        debug=not args.no_debug,
    )


if __name__ == "__main__":
    main()
