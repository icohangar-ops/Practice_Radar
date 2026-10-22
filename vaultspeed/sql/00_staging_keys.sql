-- Practice Radar: staging key derivation (Databricks SQL)
-- In VaultSpeed this logic goes into the source-object derived columns / BK expressions.
-- It replaces the string key 'SOLO_<adr_ln_1>_<cty_st_zip>' from practice_rollup.py.

CREATE SCHEMA IF NOT EXISTS practice_radar.cms_pdc__stg;

CREATE OR REPLACE VIEW practice_radar.cms_pdc__stg.clinician AS
WITH std AS (
  SELECT c.*,
    -- address standardisation: upper case, strip punctuation, collapse spaces, common USPS suffixes
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
      upper(trim(coalesce(adr_ln_1, ''))), '[^A-Z0-9 ]', ''), '\\s+', ' '),
      '\\bSTREET\\b', 'ST'), '\\bAVENUE\\b', 'AVE'), '\\bSUITE\\b', 'STE')   AS std_adr_ln_1,
    substr(regexp_replace(coalesce(nppes_provider_zip, ''), '[^0-9]', ''), 1, 5) AS std_zip5
  FROM practice_radar.cms_pdc.clinician c
)
SELECT
  std.*,
  sha2(concat_ws('||', std_adr_ln_1, std_zip5), 256)                          AS location_key,
  CASE WHEN nullif(trim(org_pac_id), '') IS NOT NULL THEN trim(org_pac_id)
       ELSE concat('SOLO|', sha2(concat_ws('||', std_adr_ln_1, std_zip5), 256)) END AS practice_key,
  sha2(upper(trim(npi)), 256)                                                 AS provider_hk,
  current_timestamp()                                                         AS load_dts,
  'CMS_PDC.clinician'                                                         AS record_source
FROM std
WHERE npi IS NOT NULL;

CREATE SCHEMA IF NOT EXISTS practice_radar.tms_xlsx__stg;

-- TMS practices: 'TMS|' + normalised name (no stable id in the workbook).
-- BV_SAL_PRACTICE later links these to CMS practices on NPI or website domain.
CREATE OR REPLACE VIEW practice_radar.tms_xlsx__stg.tms_practice AS
SELECT t.*,
  concat('TMS|', regexp_replace(upper(trim(practice_name)), '[^A-Z0-9]', '')) AS practice_key,
  current_timestamp() AS load_dts,
  'TMS_XLSX.tms_practice' AS record_source
FROM practice_radar.tms_xlsx.tms_practice t;
-- The same pattern applies to tms_funded_entity, tms_ketamine_clinic and tms_pe_provider (on facility_name).
