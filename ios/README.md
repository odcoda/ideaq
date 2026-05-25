# IdeaQueue iOS app

Offline-first SwiftUI port of the `web/` dashboard.

## What it does

- keeps a local copy of `queue/`, `completed/`, and `projects/` JSON files in app storage
- mirrors dashboard edits directly into those local JSON files
- optionally syncs those tracked JSON files with a server snapshot endpoint
- preserves the existing queue semantics, including rename propagation across `related`

## Sync model

The app does not depend on git for data sync. It keeps local JSON files as the offline source of truth, and sync is best-effort when a server is configured.

- `Sync now` fetches the server snapshot, uploads local JSON plus the last synced base snapshot when local changes need to be published, then accepts the server's canonical merged snapshot
- if the server URL is blank or the request fails, local editing still works
- server-side merge handles conflicts based on the last synced base snapshot

The expected server contract is intentionally small:

```http
GET /v1/stores/{storeID}/snapshot
```

```json
{
  "revision": "opaque-server-revision",
  "files": {
    "queue/PROJECTS.json": "[\"ksink\"]\n",
    "queue/ksink.json": "[]\n"
  }
}
```

```http
PUT /v1/stores/{storeID}/snapshot
```

```json
{
  "base_revision": "opaque-server-revision",
  "files": {
    "queue/PROJECTS.json": "[\"ksink\"]\n",
    "queue/ksink.json": "[]\n"
  },
  "client_base_files": {
    "queue/PROJECTS.json": "[]\n"
  }
}
```

`client_base_files` lets the server do a proper three-way merge. `PUT` should return the same shape as `GET`, with the new revision and canonical files. If the server needs auth, the app sends the optional token as `Authorization: Bearer <token>`.

## Setup

1. Open `/Users/odile/projects/ideaq/ios/IdeaQueue.xcodeproj` in Xcode.
2. Pick an iPhone simulator or device.
3. Run the `IdeaQueue` scheme.

Server sync is optional. Configure the server URL, store ID, and optional bearer token in the sync sheet. To enter a generated token once on a physical iPhone, copy it on a Mac using the same Apple Account with Handoff enabled, then tap `Paste` in the sync sheet; Universal Clipboard sends it to the phone. The eye button reveals the pasted token temporarily for verification.

## Installing on a personal iPhone

For installs that last longer than the free 7-day Personal Team window, use a paid Apple Developer Program membership.

1. Enroll in the Apple Developer Program with the Apple Account you use in Xcode.
2. In Xcode, open Settings > Accounts and add that Apple Account.
3. Open the `IdeaQueue` target, go to Signing & Capabilities, enable automatic signing, and select your paid team.
4. Keep the bundle ID unique in your developer account. The current ID is `com.odcoda.ideaq.ideaqueue`.
5. Connect the iPhone, trust the computer, and enable Developer Mode on the phone if iOS prompts for it.
6. Select the iPhone as the run destination and press Run. If Xcode asks to register the device, allow it.

Do not commit account-local signing materials. Certificates and private keys belong in Keychain, and generated profiles, archives, and exported IPAs are ignored by the repository.

## Regenerating the project

The project is generated from `project.yml`:

```sh
cd /Users/odile/projects/ideaq/ios
xcodegen generate
```

## Tests

```sh
cd /Users/odile/projects/ideaq/ios
xcodebuild test \
  -project IdeaQueue.xcodeproj \
  -scheme IdeaQueue \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```
