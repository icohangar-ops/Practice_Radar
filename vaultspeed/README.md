# Practice Radar on VaultSpeed

This folder rebuilds the Practice Radar pipeline (`ingest.py` → `practice_rollup.py` → `nppes_enrich.py` → `score.py` → `append_tms.py` → `npi_append.py`) as a governed Data Vault on **DuckDB**. The structure (sources, layers, business model, mappings, data products) is managed in the VaultSpeed Enterprise Context Store; the DuckDB SQL in `sql/` is the load code, and `run_duckdb.py` runs it end to end.

## Contents
| Path | What it is |
|---|---|
| `docs/data_vault_design.md` | Layers, business keys, hubs, links, satellites, Business Vault, marts |
| `docs/column_mapping.csv` | Source column → business attribute mapping, with confidence |
| `docs/business_model.html` | Business model diagram (ER + entity cards), generated from the Enterprise Context Store |
| `run_duckdb.py` | Loads the sources into DuckDB, runs `sql/` in order, exports the marts |
| `sql/00_staging_keys.sql` | Staging for all sources: address standardisation, business keys, hash keys |
| `sql/01_raw_vault_ddl.sql` | Raw Vault tables and reference data (replaces `config.py`), idempotent |
| `sql/01b_raw_vault_load.sql` | Insert-only hub, link and satellite loads (hash-diff change detection) |
| `sql/02_business_vault.sql` | Rollup, scoring, TMS priority and NPI match logic in SQL |
| `sql/02b_bv_sal_pit_bridge.sql` | Same-as link (TMS ↔ CMS practice dedup), PIT_PRACTICE, BRIDGE_PRACTICE_PROVIDER |
| `sql/03_marts.sql` | HubSpot target list and NPI review queue |

## Run it

```bash
pip install -r requirements.txt
python ingest.py                                   # live CMS pull -> clinicians_raw.csv
python vaultspeed/run_duckdb.py --clinicians clinicians_raw.csv \
    --tms tms_market_data.xlsx --fetch-npi 400     # -> practice_radar.duckdb + out/*.csv
```

`out/mart_hubspot_target_list.csv` is the HubSpot import (same headers as today) and
`out/mart_npi_review_queue.csv` is the steward queue. `out/npi_registry_result.csv` keeps every
NPPES candidate; pass it back with `--npi-results` so the next run only looks up new practices.
Steward decisions go into `pr_bv.npi_review_decision` (practice_hk, decided_npi,
review_status, reviewer, reviewed_at) and are applied on every later run.

Re-running is safe: hubs, links and satellites are insert-only and only take new keys or
changed hash diffs; each run adds one score run to `pr_bv.bv_sat_practice_score`.
`tests/test_vault_duckdb.py` runs the whole chain offline in CI.

**Verified on live data (2026-10-22, Rhode Island, 3 specialties):** 370 clinician rows →
78 practices, 253 providers. Where practice size agrees, all six score components match the
pandas pipeline exactly; the only differences come from size now counting distinct clinicians.

## What is registered in the Enterprise Context Store
- **Business model:** `nppes_provider_registry`, 11 entities and 13 relations, in the domains "Healthcare Provider Registry" and "Commercial Targeting".
- **Source systems:** `CMS_PDC`, `NPPES_API`, `TMS_XLSX`.
- **Layers** (database `practice_radar`): `cms_pdc`, `nppes_api`, `tms_xlsx`, their `__stg` counterparts, `pr_rdv`, `pr_bv` and `pr_mart`.
- **Source tables:** `clinician`, `npi_registry_result`, `tms_funded_entity`, `tms_practice`, `tms_ketamine_clinic`, `tms_pe_provider`.
- **Mapping:** 12 entity implementations and 50 column mappings (48 linked to business attributes, 2 metadata-only), mapped against the live CMS schema.
- **Business keys:** proposed UNIQUE constraints on all six source tables, waiting to be confirmed by profiling.
- **Data products** (DRAFT, preferred layer `pr_mart`, human approval required for contracts):
  - `practice_radar_hubspot_target_list`: ranked, NPI-confirmed, with the score documented as a semantic metric.
  - `practice_radar_npi_review_queue`: unmatched practices for stewardship, highest score first.

## Improvements over the script pipeline
- History is kept. Scores, practices and matches are insert-only and versioned, so nothing is overwritten.
- Scoring weights, size tiers and service keywords are versioned reference data instead of constants in `config.py`.
- NPI enrichment covers every practice, not just the top 400. Steward decisions are stored and reused on later runs.
- Practice identity uses a standardised address hash instead of a raw `SOLO_<address>_<zip>` string.
- TMS rows are a separate source with provenance, rather than a one-off Excel merge.
- Lineage runs from each HubSpot column back to the API field it came from.

## Open points
1. **Resolved:** the telehealth field is `telehlth`, and the CMS column names were checked against the live `mj5m-pzi6` schema. The original `ingest.py` endpoint returns HTTP 410 and six of its column names no longer exist. See `docs/data_vault_design.md` §8.
2. Profile a real load, then confirm or reject the proposed business-key constraints.
3. VaultSpeed's documentation does not list DuckDB as a generation target, so the DuckDB load SQL here is maintained by hand. Check with VaultSpeed before relying on generated code for this platform.
4. Register the mart objects, then generate the data contracts.
