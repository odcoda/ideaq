# ideaq

Project-management tooling for local idea queues.

This repository contains the web dashboard and iOS app code only. It does not contain queue data. Point the tools at a separate data root that contains `queue/`, `completed/`, and `projects/`.

## Web

```sh
cd /Users/odile/projects/ideaq/web
uv run app.py --data-root /path/to/idea-data
```

## iOS

Open `/Users/odile/projects/ideaq/ios/IdeaQueue.xcodeproj` in Xcode, or regenerate it from `ios/project.yml` with XcodeGen.

The iOS app keeps local JSON files offline and can optionally sync them with a server snapshot endpoint.
