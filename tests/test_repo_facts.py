"""README file-structure facts: gitignore patterns and committed snapshots."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_gitignore_patterns_and_committed_snapshots():
    """Output files are gitignored (README file-structure note); the two
    committed exceptions — manifest.json and target_list_npi.xlsx — are
    checked-in snapshots of the last published run."""
    text = (ROOT / ".gitignore").read_text()
    for pattern in ("*.csv", "*.xlsx", "*.json"):
        assert pattern in text, f"missing gitignore pattern: {pattern}"
    for snapshot in ("manifest.json", "target_list_npi.xlsx"):
        assert (ROOT / snapshot).is_file(), f"missing committed snapshot: {snapshot}"
