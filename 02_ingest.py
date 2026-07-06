"""
02_ingest.py – CMS Doctors & Clinicians API ingest
────────────────────────────────────────────────────
Fetches clinician-level records from the CMS PDC API for every
specialty × state combination and deduplicates into a single DataFrame.
"""
import requests
import pandas as pd
import time
from config import SPECIALTIES, STATES, PDC_URL, PAGE_SIZE

def fetch_segment(specialty, state, page_size=PAGE_SIZE):
    rows, offset = [], 0
    while True:
        try:
            r = requests.get(PDC_URL, params={
                "pri_spec": specialty, "nppes_provider_state": state,
                "$limit": page_size, "$offset": offset,
            }, timeout=30)
            r.raise_for_status()
            batch = r.json()
        except Exception as e:
            print(f"  [WARN] {specialty} x {state} offset {offset}: {e}")
            break
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
        time.sleep(0.05)
    return rows

def ingest():
    frames = []
    for spec in SPECIALTIES:
        for st in STATES:
            seg = fetch_segment(spec, st)
            if seg:
                frames.append(pd.DataFrame(seg))
                print(f"  {spec} x {st}: {len(seg)} rows")
            time.sleep(0.05)
    clinicians = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    # Deduplicate by NPI + address
    clinicians = clinicians.drop_duplicates(
        subset=["npi", "adr_ln_1", "cty_st_zip"]
    ).reset_index(drop=True)
    for col in ["grd_yr", "num_org_mem"]:
        if col in clinicians.columns:
            clinicians[col] = pd.to_numeric(clinicians[col], errors="coerce")
    print(f"\nClinicians (deduped): {len(clinicians):,}")
    return clinicians

if __name__ == "__main__":
    clinicians = ingest()
    clinicians.to_csv("clinicians_raw.csv", index=False)
    print("Saved: clinicians_raw.csv")
