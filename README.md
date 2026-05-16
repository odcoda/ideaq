# ideaq

Project-management tooling for local idea queues.

This repository contains the web dashboard and iOS app code only. It does not contain queue data. Point the tools at a separate data root that contains `queue/`, `completed/`, and `projects/`.

## Web

One-time local setup:

```sh
cd /Users/odile/projects/ideaq
python3 -m venv .venv
.venv/bin/python -m pip install flask
```

Run the dashboard against a separate data checkout:

```sh
cd /Users/odile/projects/ideaq
.venv/bin/python web/app.py --data-root /path/to/idea-data
```

For the current local data repo, use:

```sh
.venv/bin/python web/app.py --data-root /Users/odile/projects/meta
```

Run web tests:

```sh
.venv/bin/python -m unittest discover -s web/tests -t .
```

## iOS

Open `/Users/odile/projects/ideaq/ios/IdeaQueue.xcodeproj` in Xcode, or regenerate it from `ios/project.yml` with XcodeGen.

The iOS app keeps local JSON files offline and can optionally sync them with a server snapshot endpoint.
