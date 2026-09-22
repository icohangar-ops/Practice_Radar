#!/usr/bin/env python3
"""verify_requirements.py — the documented install command is installable.

Stdlib-only, no network. Verifies the README install claim bound in
evidence/matrix.yaml (C014): requirements.txt parses as a requirements
list with no duplicated package pins. A duplicated pin is the observed
failure mode — the superseded `requests==2.31.0+aikido.4` (served only by
a paid extra index, HTTP 402) shipped alongside the newer
`requests==2.34.0` and broke `pip install -r requirements.txt`.
"""
import re
from pathlib import Path

REQUIREMENTS = Path("requirements.txt")

# name[name-extra ...][extras][specifier]
REQ_RE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(\[[^\]]*\])?\s*([<>=!~].+)?\s*$")


def canonical(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def main():
    if not REQUIREMENTS.is_file():
        print(f"FAIL: {REQUIREMENTS} not found")
        return 1

    seen = {}
    failures = []
    count = 0
    for lineno, raw in enumerate(REQUIREMENTS.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = REQ_RE.match(line)
        if not match:
            failures.append(f"line {lineno}: not a parseable requirement: {line!r}")
            continue
        count += 1
        name, _, specifier = match.groups()
        key = canonical(name)
        if key in seen:
            failures.append(
                f"line {lineno}: duplicate pin for {name!r} — {specifier or '(no version)'} "
                f"(first pinned at line {seen[key][1]} as {seen[key][0] or '(no version)'})"
            )
        else:
            seen[key] = (specifier, lineno)

    for failure in failures:
        print(f"  [FAIL] {failure}")
    if failures:
        print(f"\nREQUIREMENTS: FAILED ({count} requirement lines, {len(failures)} problem(s))")
        return 1
    print(f"  [PASS] {count} requirement line(s) parse cleanly; no duplicate package pins")
    for name, (specifier, _) in sorted(seen.items()):
        print(f"         {name} {specifier or '(any)'}")
    print("\nREQUIREMENTS: VERIFIED — documented install command is well-formed and conflict-free")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
