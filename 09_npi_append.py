"""
09_npi_append.py – NPI lookup and HubSpot export
──────────────────────────────────────────────────
Appends NPI (National Provider Identifier) data to every row:
  - CMS rows  : inherit npi_org (NPI-2) from NPPES Enrich; npi_individual from npi_sample
  - TMS rows  : live NPPES NPI-2 lookup by facility name + state
Adds npi_match_confidence + npi_review_flag columns.

Writes two HubSpot-ready Excel sheets into target_list_npi.xlsx:
  "HubSpot – Ready"       → NPI confirmed, safe to import
  "HubSpot – NPI Review"  → unmatched, needs manual lookup before import
"""
import requests
import pandas as pd
import numpy as np
import time
import re
import shutil
from openpyxl import load_workbook
from openpyxl.styles import PatternFill, Font, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.table import Table, TableStyleInfo

NPPES_API = "https://npiregistry.cms.hhs.gov/api/"

def lookup_npi2(org_name, state):
    clean = re.sub(r"[^A-Za-z0-9 &]", "", str(org_name))[:60].strip()
    if not clean:
        return None
    params = {"version": "2.1", "enumeration_type": "NPI-2",
              "organization_name": clean + "*", "limit": 3}
    if pd.notna(state) and str(state).strip():
        params["state"] = str(state).strip()
    try:
        r = requests.get(NPPES_API, params=params, timeout=12)
        r.raise_for_status()
        results = r.json().get("results", [])
        return str(results[0]["number"]) if results else None
    except Exception:
        return None

def npi_append(combined_target_list, wb_src="target_list_combined_18095.xlsx",
               wb_out="target_list_npi.xlsx"):
    df = combined_target_list.copy()

    # Seed CMS npi_org — already present from NPPES Enrich
    df["npi_org"] = df["npi_org"].apply(
        lambda x: str(int(float(x))) if pd.notna(x) and str(x).strip() not in ("","nan") else np.nan
    )
    df["npi_individual"] = pd.to_numeric(df.get("npi_sample", np.nan), errors="coerce").apply(
        lambda x: str(int(x)) if pd.notna(x) and x > 0 else np.nan
    )

    # TMS rows: live NPPES lookup
    tms_mask = df["tms_source"] != "practice_radar"
    tms_idx  = df[tms_mask & df["npi_org"].isna()].index.tolist()
    hits = 0
    print(f"Querying NPPES for {len(tms_idx)} TMS rows...")
    for i, idx in enumerate(tms_idx):
        row = df.loc[idx]
        npi = lookup_npi2(row.get("facility_name",""), row.get("state",""))
        if npi:
            df.at[idx, "npi_org"] = npi
            hits += 1
        if (i+1) % 100 == 0:
            print(f"  … {i+1}/{len(tms_idx)}  hits={hits}")
        time.sleep(0.1)
    if tms_idx:
        print(f"  Done: {hits}/{len(tms_idx)} ({hits/len(tms_idx):.0%})")

    # Confidence
    def confidence(r):
        has_org = pd.notna(r["npi_org"]) and str(r["npi_org"]).strip() not in ("","nan")
        has_ind = pd.notna(r["npi_individual"]) and str(r["npi_individual"]).strip() not in ("","nan")
        return "org_npi" if has_org else "individual_npi_only" if has_ind else "unmatched"
    df["npi_match_confidence"] = df.apply(confidence, axis=1)
    df["npi_review_flag"]      = df["npi_match_confidence"] == "unmatched"

    # HubSpot column mapping
    col_map = {
        "facility_name": "Company Name", "npi_org": "NPI (Organization NPI-2)",
        "npi_individual": "NPI (Individual NPI-1)", "npi_match_confidence": "NPI Match Confidence",
        "npi_review_flag": "NPI Review Required", "state": "State/Region",
        "citytown": "City", "zip_code": "Postal Code", "adr_ln_1": "Street Address",
        "telephone_number": "Phone Number", "website": "Website",
        "pri_spec": "Primary Specialty", "specialty_service": "Specialty Service",
        "authorized_official": "Contact Name", "unified_score": "Practice Radar Score",
        "score_source": "Score Source", "tms_source": "Data Source",
        "tms_notes": "Notes", "funding_amount_usd": "Funding Amount (USD)",
    }
    hs_cols = [c for c in col_map if c in df.columns]
    hs_df   = df[hs_cols].rename(columns=col_map)
    hs_ready  = hs_df[~hs_df["NPI Review Required"]].copy()
    hs_review = hs_df[hs_df["NPI Review Required"]].copy()

    print(f"\n=== NPI Append ===")
    print(f"  Total rows          : {len(df):,}")
    for lbl, cnt in df["npi_match_confidence"].value_counts().items():
        print(f"  {lbl:<25}: {cnt:>6,}  ({cnt/len(df):.0%})")
    print(f"\n  HubSpot – Ready     : {len(hs_ready):,} rows")
    print(f"  HubSpot – NPI Review: {len(hs_review):,} rows")

    # Write to Excel
    shutil.copy(wb_src, wb_out)
    wb = load_workbook(wb_out)
    for sn in ["HubSpot – Ready", "HubSpot – NPI Review"]:
        if sn in wb.sheetnames:
            del wb[sn]

    def write_sheet(wb, data, sheet_name, hdr_color):
        ws = wb.create_sheet(sheet_name)
        ws.sheet_view.showGridLines = False
        WHITE = "FBFBFF"
        for ci, col in enumerate(data.columns, 1):
            c = ws.cell(row=1, column=ci, value=col)
            c.fill = PatternFill("solid", fgColor=hdr_color)
            c.font = Font(color=WHITE, bold=True, name="Calibri", size=10)
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        ws.row_dimensions[1].height = 24
        ws.freeze_panes = "A2"
        for ri, (_, row) in enumerate(data.iterrows(), 2):
            for ci, val in enumerate(row, 1):
                if isinstance(val, (bool, np.bool_)):
                    cell_val = bool(val)
                elif pd.isna(val):
                    cell_val = None
                elif isinstance(val, (int, float, str)):
                    cell_val = val
                else:
                    cell_val = str(val)
                ws.cell(row=ri, column=ci, value=cell_val)
        mr, mc = ws.max_row, ws.max_column
        if mr > 1:
            tname = "Tbl_" + re.sub(r"[^A-Za-z0-9]", "_", sheet_name)[:30]
            tbl = Table(displayName=tname, ref=f"A1:{get_column_letter(mc)}{mr}")
            tbl.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
            ws.add_table(tbl)
        for col_cells in ws.columns:
            max_len = max((len(str(c.value)) if c.value else 0) for c in col_cells)
            ws.column_dimensions[get_column_letter(col_cells[0].column)].width = min(max_len + 2, 40)

    write_sheet(wb, hs_ready,  "HubSpot – Ready",      "17B26A")
    write_sheet(wb, hs_review, "HubSpot – NPI Review", "F04438")
    wb.save(wb_out)
    print(f"  Saved: {wb_out}  ({len(wb.sheetnames)} sheets)")
    return df, hs_ready, hs_review

if __name__ == "__main__":
    combined = pd.read_csv("combined_target_list.csv")
    npi_append(combined)
