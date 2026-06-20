# Idea Queue Dashboard

Single-page Flask app for managing idea queues. Reads/writes JSON files under a configured data root.

## Setup

```
cd ~/projects/ideaq
uv run python web/app.py --data-root /path/to/idea-data
```

Open http://localhost:5050

The data root must contain the backing JSON directories:

- `queue/`
- `completed/`
- `projects/`

## Tests

```
cd ~/projects/ideaq
uv run python -m unittest discover -s web/tests -t .
```

The tests build a temporary repo fixture with `queue/` and `completed/` data and verify the JSON files after each backend endpoint call.

## Usage

### Editing ideas
- **Click any cell** to edit it inline (name, human_idea, description, difficulty, related)
- **Related** field is comma-separated; edits are saved on blur
- **Renaming** an idea automatically updates all `related` fields that reference it across all projects

### Prioritizing
- **Priority dropdown** in the last column: high / medium / low / none
- Rows are shaded by priority: purple (high), light blue (medium), yellow (low)
- **Sort** button per project, or **sort all by priority** in the toolbar

### Moving ideas between projects
- **Drag-and-drop**: grab the ☰ handle on any row and drag it to another project's table
- **Right-click** the ☰ handle to get a dropdown menu of projects — click one to move the idea there

### Filtering and collapsing
- **Filter checkboxes** in the toolbar let you show/hide ideas by priority level
- **Click a project name** to collapse/expand its table
- **Collapse all** / **expand all** buttons in the toolbar

### Project ordering
- The project list at the top of the page shows all projects with idea counts
- **Drag projects** in this list to reorder them — the tables below follow the same order
- Order is persisted in `queue/PROJECTS.json`

### Completing and deleting ideas
- Each row has four icons in the left column: ☰ (drag), ⊕/§ (project GOALS workflow), ✓ (complete), ✗ (delete)
- **✓ Complete** moves the idea from `queue/` to `completed/` (parallel JSON files)
- **✗ Delete** removes the idea with a 6-second **undo** toast at the bottom of the screen

### Project GOALS workflow
- **⊕** means `~/projects/<project>` does not exist yet; clicking it creates the directory, writes a `GOALS.md` section for only that selected idea, initializes a git repo, and publishes a new public GitHub repo with `gh`
- **§** means the project directory already exists; clicking it appends a new `GOALS.md` section for only that selected idea
- The dashboard reads project directory status on page load and updates the icon after creating a project repo

### Adding new items
- **+ idea** adds a blank idea to that project
- **+ project** creates a new empty project

### Saving to git
- **commit & push** button in the toolbar commits all changes and pushes to origin from the configured data root, if that data root is a git checkout

### Server sync
- **sync setup** prompts for the server URL, store ID, and bearer token, then saves them in browser `localStorage`
- **sync** flushes any pending delete, fetches the server snapshot, uploads local changes with the last synced local base snapshot, and replaces local JSON files with the server's canonical merged snapshot
- Sync base snapshots are stored under `~/.local/state/ideaq/` by default, not in the queue data repo

All changes save immediately to `queue/*.json`. Completed ideas go to `completed/*.json`.
