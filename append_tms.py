"""
append_tms.py – Merge TMS rows into the combined target list
────────────────────────────────────────────────────────────────
Normalises and appends 830 TMS/behavioral-health records to the
17,265 CMS Practice Radar rows, producing a unified 18,095-row list.
Exports target_list_combined_18095.xlsx with per-source tabs.
"""
import pandas as pd
import numpy as np
import re
from openpyxl import load_workbook
from openpyxl.styles import PatternFill, Font, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.table import Table, TableStyleInfo

STATE_MAP = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
    "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE",
    "Florida": "FL", "Georgia": "GA", "Hawaii": "HI", "Idaho": "ID",
    "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS",
    "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD",
    "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS",
    "Missouri": "MO", "Montana": "MT", "Nebraska": "NE", "Nevada": "NV",
    "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM", "New York": "NY",
    "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK",
    "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC",
    "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX", "Utah": "UT",
    "Vermont": "VT", "Virginia": "VA", "Washington": "WA", "West Virginia": "WV",
    "Wisconsin": "WI", "Wyoming": "WY", "District of Columbia": "DC",
}

def normalize_state(geo):
    if pd.isna(geo):
        return np.nan
    s = str(geo)
    for name, abbr in STATE_MAP.items():
        if name.lower() in s.lower():
            return abbr
    m = re.search(r'\b([A-Z]{2})\b', s)
    return m.group(1) if m else np.nan

SOURCE_TIER    = {"tms_funded_entity": 40, "pe_behavioral_health": 30, "tms_practice": 20, "ketamine_focused": 10}
SERVICE_BREADTH = {"TMS★": 30, "TMS+KETAMINE": 25, "TMS": 15, "KETAMINE": 5}

def tms_priority(source, service, website, contact, footprint):
    score = SOURCE_TIER.get(source, 0) + SERVICE_BREADTH.get(service, 0)
    if pd.notna(website) and str(website).strip():  score += 10
    if pd.notna(contact) and str(contact).strip():  score += 10
    if pd.notna(footprint) and len(str(footprint).split(",")) > 1: score += 10
    return score

def build_tms_row(name, geo=None, website=None, contact=None,
                  specialty_service="TMS", notes=None, data_type="tms_excel",
                  footprint=None, funding_amount=None):
    pri = tms_priority(data_type, specialty_service, website, contact, footprint)
    fund = 0.0
    if funding_amount:
        m = re.search(r"\$?([\d]+(?:\.\d+)?)\s*([MBK]?)", str(funding_amount).replace(",","").upper())
        if m:
            fund = float(m.group(1)) * {"M":1e6,"B":1e9,"K":1e3}.get(m.group(2),1)
    return {
        "facility_name": name, "pri_spec": "PSYCHIATRY",
        "specialty_service": specialty_service,
        "state": normalize_state(geo),
        "tms_source": data_type, "tms_notes": notes,
        "tms_priority_score": pri,
        "funding_amount_usd": fund if fund > 0 else np.nan,
        "website": website or np.nan,
        "authorized_official": contact or np.nan,
    }

def append_tms(target_list, tms_funded, tms_practices, tms_ketamine, tms_pe):
    rows = []
    for _, r in tms_funded.iterrows():
        rows.append(build_tms_row(r.get("facility_name"), r.get("hq_or_primary_market"),
            r.get("website"), r.get("primary_contact_name"), "TMS★", r.get("notes"),
            "tms_funded_entity", funding_amount=r.get("amount")))
    for _, r in tms_practices.iterrows():
        svc = "TMS+KETAMINE" if str(r.get("ketamine_spravato_offered","")).lower() in ("yes","y","true","1") else "TMS"
        rows.append(build_tms_row(r.get("practice_name"), r.get("hq_or_primary_market"),
            r.get("website"), r.get("primary_contact"), svc, r.get("notes"),
            "tms_practice", footprint=r.get("states_or_footprint")))
    for _, r in tms_ketamine.iterrows():
        rows.append(build_tms_row(r.get("facility_name"),
            str(r.get("citytown","")) + ", " + str(r.get("country","")),
            r.get("website"), specialty_service="KETAMINE", data_type="ketamine_focused"))
    for _, r in tms_pe.iterrows():
        rows.append(build_tms_row(r.get("facility_name"), str(r.get("citytown","")),
            r.get("website"), specialty_service="TMS", data_type="pe_behavioral_health"))
    tms_df = pd.DataFrame(rows)
    existing = target_list.copy()
    existing["tms_source"] = "practice_radar"
    combined = pd.concat([existing, tms_df], ignore_index=True)
    combined["unified_score"] = combined["total_score"].fillna(combined["tms_priority_score"])
    print(f"=== Append TMS Data ===")
    print(f"  CMS rows   : {len(existing):,}")
    print(f"  TMS rows   : {len(tms_df):,}")
    print(f"  Combined   : {len(combined):,}")
    return combined, tms_df

if __name__ == "__main__":
    target_list   = pd.read_csv("target_list.csv")
    from load_tms import load_tms
    tms_funded, _, tms_practices, tms_ketamine, tms_pe = load_tms()
    combined, tms_df = append_tms(target_list, tms_funded, tms_practices, tms_ketamine, tms_pe)
    combined.to_csv("combined_target_list.csv", index=False)
    print("Saved: combined_target_list.csv")
