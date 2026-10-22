-- Practice Radar: Raw Vault load (DuckDB SQL)
-- Insert-only and idempotent. Hubs and links add unseen keys only; satellites
-- add a row only when the hash diff differs from the current row.
-- Run after 00_staging_keys.sql and 01_raw_vault_ddl.sql, with load_dts set.

-- ── Hubs ────────────────────────────────────────────────────────────
INSERT INTO practice_radar.pr_rdv.hub_provider
SELECT provider_hk, trim(CAST(npi AS VARCHAR)), load_dts, record_source
FROM practice_radar.cms_pdc__stg.clinician s
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.hub_provider h WHERE h.provider_hk = s.provider_hk)
QUALIFY row_number() OVER (PARTITION BY provider_hk ORDER BY npi) = 1;

INSERT INTO practice_radar.pr_rdv.hub_provider
SELECT npi_hk, trim(CAST(number AS VARCHAR)), load_dts, record_source
FROM practice_radar.nppes_api__stg.npi_registry_result s
WHERE enumeration_type = 'NPI-1'
  AND NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.hub_provider h WHERE h.provider_hk = s.npi_hk)
QUALIFY row_number() OVER (PARTITION BY npi_hk ORDER BY number) = 1;

INSERT INTO practice_radar.pr_rdv.hub_organization
SELECT npi_hk, trim(CAST(number AS VARCHAR)), load_dts, record_source
FROM practice_radar.nppes_api__stg.npi_registry_result s
WHERE enumeration_type = 'NPI-2'
  AND NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.hub_organization h WHERE h.organization_hk = s.npi_hk)
QUALIFY row_number() OVER (PARTITION BY npi_hk ORDER BY number) = 1;

INSERT INTO practice_radar.pr_rdv.hub_practice
SELECT practice_hk, practice_key, load_dts, record_source FROM (
  SELECT practice_hk, practice_key, load_dts, record_source FROM practice_radar.cms_pdc__stg.clinician
  UNION ALL SELECT sha256(upper(practice_key)), practice_key, load_dts, record_source FROM practice_radar.tms_xlsx__stg.tms_funded_entity
  UNION ALL SELECT sha256(upper(practice_key)), practice_key, load_dts, record_source FROM practice_radar.tms_xlsx__stg.tms_practice
  UNION ALL SELECT sha256(upper(practice_key)), practice_key, load_dts, record_source FROM practice_radar.tms_xlsx__stg.tms_ketamine_clinic
  UNION ALL SELECT sha256(upper(practice_key)), practice_key, load_dts, record_source FROM practice_radar.tms_xlsx__stg.tms_pe_provider
) s
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.hub_practice h WHERE h.practice_hk = s.practice_hk)
QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY record_source) = 1;

INSERT INTO practice_radar.pr_rdv.hub_location
SELECT location_hk, location_key, load_dts, record_source
FROM practice_radar.cms_pdc__stg.clinician s
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.hub_location h WHERE h.location_hk = s.location_hk)
QUALIFY row_number() OVER (PARTITION BY location_hk ORDER BY location_key) = 1;

-- ── Links ───────────────────────────────────────────────────────────
INSERT INTO practice_radar.pr_rdv.lnk_practice_provider
SELECT practice_provider_hk, practice_hk, provider_hk, load_dts, record_source
FROM practice_radar.cms_pdc__stg.clinician s
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.lnk_practice_provider l WHERE l.practice_provider_hk = s.practice_provider_hk)
QUALIFY row_number() OVER (PARTITION BY practice_provider_hk ORDER BY npi) = 1;

INSERT INTO practice_radar.pr_rdv.lnk_practice_location
SELECT practice_location_hk, practice_hk, location_hk, load_dts, record_source
FROM practice_radar.cms_pdc__stg.clinician s
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.lnk_practice_location l WHERE l.practice_location_hk = s.practice_location_hk)
QUALIFY row_number() OVER (PARTITION BY practice_location_hk ORDER BY npi) = 1;

INSERT INTO practice_radar.pr_rdv.lnk_provider_location
SELECT provider_location_hk, provider_hk, location_hk, load_dts, record_source
FROM practice_radar.cms_pdc__stg.clinician s
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.lnk_provider_location l WHERE l.provider_location_hk = s.provider_location_hk)
QUALIFY row_number() OVER (PARTITION BY provider_location_hk ORDER BY npi) = 1;

INSERT INTO practice_radar.pr_rdv.lnk_practice_npi_lookup
SELECT practice_npi_lookup_hk, practice_hk, npi_hk, load_dts, record_source
FROM practice_radar.nppes_api__stg.npi_registry_result s
WHERE enumeration_type = 'NPI-2'
  AND NOT EXISTS (SELECT 1 FROM practice_radar.pr_rdv.lnk_practice_npi_lookup l WHERE l.practice_npi_lookup_hk = s.practice_npi_lookup_hk)
QUALIFY row_number() OVER (PARTITION BY practice_npi_lookup_hk ORDER BY result_rank) = 1;

-- ── Satellites (insert when hash diff changes) ──────────────────────
-- Pattern: stage the new rows with their hash diff, keep those whose diff differs
-- from the latest row of the same parent key.
INSERT INTO practice_radar.pr_rdv.sat_provider_cms_pdc
WITH src AS (
  SELECT provider_hk, load_dts,
         sha256(concat_ws('||', provider_first_name, provider_last_name, provider_middle_name, suff, gndr, cred,
                          med_sch, grd_yr, pri_spec, sec_spec_all, telehlth, ind_assgn)) AS hash_diff,
         record_source, provider_first_name, provider_last_name, provider_middle_name, suff, gndr, cred,
         med_sch, TRY_CAST(grd_yr AS INT), pri_spec, sec_spec_all, telehlth, ind_assgn
  FROM practice_radar.cms_pdc__stg.clinician
  QUALIFY row_number() OVER (PARTITION BY provider_hk ORDER BY adr_ln_1, zip_code) = 1
), cur AS (
  SELECT provider_hk, hash_diff FROM practice_radar.pr_rdv.sat_provider_cms_pdc
  QUALIFY row_number() OVER (PARTITION BY provider_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (provider_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_provider_nppes
WITH src AS (
  SELECT npi_hk AS provider_hk, load_dts,
         sha256(concat_ws('||', enumeration_date, website, endpoint_url)) AS hash_diff,
         record_source, NULL::VARCHAR, NULL::VARCHAR, NULL::VARCHAR,
         TRY_CAST(enumeration_date AS DATE), website, endpoint_url
  FROM practice_radar.nppes_api__stg.npi_registry_result
  WHERE enumeration_type = 'NPI-1'
  QUALIFY row_number() OVER (PARTITION BY npi_hk ORDER BY result_rank) = 1
), cur AS (
  SELECT provider_hk, hash_diff FROM practice_radar.pr_rdv.sat_provider_nppes
  QUALIFY row_number() OVER (PARTITION BY provider_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (provider_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_practice_cms_pdc
WITH src AS (
  SELECT practice_hk, load_dts,
         sha256(concat_ws('||', facility_name, num_org_mem, telephone_number)) AS hash_diff,
         record_source, facility_name, TRY_CAST(num_org_mem AS INT), telephone_number
  FROM (SELECT c.*, count(*) OVER (PARTITION BY practice_hk, facility_name) AS name_cnt
        FROM practice_radar.cms_pdc__stg.clinician c)
  -- practice attributes vary per clinician row; keep the most common name, as the pandas mode() did
  QUALIFY row_number() OVER (PARTITION BY practice_hk
                             ORDER BY name_cnt DESC, facility_name, telephone_number) = 1
), cur AS (
  SELECT practice_hk, hash_diff FROM practice_radar.pr_rdv.sat_practice_cms_pdc
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_location_cms_pdc
WITH src AS (
  SELECT location_hk, load_dts,
         sha256(concat_ws('||', adr_ln_1, citytown, state, zip_code)) AS hash_diff,
         record_source, adr_ln_1, citytown, state, CAST(zip_code AS VARCHAR)
  FROM practice_radar.cms_pdc__stg.clinician
  QUALIFY row_number() OVER (PARTITION BY location_hk ORDER BY adr_ln_1, citytown) = 1
), cur AS (
  SELECT location_hk, hash_diff FROM practice_radar.pr_rdv.sat_location_cms_pdc
  QUALIFY row_number() OVER (PARTITION BY location_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (location_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_organization_nppes
WITH src AS (
  SELECT npi_hk AS organization_hk, load_dts,
         sha256(concat_ws('||', organization_name, authorized_official_first_name, authorized_official_last_name,
                          enumeration_date, address_state, website, endpoint_url)) AS hash_diff,
         record_source, organization_name, authorized_official_first_name, authorized_official_last_name,
         TRY_CAST(enumeration_date AS DATE), address_state, website, endpoint_url
  FROM practice_radar.nppes_api__stg.npi_registry_result
  WHERE enumeration_type = 'NPI-2'
  QUALIFY row_number() OVER (PARTITION BY npi_hk ORDER BY result_rank) = 1
), cur AS (
  SELECT organization_hk, hash_diff FROM practice_radar.pr_rdv.sat_organization_nppes
  QUALIFY row_number() OVER (PARTITION BY organization_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (organization_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_lnk_practice_npi_lookup
WITH src AS (
  SELECT practice_npi_lookup_hk, load_dts,
         sha256(concat_ws('||', query_org_name, query_state, result_rank, enumeration_type)) AS hash_diff,
         record_source, query_org_name, query_state, TRY_CAST(result_rank AS INT), enumeration_type
  FROM practice_radar.nppes_api__stg.npi_registry_result
  WHERE enumeration_type = 'NPI-2'
  QUALIFY row_number() OVER (PARTITION BY practice_npi_lookup_hk ORDER BY result_rank) = 1
), cur AS (
  SELECT practice_npi_lookup_hk, hash_diff FROM practice_radar.pr_rdv.sat_lnk_practice_npi_lookup
  QUALIFY row_number() OVER (PARTITION BY practice_npi_lookup_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_npi_lookup_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_lnk_practice_provider
WITH src AS (
  SELECT practice_provider_hk, load_dts,
         sha256(CASE WHEN practice_key LIKE 'SOLO|%' THEN 'cms_pdc_solo' ELSE 'cms_pdc_group' END) AS hash_diff,
         record_source, CASE WHEN practice_key LIKE 'SOLO|%' THEN 'cms_pdc_solo' ELSE 'cms_pdc_group' END
  FROM practice_radar.cms_pdc__stg.clinician
  QUALIFY row_number() OVER (PARTITION BY practice_provider_hk ORDER BY npi) = 1
), cur AS (
  SELECT practice_provider_hk, hash_diff FROM practice_radar.pr_rdv.sat_lnk_practice_provider
  QUALIFY row_number() OVER (PARTITION BY practice_provider_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_provider_hk)
WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

-- TMS sheets
INSERT INTO practice_radar.pr_rdv.sat_practice_tms_funded
WITH src AS (
  SELECT sha256(upper(practice_key)) AS practice_hk, load_dts,
         sha256(concat_ws('||', facility_name, hq_or_primary_market, website, primary_contact_name, notes, amount)) AS hash_diff,
         record_source, facility_name, hq_or_primary_market, website, primary_contact_name, notes, CAST(amount AS VARCHAR)
  FROM practice_radar.tms_xlsx__stg.tms_funded_entity
  QUALIFY row_number() OVER (PARTITION BY practice_key ORDER BY facility_name) = 1
), cur AS (
  SELECT practice_hk, hash_diff FROM practice_radar.pr_rdv.sat_practice_tms_funded
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_hk) WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_practice_tms_practice
WITH src AS (
  SELECT sha256(upper(practice_key)) AS practice_hk, load_dts,
         sha256(concat_ws('||', practice_name, hq_or_primary_market, website, primary_contact, notes,
                          states_or_footprint, ketamine_spravato_offered)) AS hash_diff,
         record_source, practice_name, hq_or_primary_market, website, primary_contact, notes,
         states_or_footprint, CAST(ketamine_spravato_offered AS VARCHAR)
  FROM practice_radar.tms_xlsx__stg.tms_practice
  QUALIFY row_number() OVER (PARTITION BY practice_key ORDER BY practice_name) = 1
), cur AS (
  SELECT practice_hk, hash_diff FROM practice_radar.pr_rdv.sat_practice_tms_practice
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_hk) WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_practice_tms_ketamine
WITH src AS (
  SELECT sha256(upper(practice_key)) AS practice_hk, load_dts,
         sha256(concat_ws('||', facility_name, citytown, country, website)) AS hash_diff,
         record_source, facility_name, citytown, country, website
  FROM practice_radar.tms_xlsx__stg.tms_ketamine_clinic
  QUALIFY row_number() OVER (PARTITION BY practice_key ORDER BY facility_name) = 1
), cur AS (
  SELECT practice_hk, hash_diff FROM practice_radar.pr_rdv.sat_practice_tms_ketamine
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_hk) WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;

INSERT INTO practice_radar.pr_rdv.sat_practice_tms_pe
WITH src AS (
  SELECT sha256(upper(practice_key)) AS practice_hk, load_dts,
         sha256(concat_ws('||', facility_name, citytown, website)) AS hash_diff,
         record_source, facility_name, citytown, website
  FROM practice_radar.tms_xlsx__stg.tms_pe_provider
  QUALIFY row_number() OVER (PARTITION BY practice_key ORDER BY facility_name) = 1
), cur AS (
  SELECT practice_hk, hash_diff FROM practice_radar.pr_rdv.sat_practice_tms_pe
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
)
SELECT src.* FROM src LEFT JOIN cur USING (practice_hk) WHERE cur.hash_diff IS DISTINCT FROM src.hash_diff;
