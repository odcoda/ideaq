"""Shared snapshot storage and merge helpers for Idea Queue sync."""

from __future__ import annotations

import hashlib
import json
import posixpath
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import PurePosixPath
from typing import Any


TRACKED_DIRECTORIES = ("queue", "completed", "projects")
MISSING = object()


class SyncStoreError(Exception):
    """Base class for sync store errors."""


class InvalidPathError(SyncStoreError):
    """Raised when a snapshot contains a path outside the tracked data set."""


class UnknownBaseRevisionError(SyncStoreError):
    """Raised when a client uploads against a revision this server does not know."""


@dataclass(frozen=True)
class Snapshot:
    revision: str
    files: dict[str, str]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def validate_store_id(store_id: str) -> str:
    cleaned = store_id.strip()
    if not cleaned:
        raise ValueError("store ID is required")
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    if any(char not in allowed for char in cleaned):
        raise ValueError("store ID may only contain letters, numbers, dots, underscores, and hyphens")
    return cleaned


def validate_snapshot_path(path: str) -> str:
    raw_path = PurePosixPath(path.replace("\\", "/"))
    normalized = posixpath.normpath(raw_path.as_posix())
    pure_path = PurePosixPath(normalized)
    if (
        path.startswith("/")
        or normalized == "."
        or ".." in raw_path.parts
        or ".." in pure_path.parts
        or pure_path.parts[0] not in TRACKED_DIRECTORIES
        or pure_path.suffix != ".json"
    ):
        raise InvalidPathError(f"invalid snapshot path: {path}")
    return normalized


def normalize_files(files: dict[str, str]) -> dict[str, str]:
    normalized: dict[str, str] = {}
    for raw_path, contents in files.items():
        if not isinstance(raw_path, str) or not isinstance(contents, str):
            raise InvalidPathError("snapshot files must map string paths to string contents")
        normalized[validate_snapshot_path(raw_path)] = contents
    return dict(sorted(normalized.items()))


def revision_for_files(files: dict[str, str]) -> str:
    normalized = normalize_files(files)
    payload = json.dumps(
        normalized,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:32]


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def merge_snapshots(
    base: dict[str, str],
    current: dict[str, str],
    incoming: dict[str, str],
) -> dict[str, str]:
    """Three-way merge snapshot files.

    The merge is deliberately biased toward keeping usable queue JSON. When both
    sides edited the same idea file, records are merged by idea name and fields
    use normal three-way rules. Same-field scalar conflicts are resolved by the
    incoming client value because this is a single-user system and the newest
    manual sync should be allowed to make progress.
    """

    base = normalize_files(base)
    current = normalize_files(current)
    incoming = normalize_files(incoming)
    paths = sorted(set(base) | set(current) | set(incoming))
    merged: dict[str, str] = {}

    for path in paths:
        resolved = merge_file(path, base.get(path), current.get(path), incoming.get(path))
        if resolved is not None:
            merged[path] = resolved

    return normalize_files(merged)


def merge_file(path: str, base_text: str | None, current_text: str | None, incoming_text: str | None) -> str | None:
    if incoming_text == current_text:
        return incoming_text
    if incoming_text == base_text:
        return current_text
    if current_text == base_text:
        return incoming_text

    if incoming_text is None:
        return current_text
    if current_text is None:
        return incoming_text

    try:
        base_json = json.loads(base_text) if base_text is not None else MISSING
        current_json = json.loads(current_text)
        incoming_json = json.loads(incoming_text)
    except json.JSONDecodeError:
        return incoming_text

    if path == "queue/PROJECTS.json" and are_string_lists(current_json, incoming_json):
        base_list = base_json if isinstance(base_json, list) else []
        return json_text(merge_ordered_strings(base_list, current_json, incoming_json))

    if are_idea_lists(current_json, incoming_json) and (
        base_json is MISSING or isinstance(base_json, list)
    ):
        base_list = base_json if isinstance(base_json, list) else []
        return json_text(merge_idea_lists(base_list, current_json, incoming_json))

    merged_json = merge_json_value(base_json, current_json, incoming_json)
    if merged_json is MISSING:
        return None
    return json_text(merged_json)


def merge_json_value(base: Any, current: Any, incoming: Any) -> Any:
    if incoming == current:
        return incoming
    if incoming == base:
        return current
    if current == base:
        return incoming
    if incoming is MISSING:
        return current
    if current is MISSING:
        return incoming

    if isinstance(base, dict) or isinstance(current, dict) or isinstance(incoming, dict):
        if not isinstance(current, dict) or not isinstance(incoming, dict):
            return incoming
        base_dict = base if isinstance(base, dict) else {}
        keys = sorted(set(base_dict) | set(current) | set(incoming))
        merged: dict[str, Any] = {}
        for key in keys:
            resolved = merge_json_value(
                base_dict.get(key, MISSING),
                current.get(key, MISSING),
                incoming.get(key, MISSING),
            )
            if resolved is not MISSING:
                merged[key] = resolved
        return merged

    if are_string_lists(current, incoming):
        base_list = base if isinstance(base, list) else []
        return merge_ordered_strings(base_list, current, incoming)

    return incoming


def merge_idea_lists(base: list[Any], current: list[Any], incoming: list[Any]) -> list[dict[str, Any]]:
    if not have_unique_names(base, current, incoming):
        return incoming

    base_by_name = ideas_by_name(base)
    current_by_name = ideas_by_name(current)
    incoming_by_name = ideas_by_name(incoming)
    names = merge_ordered_strings(
        list(base_by_name),
        list(current_by_name),
        list(incoming_by_name),
    )

    merged: list[dict[str, Any]] = []
    for name in names:
        resolved = merge_json_value(
            base_by_name.get(name, MISSING),
            current_by_name.get(name, MISSING),
            incoming_by_name.get(name, MISSING),
        )
        if resolved is not MISSING:
            merged.append(resolved)
    return merged


def merge_ordered_strings(base: list[Any], current: list[Any], incoming: list[Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for source in (incoming, current, base):
        for item in source:
            if isinstance(item, str) and item not in seen:
                result.append(item)
                seen.add(item)
    return result


def are_string_lists(*values: Any) -> bool:
    return all(isinstance(value, list) and all(isinstance(item, str) for item in value) for value in values)


def are_idea_lists(*values: Any) -> bool:
    return all(
        isinstance(value, list)
        and all(isinstance(item, dict) and isinstance(item.get("name"), str) for item in value)
        for value in values
    )


def have_unique_names(*idea_lists: list[Any]) -> bool:
    for ideas in idea_lists:
        names = [item.get("name") for item in ideas if isinstance(item, dict)]
        if len(names) != len(set(names)):
            return False
    return True


def ideas_by_name(ideas: list[Any]) -> dict[str, dict[str, Any]]:
    return {
        item["name"]: item
        for item in ideas
        if isinstance(item, dict) and isinstance(item.get("name"), str)
    }


class SQLiteSnapshotStore:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.initialize()

    def initialize(self) -> None:
        with self.connect() as db:
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS stores (
                    store_id TEXT PRIMARY KEY,
                    current_revision TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS snapshots (
                    store_id TEXT NOT NULL,
                    revision TEXT NOT NULL,
                    files_json TEXT NOT NULL,
                    base_revision TEXT,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY (store_id, revision),
                    FOREIGN KEY (store_id) REFERENCES stores(store_id)
                )
                """
            )

    def connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.db_path)
        db.row_factory = sqlite3.Row
        return db

    def get_snapshot(self, store_id: str) -> Snapshot:
        store_id = validate_store_id(store_id)
        with self.connect() as db:
            return self._get_current_snapshot(db, store_id)

    def put_snapshot(
        self,
        store_id: str,
        base_revision: str,
        files: dict[str, str],
        client_base_files: dict[str, str] | None = None,
    ) -> Snapshot:
        store_id = validate_store_id(store_id)
        incoming = normalize_files(files)
        client_base = normalize_files(client_base_files) if client_base_files is not None else None
        with self.connect() as db:
            current = self._get_current_snapshot(db, store_id)
            if client_base is not None:
                fetched_server = current
                if base_revision != current.revision:
                    fetched_files = self._get_snapshot_files(db, store_id, base_revision)
                    if fetched_files is None:
                        raise UnknownBaseRevisionError(f"unknown base revision: {base_revision}")
                    fetched_server = Snapshot(revision=base_revision, files=fetched_files)

                client_merged = merge_snapshots(client_base, fetched_server.files, incoming)
                if fetched_server.revision == current.revision:
                    merged = client_merged
                else:
                    merged = merge_snapshots(fetched_server.files, current.files, client_merged)
            elif base_revision == current.revision:
                merged = incoming
            else:
                base = self._get_snapshot_files(db, store_id, base_revision)
                if base is None:
                    raise UnknownBaseRevisionError(f"unknown base revision: {base_revision}")
                merged = merge_snapshots(base, current.files, incoming)

            if merged == current.files:
                return current

            revision = revision_for_files(merged)
            self._insert_snapshot(db, store_id, revision, merged, base_revision)
            db.execute(
                """
                UPDATE stores
                SET current_revision = ?, updated_at = ?
                WHERE store_id = ?
                """,
                (revision, utc_now(), store_id),
            )
            return Snapshot(revision=revision, files=merged)

    def _get_current_snapshot(self, db: sqlite3.Connection, store_id: str) -> Snapshot:
        row = db.execute(
            "SELECT current_revision FROM stores WHERE store_id = ?",
            (store_id,),
        ).fetchone()
        if row is None:
            return self._create_empty_store(db, store_id)

        files = self._get_snapshot_files(db, store_id, row["current_revision"])
        if files is None:
            return self._create_empty_store(db, store_id)
        return Snapshot(revision=row["current_revision"], files=files)

    def _create_empty_store(self, db: sqlite3.Connection, store_id: str) -> Snapshot:
        files: dict[str, str] = {}
        revision = revision_for_files(files)
        self._insert_snapshot(db, store_id, revision, files, None)
        db.execute(
            """
            INSERT OR REPLACE INTO stores (store_id, current_revision, updated_at)
            VALUES (?, ?, ?)
            """,
            (store_id, revision, utc_now()),
        )
        return Snapshot(revision=revision, files=files)

    def _get_snapshot_files(
        self,
        db: sqlite3.Connection,
        store_id: str,
        revision: str,
    ) -> dict[str, str] | None:
        row = db.execute(
            """
            SELECT files_json
            FROM snapshots
            WHERE store_id = ? AND revision = ?
            """,
            (store_id, revision),
        ).fetchone()
        if row is None:
            return None
        return normalize_files(json.loads(row["files_json"]))

    def _insert_snapshot(
        self,
        db: sqlite3.Connection,
        store_id: str,
        revision: str,
        files: dict[str, str],
        base_revision: str | None,
    ) -> None:
        db.execute(
            """
            INSERT OR IGNORE INTO snapshots (store_id, revision, files_json, base_revision, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                store_id,
                revision,
                json.dumps(normalize_files(files), sort_keys=True, ensure_ascii=False),
                base_revision,
                utc_now(),
            ),
        )
