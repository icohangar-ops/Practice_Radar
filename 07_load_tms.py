"""
07_load_tms.py – Load TMS market data from Excel
──────────────────────────────────────────────────
Reads the manually curated TMS/behavioral-health Excel workbook and
returns 5 categorised DataFrames: funded entities, society key persons,
practices, ketamine-focused clinics, and PE-backed providers.

Expected file: tms_market_data.xlsx   (placed in working directory)
"""
import pandas as pd

SHEET_MAP = {
    "funded":   0,   # Sheet 1 – Funded entities
    "society":  1,   # Sheet 2 – Society key persons
    "practice": slice(2, 5),  # Sheets 3-5 – Practice lists (concat)
    "ketamine": 5,   # Sheet 6 – Ketamine-focused clinics
    "pe":       6,   # Sheet 7 – PE-backed behavioral health
}

def load_tms(path="tms_market_data.xlsx"):
    xl = pd.ExcelFile(path)
    tms_funded   = xl.parse(xl.sheet_names[0])
    tms_society  = xl.parse(xl.sheet_names[1])
    tms_practices = pd.concat(
        [xl.parse(xl.sheet_names[i]) for i in range(2, 5)],
        ignore_index=True
    ).drop_duplicates()
    tms_ketamine = xl.parse(xl.sheet_names[5])
    tms_pe       = xl.parse(xl.sheet_names[6])
    print("=== TMS Data Loaded ===")
    print(f"  Funded entities   : {len(tms_funded)} rows")
    print(f"  Society persons   : {len(tms_society)} rows")
    print(f"  Practices (deduped): {len(tms_practices)} rows")
    print(f"  Ketamine focused  : {len(tms_ketamine)} rows")
    print(f"  PE behavioral     : {len(tms_pe)} rows")
    return tms_funded, tms_society, tms_practices, tms_ketamine, tms_pe

if __name__ == "__main__":
    tms_funded, tms_society, tms_practices, tms_ketamine, tms_pe = load_tms()
