#!/usr/bin/env python3
"""verify_target_list.py — deterministic checks over the committed workbook.

Stdlib-only (zipfile + ElementTree), no network, no pandas. Verifies the
claims bound in evidence/matrix.yaml against the committed snapshot
``target_list_npi.xlsx`` and exits non-zero on the first mismatch.

Evidence rows served: C004 (18,095 = 17,265 + 830), C009 (sheet inventory
and row counts), C010 (CMS score range 4.8-71.8, mean 28.5), C011 (TMS
priority score within 0-100), C012 (CMS individual-NPI coverage ~100%),
C013 (TMS org-NPI matches 365/830 = 44%).
"""
import hashlib
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

WORKBOOK = Path("target_list_npi.xlsx")
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_ID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"

# Claim C009: required sheets and their exact published row counts.
REQUIRED_SHEET_ROWS = {
    "HubSpot \u2013 Ready": 17630,
    "HubSpot \u2013 NPI Review": 465,
    "All Targets": 18095,
    "Practice Radar": 17265,
    "TMS Appended": 830,
}
# Claim C009: the five per-source tabs.
PER_SOURCE_TABS = (
    "CMS Practice Radar",
    "TMS Funded Entity",
    "TMS Practice",
    "Ketamine Focused",
    "PE Behavioral Health",
)

failures = []


def check(label, ok, detail=""):
    mark = "PASS" if ok else "FAIL"
    print(f"  [{mark}] {label}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(f"{label}" + (f" — {detail}" if detail else ""))


def cell_value(cell, shared):
    value = cell.find("m:v", NS)
    if value is None:
        return None
    if cell.get("t") == "s":
        return shared[int(value.text)]
    return value.text


def read_sheet(sheet_xml, shared):
    """Yield {header: value} dicts for one worksheet."""
    rows = sheet_xml.findall("m:sheetData/m:row", NS)
    headers = []
    if rows:
        for cell in rows[0].iter("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c"):
            headers.append(cell_value(cell, shared) or "")
    for row in rows[1:]:
        record = {}
        for cell in row.findall("m:c", NS):
            column = re.match(r"([A-Z]+)", cell.get("r")).group(1)
            index = 0
            for char in column:
                index = index * 26 + ord(char) - 64
            if 0 < index <= len(headers):
                record[headers[index - 1]] = cell_value(cell, shared)
        yield record


def numeric_values(sheet_xml, shared, column_name):
    values = []
    for record in read_sheet(sheet_xml, shared):
        raw = record.get(column_name)
        if raw is None or str(raw).strip() == "":
            continue
        try:
            values.append(float(raw))
        except ValueError:
            failures.append(f"non-numeric value in column {column_name!r}: {raw!r}")
    return values


def main():
    if not WORKBOOK.is_file():
        print(f"FAIL: committed workbook not found: {WORKBOOK}")
        return 1

    digest = hashlib.sha256(WORKBOOK.read_bytes()).hexdigest()
    print(f"target_list_npi.xlsx sha256: {digest}")

    archive = zipfile.ZipFile(WORKBOOK)
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    relmap = {rel.get("Id"): rel.get("Target") for rel in rels}
    try:
        strings_xml = ET.fromstring(archive.read("xl/sharedStrings.xml"))
        shared = [
            "".join(
                node.text or ""
                for node in item.iter("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t")
            )
            for item in strings_xml
        ]
    except KeyError:
        shared = []

    sheet_paths = {}
    sheet_names = []
    for sheet in workbook.find("m:sheets", NS):
        name = sheet.get("name")
        sheet_names.append(name)
        sheet_paths[name] = "xl/" + relmap[sheet.get(REL_ID)].lstrip("/")

    # C009 — sheet inventory and exact row counts.
    for name, expected_rows in REQUIRED_SHEET_ROWS.items():
        if name not in sheet_paths:
            check(f"sheet {name!r} present", False)
            continue
        rows = ET.fromstring(archive.read(sheet_paths[name])).findall("m:sheetData/m:row", NS)
        check(
            f"sheet {name!r} has {expected_rows:,} rows",
            len(rows) - 1 == expected_rows,
            f"found {len(rows) - 1:,}",
        )
    for name in PER_SOURCE_TABS:
        check(f"per-source tab {name!r} present", name in sheet_paths)

    # C010 — CMS score range/mean on the Practice Radar sheet.
    if "Practice Radar" in sheet_paths:
        scores = numeric_values(ET.fromstring(archive.read(sheet_paths["Practice Radar"])), shared, "total_score")
        check("Practice Radar total_score: 17,265 scored rows", len(scores) == 17265, f"found {len(scores):,}")
        if scores:
            check(
                "CMS scores range 4.8–71.8",
                min(scores) == 4.8 and max(scores) == 71.8,
                f"found {min(scores)}–{max(scores)}",
            )
            check(
                "CMS mean score 28.5 (to 1 decimal)",
                round(sum(scores) / len(scores), 1) == 28.5,
                f"found {sum(scores) / len(scores):.4f}",
            )

    # C011 — TMS priority score within 0-100.
    if "TMS Appended" in sheet_paths:
        priorities = numeric_values(ET.fromstring(archive.read(sheet_paths["TMS Appended"])), shared, "tms_priority_score")
        check("TMS Appended: 830 priority-scored rows", len(priorities) == 830, f"found {len(priorities):,}")
        if priorities:
            check(
                "TMS priority scores within 0–100",
                min(priorities) >= 0 and max(priorities) <= 100,
                f"found {min(priorities)}–{max(priorities)}",
            )

    # C012 / C013 — NPI coverage across the two HubSpot sheets.
    cms_rows, cms_with_individual, tms_rows, tms_with_org = 0, 0, 0, 0
    for name in ("HubSpot \u2013 Ready", "HubSpot \u2013 NPI Review"):
        if name not in sheet_paths:
            continue
        for record in read_sheet(ET.fromstring(archive.read(sheet_paths[name])), shared):
            source = record.get("Data Source")
            if source == "practice_radar":
                cms_rows += 1
                individual = record.get("NPI (Individual NPI-1)")
                if individual is not None and str(individual).strip():
                    cms_with_individual += 1
            else:
                tms_rows += 1
                org = record.get("NPI (Organization NPI-2)")
                if org is not None and str(org).strip():
                    tms_with_org += 1
    check("CMS-origin rows across HubSpot sheets: 17,265", cms_rows == 17265, f"found {cms_rows:,}")
    coverage = cms_with_individual / cms_rows if cms_rows else 0.0
    check(
        "CMS individual-NPI-1 coverage ~100% (>= 99%)",
        coverage >= 0.99,
        f"found {cms_with_individual:,}/{cms_rows:,} ({coverage:.1%})",
    )
    check("TMS-origin rows across HubSpot sheets: 830", tms_rows == 830, f"found {tms_rows:,}")
    check(
        "TMS org-NPI-2 matches: 365/830 (44%)",
        tms_with_org == 365,
        f"found {tms_with_org:,}/830 ({tms_with_org / 830:.0%})" if tms_rows else "",
    )

    if failures:
        print(f"\nTARGET LIST: FAILED ({len(failures)} check(s) failed)")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("\nTARGET LIST: VERIFIED — committed workbook matches every pinned value")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
