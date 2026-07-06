"""
10_cover_memo.py – Cover Memo Excel sheet
──────────────────────────────────────────
Injects a professionally formatted Cover Memo as the first sheet of
target_list_npi.xlsx with pipeline metadata, KPI tiles, data-source
notes, scoring methodology, and a sheet guide.
"""
import pandas as pd
import numpy as np
from datetime import datetime
from openpyxl import load_workbook
from openpyxl.styles import PatternFill, Font, Alignment
from openpyxl.utils import get_column_letter

DARK_BG  = "1D1D20"
CARD_BG  = "2F2F35"
WHITE    = "FBFBFF"
GOLD     = "FFD400"
GREEN    = "17B26A"
CORAL    = "F04438"
ACCENT   = "A1C9F4"
LAVENDER = "D0BBFF"

def add_cover_memo(wb_path, total_rows, ready_rows, review_rows, run_id):
    wb = load_workbook(wb_path)
    if "Cover Memo" in wb.sheetnames:
        del wb["Cover Memo"]
    ws = wb.create_sheet("Cover Memo", 0)
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 4
    ws.column_dimensions["B"].width = 30
    ws.column_dimensions["C"].width = 50

    def cell(row, col, value, fg=WHITE, bg=None, bold=False, size=11, align="left"):
        c = ws.cell(row=row, column=col, value=value)
        c.font = Font(color=fg, bold=bold, name="Calibri", size=size)
        c.alignment = Alignment(horizontal=align, vertical="center", wrap_text=True)
        if bg:
            c.fill = PatternFill("solid", fgColor=bg)
        return c

    # Title
    ws.merge_cells("B1:C1")
    cell(1, 2, "PRACTICE RADAR — Target List", fg=GOLD, bg=DARK_BG, bold=True, size=16, align="center")
    ws.row_dimensions[1].height = 36

    cell(2, 2, f"Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}   Run ID: {run_id}",
         fg="909094", bg=DARK_BG, size=9, align="center")
    ws.merge_cells("B2:C2")

    # KPI tiles
    tiles = [
        ("Total Facilities", f"{total_rows:,}",  ACCENT),
        ("HubSpot Ready",    f"{ready_rows:,}",  GREEN),
        ("NPI Review Needed",f"{review_rows:,}", CORAL),
    ]
    for i, (label, val, color) in enumerate(tiles):
        r = 4 + i * 2
        cell(r,   2, label, fg="909094", bg=CARD_BG, size=9)
        cell(r+1, 2, val,   fg=color,    bg=CARD_BG, size=18, bold=True, align="center")
        ws.merge_cells(f"B{r}:C{r}")
        ws.merge_cells(f"B{r+1}:C{r+1}")

    # Sheet guide
    cell(12, 2, "SHEET GUIDE", fg=GOLD, bg=DARK_BG, bold=True, size=10)
    ws.merge_cells("B12:C12")
    guide = [
        ("HubSpot – Ready",      "NPI confirmed — safe to import to HubSpot"),
        ("HubSpot – NPI Review", "Unmatched NPI — manual lookup required before import"),
        ("All Targets",          "All 18,095 facilities ranked by unified score"),
        ("Practice Radar",       "17,265 CMS-sourced practices (ENT, SLP, Psychiatry)"),
        ("TMS Appended",         "830 TMS / behavioral-health rows from market research"),
    ]
    for j, (sheet, desc) in enumerate(guide, 13):
        cell(j, 2, sheet, fg=ACCENT, bold=True, size=9)
        cell(j, 3, desc,  fg=WHITE,  size=9)

    # NPI methodology note
    cell(20, 2, "NPI METHODOLOGY", fg=GOLD, bg=DARK_BG, bold=True, size=10)
    ws.merge_cells("B20:C20")
    note = (
        "CMS rows inherit NPI-2 from NPPES Enrich (top 400 by size). "
        "TMS rows are matched live via NPPES NPI-2 API by facility name + state. "
        "Confidence levels: org_npi (NPI-2 confirmed) → individual_npi_only (NPI-1 from CMS) → unmatched. "
        "Do NOT import unmatched rows to HubSpot without manual NPI verification."
    )
    ws.merge_cells("B21:C21")
    cell(21, 2, note, fg="909094", size=9)
    ws.row_dimensions[21].height = 48

    wb.save(wb_path)
    print(f"=== Cover Memo ===")
    print(f"  Added to  : {wb_path}")
    print(f"  Sheets    : {wb.sheetnames}")

if __name__ == "__main__":
    add_cover_memo(
        wb_path="target_list_npi.xlsx",
        total_rows=18095, ready_rows=17630, review_rows=465,
        run_id="manual_run"
    )
