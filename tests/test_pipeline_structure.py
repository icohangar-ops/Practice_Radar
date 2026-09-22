"""Entry-point claims: run_pipeline resolves, stages import, README names real files."""
import ast
import importlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STAGE_MODULES = [
    "config",
    "ingest",
    "practice_rollup",
    "nppes_enrich",
    "score",
    "publish",
    "load_tms",
    "append_tms",
    "npi_append",
    "cover_memo",
]


def test_run_pipeline_imports_resolve():
    """The [Data]-review finding was run_pipeline importing absent modules; PR #3
    renamed the stages. This pins the repair: run_pipeline imports every stage it
    orchestrates (cover_memo stays optional, matching the README's note)."""
    importlib.import_module("run_pipeline")
    tree = ast.parse((ROOT / "run_pipeline.py").read_text())
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
        elif isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
    missing = [m for m in STAGE_MODULES if m != "cover_memo" and m not in imported]
    assert not missing, f"run_pipeline.py no longer imports: {missing}"


def test_stage_modules_import():
    """Every stage named in the README pipeline architecture exists and imports."""
    for name in STAGE_MODULES:
        importlib.import_module(name)


def test_readme_file_structure_lists_real_files():
    """The README File structure block names files that exist in the tree."""
    text = (ROOT / "README.md").read_text()
    block = text.split("## File structure", 1)[1].split("```", 2)[1]
    names = [line.strip().lstrip("├─└│ ").strip() for line in block.splitlines()]
    names = [n for n in names if n and not n.endswith("/")]
    assert names, "file-structure block not found in README"
    for name in names:
        assert (ROOT / name).exists(), f"README file structure names a missing file: {name}"
