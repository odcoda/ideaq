import json
import tempfile
import unittest
from pathlib import Path

from server.sync_core import (
    InvalidPathError,
    SQLiteSnapshotStore,
    UnknownBaseRevisionError,
    json_text,
    merge_snapshots,
    normalize_files,
)


class SyncCoreMergeTests(unittest.TestCase):
    maxDiff = None

    def test_merge_combines_different_fields_on_same_idea(self):
        base = {
            "queue/alpha.json": json_text([
                {
                    "name": "alpha_one",
                    "human_idea": "base",
                    "description": "base description",
                    "difficulty": "S",
                    "related": ["old"],
                    "priority": "none",
                }
            ])
        }
        current = {
            "queue/alpha.json": json_text([
                {
                    "name": "alpha_one",
                    "human_idea": "server",
                    "description": "base description",
                    "difficulty": "S",
                    "related": ["old", "server_rel"],
                    "priority": "high",
                }
            ])
        }
        incoming = {
            "queue/alpha.json": json_text([
                {
                    "name": "alpha_one",
                    "human_idea": "base",
                    "description": "local description",
                    "difficulty": "S",
                    "related": ["old", "local_rel"],
                    "priority": "none",
                }
            ])
        }

        merged = merge_snapshots(base, current, incoming)
        idea = json.loads(merged["queue/alpha.json"])[0]

        self.assertEqual(idea["human_idea"], "server")
        self.assertEqual(idea["description"], "local description")
        self.assertEqual(idea["priority"], "high")
        self.assertEqual(idea["related"], ["old", "local_rel", "server_rel"])

    def test_merge_project_order_keeps_projects_from_both_sides(self):
        merged = merge_snapshots(
            {"queue/PROJECTS.json": json_text(["alpha"])},
            {"queue/PROJECTS.json": json_text(["alpha", "server"])},
            {"queue/PROJECTS.json": json_text(["local", "alpha"])},
        )

        self.assertEqual(json.loads(merged["queue/PROJECTS.json"]), ["local", "alpha", "server"])

    def test_normalize_rejects_untracked_paths(self):
        with self.assertRaises(InvalidPathError):
            normalize_files({"notes.txt": "nope"})

    def test_normalize_rejects_parent_directory_paths(self):
        with self.assertRaises(InvalidPathError):
            normalize_files({"queue/../completed/alpha.json": "[]\n"})


class SQLiteSnapshotStoreTests(unittest.TestCase):
    def test_put_snapshot_merges_stale_client_upload(self):
        with tempfile.TemporaryDirectory() as tempdir:
            store = SQLiteSnapshotStore(str(Path(tempdir) / "sync.sqlite3"))
            initial = store.get_snapshot("default")
            server_snapshot = store.put_snapshot(
                "default",
                initial.revision,
                {"queue/alpha.json": json_text([{"name": "server", "related": []}])},
            )

            merged = store.put_snapshot(
                "default",
                initial.revision,
                {"queue/beta.json": json_text([{"name": "local", "related": []}])},
            )

            self.assertNotEqual(merged.revision, server_snapshot.revision)
            self.assertIn("queue/alpha.json", merged.files)
            self.assertIn("queue/beta.json", merged.files)

    def test_put_snapshot_rejects_unknown_base_revision(self):
        with tempfile.TemporaryDirectory() as tempdir:
            store = SQLiteSnapshotStore(str(Path(tempdir) / "sync.sqlite3"))
            store.get_snapshot("default")

            with self.assertRaises(UnknownBaseRevisionError):
                store.put_snapshot("default", "missing", {})


if __name__ == "__main__":
    unittest.main()
