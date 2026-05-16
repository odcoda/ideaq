# /// script
# requires-python = ">=3.10"
# dependencies = ["flask"]
# ///
"""Idea queue dashboard. Reads/writes JSON files in a configured data root."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from flask import Flask, current_app, jsonify, render_template, request


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
        order = read_project_order()
        # ensure order includes all projects, append any new ones
        known = set(order)
        for project_name in sorted(projects.keys()):
            if project_name not in known:
                order.append(project_name)
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
