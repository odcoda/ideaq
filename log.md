# ideaq Log

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
