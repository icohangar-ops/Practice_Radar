"""
publish.py – Export scored target list + pipeline manifest
──────────────────────────────────────────────────────────────
Writes target_list.csv and manifest.json to the working directory.
"""
import pandas as pd
import json
import datetime
from config import (SPECIALTIES, STATES, SPECIALTY_SERVICES,
                    PDC_URL, NPPES_URL, PAGE_SIZE, WEIGHTS,
                    SIZE_FIT_TARGET, SCHEMA_VERSION, RUN_ID)

def publish(scored_practices, clinicians, practices, enriched_practices):
    target_list = scored_practices.copy()
    target_list.to_csv("target_list.csv", index=False)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "run_id":         RUN_ID,
        "generated_at":   datetime.datetime.utcnow().isoformat() + "Z",
        "sources": {
            "cms_pdc": {"url": PDC_URL, "page_size": PAGE_SIZE, "specialties": SPECIALTIES, "states": STATES},
            "nppes":   {"url": NPPES_URL, "candidates": 400},
        },
        "scoring_weights": WEIGHTS,
        "size_fit_target": list(SIZE_FIT_TARGET),
        "row_counts": {
            "clinicians":          len(clinicians),
            "practices":           len(practices),
            "enriched_practices":  len(enriched_practices),
            "target_list":         len(target_list),
        },
        "npi_org_populated": int(target_list["npi_org"].notna().sum()),
    }
    with open("manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)
    print("=== Publish ===")
    print(f"  target_list.csv: {len(target_list):,} rows x {len(target_list.columns)} cols")
    print(f"  manifest.json  : written  (schema v{SCHEMA_VERSION})")
    return target_list, manifest

if __name__ == "__main__":
    clinicians  = pd.read_csv("clinicians_raw.csv")
    practices   = pd.read_csv("practices.csv")
    enriched    = pd.read_csv("enriched_practices.csv")
    scored      = pd.read_csv("scored_practices.csv")
    publish(scored, clinicians, practices, enriched)
