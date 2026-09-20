"""
nppes_enrich.py – NPPES NPI-2 enrichment for top 400 practices
──────────────────────────────────────────────────────────────────
Queries the NPPES REST API to fetch org NPI (NPI-2), authorized officials,
enumeration dates, websites, and FHIR endpoint data for the top 400
practices by size. Merges enrichment back onto all practices.
"""
import requests
import pandas as pd
import numpy as np
import time
import datetime
import re
from config import NPPES_URL, NPPES_LIMIT

def query_nppes(org_name, state, url=NPPES_URL, limit=NPPES_LIMIT):
    name = re.sub(r"[^A-Za-z0-9 &]", "", str(org_name))[:60].strip()
    if not name:
        return None
    try:
        r = requests.get(url, params={
            "version": "2.1", "enumeration_type": "NPI-2",
            "organization_name": name + "*", "state": state, "limit": limit,
        }, timeout=10)
        r.raise_for_status()
        results = r.json().get("results", [])
        return results[0] if results else None
    except Exception:
        return None

def enrich(practices, n_candidates=400):
    candidates = practices.nlargest(n_candidates, "size").copy()
    today = datetime.date.today()
    rows, hit = [], 0
    for _, row in candidates.iterrows():
        res = query_nppes(row["facility_name"], row["state"])
        rec = {"practice_key": row["practice_key"]}
        if res:
            hit += 1
            basic = res.get("basic", {})
            rec["npi_org"] = str(res.get("number", "")).strip() or np.nan
            ao = (basic.get("authorized_official_first_name", "") + " " +
                  basic.get("authorized_official_last_name", "")).strip()
            rec["authorized_official"] = ao
            enum_str = basic.get("enumeration_date", "")
            enum_date = None
            if enum_str:
                try:
                    enum_date = datetime.date.fromisoformat(str(enum_str)[:10])
                except ValueError:
                    pass
            rec["enumeration_date"]  = str(enum_date) if enum_date else ""
            rec["practice_age_yrs"]  = round((today - enum_date).days / 365.25, 1) if enum_date else np.nan
            addrs   = res.get("addresses", [{}])
            primary = next((a for a in addrs if a.get("address_purpose") == "LOCATION"), addrs[0] if addrs else {})
            rec["website"] = primary.get("website") or ""
            endpoints = res.get("endpoints", [])
            rec["has_endpoint"] = len(endpoints) > 0
            rec["fhir_url"]     = next((e.get("endpoint", "") for e in endpoints if "fhir" in str(e.get("endpoint","")).lower()), "")
            m = re.search(r"(?:https?://)?(?:www\.)?([^/\s]+)", rec["website"])
            rec["domain"] = m.group(1) if m else ""
        else:
            rec.update({"npi_org": np.nan, "authorized_official": "",
                        "enumeration_date": "", "practice_age_yrs": np.nan,
                        "website": "", "has_endpoint": False, "fhir_url": "", "domain": ""})
        rows.append(rec)
        time.sleep(0.08)
    enrichment = pd.DataFrame(rows)
    enriched = practices.merge(enrichment, on="practice_key", how="left")
    for c in ["authorized_official", "enumeration_date", "website", "fhir_url", "domain"]:
        enriched[c] = enriched[c].fillna("")
    enriched["npi_org"] = enriched.get("npi_org", np.nan)
    enriched["has_endpoint"] = enriched["has_endpoint"].fillna(False)
    enriched["practice_age_yrs"] = pd.to_numeric(enriched["practice_age_yrs"], errors="coerce")
    print(f"=== NPPES Enrich ===")
    print(f"  Candidates queried: {len(candidates):,}")
    print(f"  NPPES hits        : {hit:,}  ({hit/len(candidates):.0%})")
    print(f"  With npi_org      : {enriched['npi_org'].notna().sum():,}")
    return enriched

if __name__ == "__main__":
    practices = pd.read_csv("practices.csv")
    enriched = enrich(practices)
    enriched.to_csv("enriched_practices.csv", index=False)
    print("Saved: enriched_practices.csv")
