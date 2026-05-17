import tempfile
import unittest
from pathlib import Path

from server.app import create_app
from server.sync_core import json_text


class SyncServerAppTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.app = create_app(Path(self.tempdir.name) / "sync.sqlite3", token="secret")
        self.app.testing = True
        self.client = self.app.test_client()

    def tearDown(self):
        self.tempdir.cleanup()

    def auth_headers(self):
        return {"Authorization": "Bearer secret"}

    def test_snapshot_requires_bearer_auth(self):
        response = self.client.get("/v1/stores/default/snapshot")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.get_json()["error"], "missing bearer token")

    def test_get_snapshot_creates_empty_store(self):
        response = self.client.get("/v1/stores/default/snapshot", headers=self.auth_headers())

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["files"], {})
        self.assertTrue(response.get_json()["revision"])

    def test_put_snapshot_returns_new_revision(self):
        initial = self.client.get("/v1/stores/default/snapshot", headers=self.auth_headers()).get_json()

        response = self.client.put(
            "/v1/stores/default/snapshot",
            headers=self.auth_headers(),
            json={
                "base_revision": initial["revision"],
                "files": {"queue/alpha.json": json_text([{"name": "alpha_one", "related": []}])},
            },
        )

        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertNotEqual(data["revision"], initial["revision"])
        self.assertIn("queue/alpha.json", data["files"])

    def test_put_snapshot_rejects_unknown_base_revision(self):
        response = self.client.put(
            "/v1/stores/default/snapshot",
            headers=self.auth_headers(),
            json={"base_revision": "missing", "files": {}},
        )

        self.assertEqual(response.status_code, 409)
        self.assertIn("unknown base revision", response.get_json()["error"])

    def test_put_snapshot_uses_client_base_files_for_server_merge(self):
        initial = self.client.get("/v1/stores/default/snapshot", headers=self.auth_headers()).get_json()
        server_response = self.client.put(
            "/v1/stores/default/snapshot",
            headers=self.auth_headers(),
            json={
                "base_revision": initial["revision"],
                "files": {"queue/server.json": json_text([{"name": "server", "related": []}])},
                "client_base_files": {},
            },
        ).get_json()

        merged_response = self.client.put(
            "/v1/stores/default/snapshot",
            headers=self.auth_headers(),
            json={
                "base_revision": server_response["revision"],
                "files": {"queue/local.json": json_text([{"name": "local", "related": []}])},
                "client_base_files": {},
            },
        )

        self.assertEqual(merged_response.status_code, 200)
        self.assertIn("queue/server.json", merged_response.get_json()["files"])
        self.assertIn("queue/local.json", merged_response.get_json()["files"])


if __name__ == "__main__":
    unittest.main()
