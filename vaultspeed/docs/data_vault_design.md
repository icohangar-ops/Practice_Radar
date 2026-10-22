# Practice Radar on VaultSpeed: Data Vault design

Target: Databricks (Delta), catalog/database `practice_radar`.
Business model: `nppes_provider_registry` in the Enterprise Context Store (11 entities, 13 relations; Practice, Practice Score and NPI Match extended with Funding Amount USD, Score Source, Reviewer and Reviewed At).

VaultSpeed generates the load code for the Raw Vault from the source metadata and the business model.
The SQL in `../sql/` is the target design that the generated objects should match, and it can be used to
review the shape of the vault. It is not a hand-coded replacement for the generated code.

## 1. Layers

| Layer | Schema | Tier | Purpose |
|---|---|---|---|
| Source | `cms_pdc` | SOURCE | CMS Doctors & Clinicians API rows, landed as-is |
| Source | `nppes_api` | SOURCE | NPI Registry API v2.1 results, flattened, one row per returned NPI |
| Source | `tms_xlsx` | SOURCE | TMS workbook, one table per sheet |
| Staging | `cms_pdc__stg`, `nppes_api__stg`, `tms_xlsx__stg` | INTERMEDIATE | Hash keys, hash diffs, load date, record source, standardised address |
| Raw Vault | `pr_rdv` | SILVER | Hubs, links and satellites, source-specific and insert-only |
| Business Vault | `pr_bv` | SILVER | Rollup, scoring, NPI match decisions, same-as links, PITs and bridges |
| Mart | `pr_mart` | GOLD | Dimensions, score fact, HubSpot target list, NPI review queue |

## 2. Source tables

| Source system | Table | Grain | Replaces |
|---|---|---|---|
| CMS_PDC | `clinician` | clinician x address | `ingest.py` → `clinicians_raw.csv` |
| NPPES_API | `npi_registry_result` | lookup x returned NPI | `nppes_enrich.py`, `npi_append.py` |
| TMS_XLSX | `tms_funded_entity`, `tms_practice`, `tms_ketamine_clinic`, `tms_pe_provider` | one row per sheet row | `load_tms.py` (the society sheet is not used by the pipeline and is left out) |

## 3. Business keys

| Hub | Business key | Rule |
|---|---|---|
| HUB_PROVIDER | NPI (NPI-1) | `clinician.npi`, or `npi_registry_result.number` where `enumeration_type = 'NPI-1'` |
| HUB_ORGANIZATION | Org NPI (NPI-2) | `npi_registry_result.number` where `enumeration_type = 'NPI-2'` |
| HUB_PRACTICE | Practice Key | CMS: `org_pac_id`. CMS solo: `SOLO|` + Location Key. TMS: `TMS|` + normalised facility name. Each source keeps its own key, and BV_SAL_PRACTICE resolves duplicates. |
| HUB_LOCATION | Location Key | SHA-256 of the standardised address (upper case, punctuation stripped, USPS abbreviations, ZIP5). This replaces the raw `SOLO_<adr>_<zip>` string. |
| HUB_TAXONOMY | Taxonomy Code | NUCC code, filled from the NPPES bulk file / API `taxonomies[]` (phase 2) |

All hash keys are `sha2(upper(trim(bk)), 256)`, and composite keys are joined with `||`. Every row carries `load_dts` and `record_source`.

## 4. Raw Vault (`pr_rdv`)

### Hubs
| Object | Sources |
|---|---|
| HUB_PROVIDER | cms_pdc.clinician, nppes_api.npi_registry_result |
| HUB_ORGANIZATION | nppes_api.npi_registry_result |
| HUB_PRACTICE | cms_pdc.clinician, tms_xlsx.* |
| HUB_LOCATION | cms_pdc.clinician |
| HUB_TAXONOMY | NPPES bulk / API (phase 2) |

### Links
| Object | Hubs | Business relation | Source |
|---|---|---|---|
| LNK_PRACTICE_PROVIDER | Practice, Provider | Practice employs Provider | clinician |
| LNK_PRACTICE_LOCATION | Practice, Location | Practice operates at Location | clinician |
| LNK_PROVIDER_LOCATION | Provider, Location | Provider practices at Location | clinician |
| LNK_PRACTICE_NPI_LOOKUP | Practice, Organization | Practice has NPI Match (the raw API candidate) | npi_registry_result |
| LNK_PROVIDER_ORGANIZATION | Provider, Organization | Provider is affiliated with Organization | NPPES (phase 2) |
| LNK_PROVIDER_TAXONOMY | Provider, Taxonomy | Provider has Taxonomy | NPPES (phase 2) |

### Satellites
Satellites are split by source, because each source has its own change rate and quality.

| Satellite | Parent | Attributes |
|---|---|---|
| SAT_PROVIDER_CMS_PDC | HUB_PROVIDER | names, gndr, cred, med_sch, grd_yr, pri_spec, sec_spec_all, telehlth, ind_assgn |
| SAT_PROVIDER_NPPES | HUB_PROVIDER | names, credential, enumeration_date, website, endpoint_url |
| SAT_PRACTICE_CMS_PDC | HUB_PRACTICE | facility_name, num_org_mem, telephone_number |
| SAT_PRACTICE_TMS_FUNDED | HUB_PRACTICE | hq_or_primary_market, website, primary_contact_name, notes, amount |
| SAT_PRACTICE_TMS_PRACTICE | HUB_PRACTICE | hq_or_primary_market, website, primary_contact, notes, states_or_footprint, ketamine_spravato_offered |
| SAT_PRACTICE_TMS_KETAMINE | HUB_PRACTICE | citytown, country, website |
| SAT_PRACTICE_TMS_PE | HUB_PRACTICE | citytown, website |
| SAT_LOCATION_CMS_PDC | HUB_LOCATION | adr_ln_1, citytown, state, zip_code |
| SAT_ORGANIZATION_NPPES | HUB_ORGANIZATION | organization_name, authorized official, enumeration_date, address_state, website, endpoint_url |
| SAT_LNK_PRACTICE_NPI_LOOKUP | LNK_PRACTICE_NPI_LOOKUP | query_org_name, query_state, result_rank, enumeration_type |
| SAT_LNK_PRACTICE_PROVIDER | LNK_PRACTICE_PROVIDER | membership_source |

### Reference tables (versioned, replacing `config.py`)
| Object | Content | Replaces |
|---|---|---|
| REF_SCORE_CRITERION | criterion_code, weight_points, ideal_range_min/max, effective_from | `WEIGHTS`, `SIZE_FIT_TARGET` |
| REF_SIZE_TIER | tier, min_size, max_size | `SIZE_TIERS` |
| REF_SERVICE_KEYWORD | service (ABA / KETAMINE), keyword | `SPECIALTY_SERVICES` |
| REF_DATA_SOURCE | source_code, category, source_tier_points | `SOURCE_TIER` in `append_tms.py` |
| REF_SERVICE_BREADTH | service, points | `SERVICE_BREADTH` |

## 5. Business Vault (`pr_bv`)

The derived logic moves out of pandas into the Business Vault, where it is versioned and lineage-traceable.

| Object | Type | Logic | Replaces |
|---|---|---|---|
| BV_SAT_PRACTICE_ROLLUP | computed sat on HUB_PRACTICE | size, n_sites, telehealth_share, median_grad_yr, median_exp_yrs, is_solo, is_multi_site, size_tier, specialty_service | `practice_rollup.py` |
| BV_SAT_PRACTICE_SCORE | computed sat on HUB_PRACTICE, keyed by score_run_id | six component scores, total, criterion version used | `score.py` |
| BV_SAT_PRACTICE_TMS_PRIORITY | computed sat | tms_priority_score, funding_amount_usd | `append_tms.py` |
| BV_SAT_PRACTICE_NPI_MATCH | computed sat on HUB_PRACTICE | matched org/individual NPI, confidence (org_npi, individual_npi_only, unmatched), method, review status | `npi_append.py` |
| BV_SAL_PRACTICE | same-as link | TMS practice ↔ CMS practice when the NPI or website domain matches | the manual merge in `append_tms.py` |
| PIT_PRACTICE | point-in-time | snapshot per load date across all practice sats | |
| BRIDGE_PRACTICE_PROVIDER | bridge | practice → provider → location for fast mart builds | |

Improvements over the current pipeline:
- **Enrichment covers every practice.** It no longer stops at the top 400 by size. Lookups are incremental, so only new or changed practices are queried.
- **Match decisions are kept as data.** A steward's confirm or reject is written back to the review status and reused on the next run, so it doesn't have to be redone.
- **Scores are reproducible.** Every score row records the criterion version, so two weightings can be compared side by side.
- **Recency is normalised per score run.** It is no longer recomputed against whatever rows happen to be in memory.

## 6. Marts (`pr_mart`) and data products

| Object | Grain | Data product |
|---|---|---|
| DIM_PRACTICE (SCD2) | practice version | |
| DIM_PROVIDER (SCD2) | provider version | |
| FCT_PRACTICE_SCORE | practice x score run | |
| MART_HUBSPOT_TARGET_LIST | practice, latest run, NPI-confirmed | `practice_radar_hubspot_target_list` |
| MART_NPI_REVIEW_QUEUE | unmatched practice | `practice_radar_npi_review_queue` |

The HubSpot column names stay the same as the current export (`Company Name`, `NPI (Organization NPI-2)`, …), so the import mapping in HubSpot needs no change.

## 7. Column-to-vault mapping (summary)

| Source column | Vault object | Business attribute |
|---|---|---|
| clinician.npi | HUB_PROVIDER | Provider.NPI |
| clinician.grd_yr | SAT_PROVIDER_CMS_PDC | Provider.Graduation Year |
| clinician.telehlth | SAT_PROVIDER_CMS_PDC | Provider.Telehealth Enrollment Flag |
| clinician.pri_spec | SAT_PROVIDER_CMS_PDC | Provider.CMS Primary Specialty |
| clinician.org_pac_id | HUB_PRACTICE | Practice.Practice Key |
| clinician.facility_name | SAT_PRACTICE_CMS_PDC | Practice.Facility Name |
| clinician.num_org_mem | SAT_PRACTICE_CMS_PDC | Practice.Practice Size (reported) |
| clinician.telephone_number | SAT_PRACTICE_CMS_PDC | Practice.Telephone Number |
| clinician.adr_ln_1, citytown, state, zip_code | HUB_LOCATION / SAT_LOCATION_CMS_PDC | Location.* |
| npi_registry_result.number (NPI-2) | HUB_ORGANIZATION | Organization.Organization Identifier |
| npi_registry_result.organization_name | SAT_ORGANIZATION_NPPES | Organization.Organization Name |
| npi_registry_result.authorized_official_* | SAT_ORGANIZATION_NPPES | Provider.Authorized Official Name |
| npi_registry_result.enumeration_date | SAT_ORGANIZATION_NPPES | Practice.Practice Age Years (derived in BV) |
| npi_registry_result.website, endpoint_url | SAT_ORGANIZATION_NPPES | Website, FHIR Endpoint URL |
| tms_*.facility_name / practice_name | HUB_PRACTICE (`TMS|` key) | Practice.Facility Name |
| tms_practice.ketamine_spravato_offered | SAT_PRACTICE_TMS_PRACTICE | Practice.Specialty Service Signal |

The authoritative attribute-level mapping is stored in the Enterprise Context Store as entity and attribute implementations.

## 8. Source schema check (live `mj5m-pzi6`, verified 2026-10-22)
The design uses the live CMS column names. The original `ingest.py` breaks against today's API:

| Original pipeline | Live dataset | Impact on the original pipeline |
|---|---|---|
| `https://data.cms.gov/resource/mj5m-pzi6.json` | `https://data.cms.gov/provider-data/api/1/datastore/query/mj5m-pzi6/0` | Old endpoint returns **HTTP 410 Gone**, so ingest gets no rows |
| `ind_enrlt_flg` (telehealth) | `telehlth` (`Y` or blank) | Telehealth share was always 0 |
| `org_lgl_nm` | `facility_name` | Practice names were empty |
| `cty_st_zip` | `citytown` (city only) | |
| `nppes_provider_state` | `state` | The state filter in `fetch_segment` matched nothing |
| `nppes_provider_zip` | `zip_code` (ZIP+4, 9 digits) | Staging takes the first 5 digits |
| `phn_numbr` | `telephone_number` | Contactability lost its phone half |

The live dataset also provides `provider_first_name`, `provider_last_name`, `provider_middle_name`, `suff`, `gndr`, `cred`, `med_sch`, `sec_spec_all`, `ind_pac_id`, `adr_ln_2`, `adrs_id`, `ind_assgn` and `grp_assgn`. These columns are now registered, and the identity fields are mapped to Provider.

In a sample of 500 psychiatry rows, about 51% had `telehlth = 'Y'` and about 11% had no `org_pac_id` (solo clinicians).
