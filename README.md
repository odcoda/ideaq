# ideaq

Project-management tooling for local idea queues.

This repository contains the web dashboard and iOS app code only. It does not contain queue data. Point the tools at a separate data root that contains `queue/`, `completed/`, and `projects/`.

## Server

The sync server lives in `server/`. It is a small Flask app backed by SQLite with bearer-token auth and server-side three-way merge.

Local setup:

```sh
cd /Users/odile/projects/ideaq
export IDEAQ_SYNC_TOKEN="$(uv run python -c 'import secrets; print(secrets.token_urlsafe(32))')"
export IDEAQ_SERVER_DB=/tmp/ideaq-sync.sqlite3
uv run python server/app.py --host 127.0.0.1 --port 8050 --no-debug
```

AWS/setup notes are in `server/README.md`.

## Web

Run the dashboard against a separate data checkout:

```sh
cd /Users/odile/projects/ideaq
uv run python web/app.py --data-root /path/to/idea-data
```

For the current local data repo, use:

```sh
uv run python web/app.py --data-root /Users/odile/projects/meta
```

Run web tests:

```sh
uv run python -m unittest discover -s web/tests -t .
```

## iOS

Open `/Users/odile/projects/ideaq/ios/IdeaQueue.xcodeproj` in Xcode, or regenerate it from `ios/project.yml` with XcodeGen.

The iOS app keeps local JSON files offline and can optionally sync them with a server snapshot endpoint.

## Tests

```sh
cd /Users/odile/projects/ideaq
uv run python -m unittest discover -s server/tests -t .
uv run python -m unittest discover -s web/tests -t .
xcodebuild test -project ios/IdeaQueue.xcodeproj -scheme IdeaQueue -destination 'platform=iOS Simulator,name=iPhone 15'
```
