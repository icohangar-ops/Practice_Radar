"""
ingest.py – CMS Doctors & Clinicians API ingest
────────────────────────────────────────────────────
Fetches clinician-level records from the CMS Provider Data Catalog
(dataset mj5m-pzi6, DKAN datastore API) for every specialty × state
combination and deduplicates them into a single DataFrame.

Column names follow the live dataset (verified 2026-10-22):
  telehlth, facility_name, citytown, state, zip_code, telephone_number
replace the retired ind_enrlt_flg, org_lgl_nm, cty_st_zip,
nppes_provider_state, nppes_provider_zip and phn_numbr.
"""
import time

import pandas as pd
import requests

from config import SPECIALTIES, STATES, PDC_URL, PAGE_SIZE, PDC_TIMEOUT, PDC_RETRIES

# Columns the downstream stages rely on. Ingest fails loudly if CMS renames them
# again, instead of silently producing empty practice names or a zero telehealth score.
REQUIRED_COLUMNS = [
    "npi", "org_pac_id", "facility_name", "num_org_mem", "pri_spec", "grd_yr",
    "telehlth", "adr_ln_1", "citytown", "state", "zip_code", "telephone_number",
]


class IngestError(RuntimeError):
    """A segment could not be fetched completely."""


def _post_page(session, specialty, state, offset, page_size):
    body = {
        "limit": page_size,
        "offset": offset,
        "count": True,
        "results": True,
        "conditions": [
            {"property": "pri_spec", "value": specialty, "operator": "="},
            {"property": "state", "value": state, "operator": "="},
        ],
    }
    last_err = None
    for attempt in range(PDC_RETRIES):
        try:
            r = session.post(PDC_URL, json=body, timeout=PDC_TIMEOUT)
            r.raise_for_status()
            if "json" not in r.headers.get("Content-Type", ""):
                # The API answers some overload errors with an HTML "Temporarily Unavailable" page.
                raise IngestError(f"non-JSON response ({r.headers.get('Content-Type')})")
            data = r.json()
            return data.get("results", []), int(data.get("count", 0))
        except (requests.RequestException, ValueError, IngestError) as e:
            last_err = e
            time.sleep(min(2 ** attempt, 30))
    raise IngestError(f"{specialty} x {state} offset {offset}: {last_err}")


def fetch_segment(specialty, state, page_size=PAGE_SIZE, session=None):
    """Return every row for one specialty × state, or raise IngestError.

    Paging stops on the server-reported count, not on a short page, so a
    failed page can never truncate a segment without anyone noticing.
    """
    session = session or requests.Session()
    rows, offset, total = [], 0, None
    while total is None or offset < total:
        batch, total = _post_page(session, specialty, state, offset, page_size)
        if not batch:
            break
        rows.extend(batch)
        offset += len(batch)
    if total is not None and len(rows) < total:
        raise IngestError(f"{specialty} x {state}: got {len(rows)} of {total} rows")
    return rows


def ingest(specialties=SPECIALTIES, states=STATES):
    session = requests.Session()
    frames, failed = [], []
    for spec in specialties:
        for st in states:
            try:
                seg = fetch_segment(spec, st, session=session)
            except IngestError as e:
                print(f"  [FAIL] {e}")
                failed.append((spec, st))
                continue
            if seg:
                frames.append(pd.DataFrame(seg))
                print(f"  {spec} x {st}: {len(seg)} rows")
    if failed:
        raise IngestError(f"{len(failed)} segment(s) failed after retries: {failed[:5]}")
    clinicians = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame(columns=REQUIRED_COLUMNS)
    missing = [c for c in REQUIRED_COLUMNS if c not in clinicians.columns]
    if missing:
        raise IngestError(f"CMS dataset no longer has expected columns: {missing}")
    # Deduplicate by NPI + address
    clinicians = clinicians.drop_duplicates(
        subset=["npi", "adr_ln_1", "zip_code"]
    ).reset_index(drop=True)
    for col in ["grd_yr", "num_org_mem"]:
        clinicians[col] = pd.to_numeric(clinicians[col], errors="coerce")
    print(f"\nClinicians (deduped): {len(clinicians):,}")
    return clinicians


if __name__ == "__main__":
    clinicians = ingest()
    clinicians.to_csv("clinicians_raw.csv", index=False)
    print("Saved: clinicians_raw.csv")
