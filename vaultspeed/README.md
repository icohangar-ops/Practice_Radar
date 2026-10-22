# Practice Radar on VaultSpeed

This folder rebuilds the Practice Radar pipeline (`ingest.py` → `practice_rollup.py` → `nppes_enrich.py` → `score.py` → `append_tms.py` → `npi_append.py`) as a governed Data Vault on Databricks. The structure is managed in the VaultSpeed Enterprise Context Store, and VaultSpeed generates the load code.

## Contents
| Path | What it is |
|---|---|
| `docs/data_vault_design.md` | Layers, business keys, hubs, links, satellites, Business Vault, marts |
| `docs/column_mapping.csv` | Source column → business attribute mapping, with confidence |
| `sql/00_staging_keys.sql` | Address standardisation, plus practice and location key derivation |
| `sql/01_raw_vault_ddl.sql` | Raw Vault target shape and reference tables (replaces `config.py`) |
| `sql/02_business_vault.sql` | Rollup, scoring, TMS priority and NPI match logic in SQL |
| `sql/03_marts.sql` | HubSpot target list and NPI review queue |

The SQL is the reference target design. It has not been executed yet: no warehouse connection is linked to the `practice_radar` layers.

## What is registered in the Enterprise Context Store
- **Business model:** `nppes_provider_registry`, 11 entities and 13 relations, in the domains "Healthcare Provider Registry" and "Commercial Targeting".
- **Source systems:** `CMS_PDC`, `NPPES_API`, `TMS_XLSX`.
- **Layers** (database `practice_radar`): `cms_pdc`, `nppes_api`, `tms_xlsx`, their `__stg` counterparts, `pr_rdv`, `pr_bv` and `pr_mart`.
- **Source tables:** `clinician`, `npi_registry_result`, `tms_funded_entity`, `tms_practice`, `tms_ketamine_clinic`, `tms_pe_provider`.
- **Mapping:** 12 entity implementations and 41 attribute mappings.
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
1. Confirm the telehealth source field (`ind_enrlt_flg` vs `telehlth`).
2. Confirm the CMS column names against the live `mj5m-pzi6` schema.
3. Link a Databricks connection to the `practice_radar` layers, then generate and deploy.
4. Register the mart objects, then generate the data contracts.
