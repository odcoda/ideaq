# ideaq Log

## 2026-05-16 project split

Created the standalone `ideaq` project from the web dashboard and iOS app code.
The new repo intentionally excludes queue/completed/project data and expects tools to point at an external data root.
Up next:
- add server-backed data sync when the backend exists
