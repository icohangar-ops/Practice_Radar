"""
run_pipeline.py – Practice Radar end-to-end runner
────────────────────────────────────────────────────
Executes all 10 pipeline steps in order. Requires:
  - Python 3.10+
  - pip install -r requirements.txt
  - tms_market_data.xlsx in the working directory

Usage:
    python run_pipeline.py
"""
import sys
from config               import SPECIALTIES, STATES, SPECIALTY_SERVICES, WEIGHTS, SIZE_FIT_TARGET, SIZE_TIERS, PDC_URL, NPPES_URL, PAGE_SIZE, NPPES_LIMIT, SCHEMA_VERSION, RUN_ID
from ingest               import ingest
from practice_rollup      import rollup
from nppes_enrich         import enrich
from score                import score
from publish              import publish
from load_tms             import load_tms
from append_tms           import append_tms
from npi_append           import npi_append
# from cover_memo         import add_cover_memo  # optional

def run():
    print("\n" + "="*60)
    print("  PRACTICE RADAR PIPELINE")
    print("="*60)

    # 1. Ingest
    clinicians = ingest()

    # 2. Rollup
    practices = rollup(clinicians)

    # 3. Enrich
    enriched = enrich(practices)

    # 4. Score
    scored = score(enriched)

    # 5. Publish
    target_list, manifest = publish(scored, clinicians, practices, enriched)

    # 6. Load TMS
    tms_funded, tms_society, tms_practices, tms_ketamine, tms_pe = load_tms()

    # 7. Append TMS
    combined, tms_df = append_tms(target_list, tms_funded, tms_practices, tms_ketamine, tms_pe)

    # 8. NPI Append + HubSpot export
    npi_df, hs_ready, hs_review = npi_append(combined)

    print("\n" + "="*60)
    print("  PIPELINE COMPLETE")
    print(f"  Output : target_list_npi.xlsx")
    print(f"  HubSpot-Ready   : {len(hs_ready):,} rows")
    print(f"  HubSpot-Review  : {len(hs_review):,} rows")
    print("="*60 + "\n")

if __name__ == "__main__":
    run()
