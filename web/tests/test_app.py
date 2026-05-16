import copy
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from web.app import create_app


PROJECT_ORDER = ["beta", "alpha"]

QUEUE_FIXTURE = {
    "alpha": [
        {
            "name": "alpha_one",
            "human_idea": "Alpha idea one",
            "description": "First alpha idea.",
            "difficulty": "S",
            "related": ["beta_shared"],
            "priority": "none",
        },
        {
            "name": "alpha_two",
            "human_idea": "Alpha idea two",
            "description": "Second alpha idea.",
            "difficulty": "M",
            "related": [],
            "priority": "low",
        },
    ],
    "beta": [
        {
            "name": "beta_shared",
            "human_idea": "Beta idea shared",
            "description": "Shared beta idea.",
            "difficulty": "L",
            "related": ["alpha_one"],
            "priority": "medium",
        },
        {
            "name": "beta_other",
            "human_idea": "Beta idea other",
            "description": "Another beta idea.",
            "difficulty": "S",
            "related": ["alpha_one"],
            "priority": "high",
        },
    ],
}

COMPLETED_FIXTURE = {
    "alpha": [
        {
            "name": "done_alpha",
            "human_idea": "Completed alpha idea",
            "description": "Completed already.",
            "difficulty": "S",
            "related": [],
            "priority": "none",
        }
    ]
}

DEFAULT_NEW_IDEA = {
    "name": "new_idea",
    "human_idea": "",
    "description": "",
    "difficulty": "S",
    "related": [],
    "priority": "none",
}


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def read_json(path):
    return json.loads(path.read_text())


class AppEndpointTests(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.repo_dir = Path(self.tempdir.name) / "repo"
        self.queue_dir = self.repo_dir / "queue"
        self.completed_dir = self.repo_dir / "completed"
        self.repo_dir.mkdir(parents=True)
        self.queue_dir.mkdir()
        self.completed_dir.mkdir()
        self._seed_repo()

        self.app = create_app(self.repo_dir)
        self.app.testing = True
        self.client = self.app.test_client()

    def tearDown(self):
        self.tempdir.cleanup()

    def test_create_app_uses_configured_data_root(self):
        self.assertEqual(Path(self.app.config["DATA_ROOT"]), self.repo_dir.resolve())
        self.assertEqual(Path(self.app.config["QUEUE_DIR"]), self.queue_dir.resolve())
        self.assertEqual(Path(self.app.config["COMPLETED_DIR"]), self.completed_dir.resolve())

    def _seed_repo(self):
        write_json(self.queue_dir / "PROJECTS.json", copy.deepcopy(PROJECT_ORDER))
        for project_name, ideas in QUEUE_FIXTURE.items():
            write_json(self.queue_dir / f"{project_name}.json", copy.deepcopy(ideas))
        for project_name, ideas in COMPLETED_FIXTURE.items():
            write_json(self.completed_dir / f"{project_name}.json", copy.deepcopy(ideas))

    def _queue_project(self, name):
        return read_json(self.queue_dir / f"{name}.json")

    def _completed_project(self, name):
        return read_json(self.completed_dir / f"{name}.json")

    def _projects_order(self):
        return read_json(self.queue_dir / "PROJECTS.json")

    def _git(self, *args, cwd=None):
        return subprocess.run(
            ["git", *args],
            cwd=cwd or self.repo_dir,
            check=True,
            capture_output=True,
            text=True,
        )

    def test_projects_endpoint_returns_queue_data(self):
        response = self.client.get("/api/projects")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), QUEUE_FIXTURE)

    def test_save_persists_each_supplied_project_file(self):
        new_state = copy.deepcopy(QUEUE_FIXTURE)
        new_state["alpha"].reverse()
        new_state["beta"][0]["priority"] = "high"

        response = self.client.post("/api/save", json=new_state)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(self._queue_project("alpha"), new_state["alpha"])
        self.assertEqual(self._queue_project("beta"), new_state["beta"])

    def test_update_idea_persists_simple_field_change(self):
        response = self.client.post(
            "/api/update_idea",
            json={
                "project": "beta",
                "index": 1,
                "field": "priority",
                "value": "none",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(self._queue_project("beta")[1]["priority"], "none")
        self.assertEqual(self._queue_project("alpha"), QUEUE_FIXTURE["alpha"])

    def test_update_idea_rename_updates_related_fields_everywhere(self):
        response = self.client.post(
            "/api/update_idea",
            json={
                "project": "alpha",
                "index": 0,
                "field": "name",
                "value": "alpha_renamed",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(self._queue_project("alpha")[0]["name"], "alpha_renamed")
        self.assertEqual(self._queue_project("beta")[0]["related"], ["alpha_renamed"])
        self.assertEqual(self._queue_project("beta")[1]["related"], ["alpha_renamed"])

    def test_move_idea_reorders_rows_within_a_project(self):
        response = self.client.post(
            "/api/move_idea",
            json={
                "from_project": "alpha",
                "from_index": 0,
                "to_project": "alpha",
                "to_index": 1,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(
            [idea["name"] for idea in self._queue_project("alpha")],
            ["alpha_two", "alpha_one"],
        )

    def test_move_idea_between_projects_updates_both_files(self):
        response = self.client.post(
            "/api/move_idea",
            json={
                "from_project": "alpha",
                "from_index": 1,
                "to_project": "beta",
                "to_index": 1,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(
            [idea["name"] for idea in self._queue_project("alpha")],
            ["alpha_one"],
        )
        self.assertEqual(
            [idea["name"] for idea in self._queue_project("beta")],
            ["beta_shared", "alpha_two", "beta_other"],
        )

    def test_new_project_creates_an_empty_queue_file(self):
        response = self.client.post("/api/new_project", json={"name": "gamma"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(self._queue_project("gamma"), [])

    def test_new_idea_appends_default_record(self):
        response = self.client.post("/api/new_idea", json={"project": "beta"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(self._queue_project("beta")[-1], DEFAULT_NEW_IDEA)

    def test_project_order_writes_projects_file(self):
        response = self.client.post("/api/project_order", json=["alpha", "beta"])

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(self._projects_order(), ["alpha", "beta"])

    def test_complete_idea_moves_queue_item_into_completed_file(self):
        response = self.client.post(
            "/api/complete_idea",
            json={"project": "alpha", "index": 1},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(
            [idea["name"] for idea in self._queue_project("alpha")],
            ["alpha_one"],
        )
        self.assertEqual(
            [idea["name"] for idea in self._completed_project("alpha")],
            ["done_alpha", "alpha_two"],
        )

    def test_delete_idea_removes_queue_item(self):
        response = self.client.post(
            "/api/delete_idea",
            json={"project": "beta", "index": 0},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"ok": True})
        self.assertEqual(
            [idea["name"] for idea in self._queue_project("beta")],
            ["beta_other"],
        )

    def test_git_commit_push_commits_dashboard_changes_and_updates_origin(self):
        remote_dir = Path(self.tempdir.name) / "remote.git"
        self._git("init", "--bare", str(remote_dir), cwd=self.tempdir.name)
        self._git("init", "-b", "main")
        self._git("config", "user.name", "Test User")
        self._git("config", "user.email", "test@example.com")
        self._git("remote", "add", "origin", str(remote_dir))
        self._git("add", "-A")
        self._git("commit", "-m", "Initial fixture")
        self._git("push", "-u", "origin", "main")

        update_response = self.client.post(
            "/api/update_idea",
            json={
                "project": "beta",
                "index": 0,
                "field": "priority",
                "value": "high",
            },
        )
        self.assertEqual(update_response.status_code, 200)

        response = self.client.post("/api/git_commit_push", json={})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.get_json(),
            {"ok": True, "message": "Committed and pushed"},
        )
        self.assertEqual(self._queue_project("beta")[0]["priority"], "high")
        self.assertEqual(self._git("status", "--porcelain").stdout.strip(), "")
        self.assertEqual(
            self._git("log", "-1", "--pretty=%s").stdout.strip(),
            "Update queues from dashboard",
        )
        self.assertEqual(
            self._git("rev-parse", "HEAD").stdout.strip(),
            self._git("--git-dir", str(remote_dir), "rev-parse", "refs/heads/main").stdout.strip(),
        )


if __name__ == "__main__":
    unittest.main()
