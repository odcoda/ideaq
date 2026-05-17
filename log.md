# ideaq Log

## 2026-05-17 uv server setup

Switched Python setup docs from manual venv/requirements to `uv run` with project dependencies in `pyproject.toml`.
Trimmed server deployment notes to AWS-only.
Up next:
- deploy on EC2 and configure the clients with the server URL/token

## 2026-05-17 iOS table usability

Made the iOS queue table denser and less edit-heavy:
- portrait shows name, human, and priority; landscape adds description and size
- human/description cells truncate with tap popovers for full text
- main table editing is limited to size and priority menus
- row handles can be dragged to reorder ideas within or across projects

Up next:
- smoke test drag behavior on a physical device

## 2026-05-17 sync server working

Added a Flask/SQLite sync server with bearer-token auth, snapshot revisions, and server-side JSON merge.
Wired web and iOS clients to upload local changes with their last synced base so the server can return a canonical merged snapshot.
Up next:
- deploy the server and test a real web/iOS round trip

## 2026-05-16 local venv docs

Created a local ignored `.venv` for the web dashboard and documented the venv-based run/test commands.
Up next:
- keep runtime dependencies out of git while making local startup explicit

## 2026-05-16 project split

Created the standalone `ideaq` project from the web dashboard and iOS app code.
The new repo intentionally excludes queue/completed/project data and expects tools to point at an external data root.
Up next:
- add server-backed data sync when the backend exists
