-- Practice Radar: staging (DuckDB SQL)
-- Business keys, hash keys and hash diffs for every source table.
-- Hash keys: sha256(upper(trim(bk))). load_dts comes from the run variable set by
-- run_duckdb.py (SET VARIABLE load_dts = ...), so every object in one load shares it.
-- This replaces the string key 'SOLO_<adr_ln_1>_<zip>' from practice_rollup.py.

CREATE SCHEMA IF NOT EXISTS practice_radar.cms_pdc__stg;
CREATE SCHEMA IF NOT EXISTS practice_radar.nppes_api__stg;
CREATE SCHEMA IF NOT EXISTS practice_radar.tms_xlsx__stg;

-- ── CMS clinician ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW practice_radar.cms_pdc__stg.clinician AS
WITH std AS (
  SELECT c.*,
    -- address standardisation: upper case, strip punctuation, collapse spaces, common USPS suffixes
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
      upper(trim(coalesce(adr_ln_1, ''))), '[^A-Z0-9 ]', '', 'g'), '\s+', ' ', 'g'),
      '\bSTREET\b', 'ST', 'g'), '\bAVENUE\b', 'AVE', 'g'), '\bSUITE\b', 'STE', 'g') AS std_adr_ln_1,
    substr(regexp_replace(coalesce(CAST(zip_code AS VARCHAR), ''), '[^0-9]', '', 'g'), 1, 5) AS std_zip5
  FROM practice_radar.cms_pdc.clinician c
  WHERE npi IS NOT NULL
),
keyed AS (
  SELECT std.*,
    sha256(concat_ws('||', std_adr_ln_1, std_zip5))                            AS location_key,
    CASE WHEN nullif(trim(CAST(org_pac_id AS VARCHAR)), '') IS NOT NULL THEN trim(CAST(org_pac_id AS VARCHAR))
         ELSE concat('SOLO|', sha256(concat_ws('||', std_adr_ln_1, std_zip5))) END AS practice_key
  FROM std
)
SELECT keyed.*,
  sha256(upper(trim(CAST(npi AS VARCHAR))))                                    AS provider_hk,
  sha256(upper(practice_key))                                                  AS practice_hk,
  sha256(upper(location_key))                                                  AS location_hk,
  sha256(concat_ws('||', upper(practice_key), upper(trim(CAST(npi AS VARCHAR)))))  AS practice_provider_hk,
  sha256(concat_ws('||', upper(practice_key), upper(location_key)))           AS practice_location_hk,
  sha256(concat_ws('||', upper(trim(CAST(npi AS VARCHAR))), upper(location_key))) AS provider_location_hk,
  getvariable('load_dts')                                                      AS load_dts,
  'CMS_PDC.clinician'                                                          AS record_source
FROM keyed;

-- ── NPPES lookup results ────────────────────────────────────────────
CREATE OR REPLACE VIEW practice_radar.nppes_api__stg.npi_registry_result AS
SELECT r.*,
  sha256(upper(trim(CAST(number AS VARCHAR))))                                 AS npi_hk,      -- provider_hk or organization_hk
  sha256(upper(trim(query_practice_key)))                                      AS practice_hk,
  sha256(concat_ws('||', upper(trim(query_practice_key)), upper(trim(CAST(number AS VARCHAR))))) AS practice_npi_lookup_hk,
  getvariable('load_dts')                                                      AS load_dts,
  'NPPES_API.npi_registry_result'                                              AS record_source
FROM practice_radar.nppes_api.npi_registry_result r
WHERE number IS NOT NULL AND query_practice_key IS NOT NULL;

-- ── TMS workbook sheets: 'TMS|' + normalised name (no stable id in the workbook) ──
-- BV_SAL_PRACTICE later links these to CMS practices on organization NPI or website domain.
CREATE OR REPLACE VIEW practice_radar.tms_xlsx__stg.tms_funded_entity AS
SELECT t.*, concat('TMS|', regexp_replace(upper(trim(facility_name)), '[^A-Z0-9]', '', 'g')) AS practice_key,
       getvariable('load_dts') AS load_dts, 'TMS_XLSX.tms_funded_entity' AS record_source
FROM practice_radar.tms_xlsx.tms_funded_entity t WHERE nullif(trim(facility_name), '') IS NOT NULL;

CREATE OR REPLACE VIEW practice_radar.tms_xlsx__stg.tms_practice AS
SELECT t.*, concat('TMS|', regexp_replace(upper(trim(practice_name)), '[^A-Z0-9]', '', 'g')) AS practice_key,
       getvariable('load_dts') AS load_dts, 'TMS_XLSX.tms_practice' AS record_source
FROM practice_radar.tms_xlsx.tms_practice t WHERE nullif(trim(practice_name), '') IS NOT NULL;

CREATE OR REPLACE VIEW practice_radar.tms_xlsx__stg.tms_ketamine_clinic AS
SELECT t.*, concat('TMS|', regexp_replace(upper(trim(facility_name)), '[^A-Z0-9]', '', 'g')) AS practice_key,
       getvariable('load_dts') AS load_dts, 'TMS_XLSX.tms_ketamine_clinic' AS record_source
FROM practice_radar.tms_xlsx.tms_ketamine_clinic t WHERE nullif(trim(facility_name), '') IS NOT NULL;

CREATE OR REPLACE VIEW practice_radar.tms_xlsx__stg.tms_pe_provider AS
SELECT t.*, concat('TMS|', regexp_replace(upper(trim(facility_name)), '[^A-Z0-9]', '', 'g')) AS practice_key,
       getvariable('load_dts') AS load_dts, 'TMS_XLSX.tms_pe_provider' AS record_source
FROM practice_radar.tms_xlsx.tms_pe_provider t WHERE nullif(trim(facility_name), '') IS NOT NULL;
