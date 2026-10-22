-- Practice Radar: Raw Vault target design (Databricks / Delta)
-- VaultSpeed generates the DDL and load code. This file is the reference shape for review.
-- Hash keys: sha2(upper(trim(bk)), 256). All objects are insert-only.

CREATE SCHEMA IF NOT EXISTS practice_radar.pr_rdv;

-- ── Hubs ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_provider (
  provider_hk     STRING    NOT NULL,
  npi             STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_organization (
  organization_hk STRING    NOT NULL,
  org_npi         STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_practice (
  practice_hk     STRING    NOT NULL,
  practice_key    STRING    NOT NULL,  -- org_pac_id | 'SOLO|'||location_key | 'TMS|'||norm_name
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_location (
  location_hk     STRING    NOT NULL,
  location_key    STRING    NOT NULL,  -- sha2 of standardised address
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_taxonomy (
  taxonomy_hk     STRING    NOT NULL,
  taxonomy_code   STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

-- ── Links ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_practice_provider (
  practice_provider_hk STRING NOT NULL,
  practice_hk     STRING    NOT NULL,
  provider_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_practice_location (
  practice_location_hk STRING NOT NULL,
  practice_hk     STRING    NOT NULL,
  location_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_provider_location (
  provider_location_hk STRING NOT NULL,
  provider_hk     STRING    NOT NULL,
  location_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_practice_npi_lookup (
  practice_npi_lookup_hk STRING NOT NULL,
  practice_hk     STRING    NOT NULL,
  organization_hk STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_provider_organization (
  provider_organization_hk STRING NOT NULL,
  provider_hk     STRING    NOT NULL,
  organization_hk STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_provider_taxonomy (
  provider_taxonomy_hk STRING NOT NULL,
  provider_hk     STRING    NOT NULL,
  taxonomy_hk     STRING    NOT NULL,
  taxonomy_slot_number INT,             -- dependent child key (1-15)
  load_dts        TIMESTAMP NOT NULL,
  record_source   STRING    NOT NULL
) USING DELTA;

-- ── Satellites (split by source) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_provider_cms_pdc (
  provider_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  provider_first_name  STRING,
  provider_last_name   STRING,
  provider_middle_name STRING,
  suff            STRING,
  gndr            STRING,
  cred            STRING,
  med_sch         STRING,
  grd_yr          INT,
  pri_spec        STRING,
  sec_spec_all    STRING,
  telehlth        STRING,   -- 'Y' or blank (live CMS field; replaces ind_enrlt_flg)
  ind_assgn       STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_provider_nppes (
  provider_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  first_name      STRING,
  last_name       STRING,
  credential      STRING,
  enumeration_date DATE,
  website         STRING,
  endpoint_url    STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_cms_pdc (
  practice_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  facility_name      STRING,
  num_org_mem     INT,
  telephone_number       STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_funded (
  practice_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  facility_name   STRING,
  hq_or_primary_market STRING,
  website         STRING,
  primary_contact_name STRING,
  notes           STRING,
  amount          STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_practice (
  practice_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  practice_name   STRING,
  hq_or_primary_market STRING,
  website         STRING,
  primary_contact STRING,
  notes           STRING,
  states_or_footprint STRING,
  ketamine_spravato_offered STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_ketamine (
  practice_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  facility_name   STRING,
  citytown        STRING,
  country         STRING,
  website         STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_pe (
  practice_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  facility_name   STRING,
  citytown        STRING,
  website         STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_location_cms_pdc (
  location_hk     STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  adr_ln_1        STRING,
  citytown      STRING,
  state STRING,
  zip_code   STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_organization_nppes (
  organization_hk STRING    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  organization_name STRING,
  authorized_official_first_name STRING,
  authorized_official_last_name  STRING,
  enumeration_date DATE,
  address_state   STRING,
  website         STRING,
  endpoint_url    STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_lnk_practice_npi_lookup (
  practice_npi_lookup_hk STRING NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  query_org_name  STRING,
  query_state     STRING,
  result_rank     INT,
  enumeration_type STRING
) USING DELTA;

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_lnk_practice_provider (
  practice_provider_hk STRING NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       STRING    NOT NULL,
  record_source   STRING    NOT NULL,
  membership_source STRING
) USING DELTA;

-- ── Reference data (replaces config.py) ─────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_score_criterion (
  criterion_code  STRING NOT NULL,
  weight_points   INT    NOT NULL,
  ideal_range_min INT,
  ideal_range_max INT,
  description     STRING,
  effective_from  DATE   NOT NULL,
  load_dts        TIMESTAMP NOT NULL
) USING DELTA;

INSERT INTO practice_radar.pr_rdv.ref_score_criterion VALUES
  ('size_fit',          24, 3, 15, 'Clinician count in target band',             DATE'2024-01-01', current_timestamp()),
  ('multi_site',        12, NULL, NULL, 'More than one practice address',          DATE'2024-01-01', current_timestamp()),
  ('telehealth',         8, NULL, NULL, 'Share of clinicians with telehealth flag', DATE'2024-01-01', current_timestamp()),
  ('recency',           16, NULL, NULL, 'Median graduation year, min-max scaled',   DATE'2024-01-01', current_timestamp()),
  ('contactability',    20, NULL, NULL, 'Phone (50%) + website (50%)',              DATE'2024-01-01', current_timestamp()),
  ('specialty_service', 20, NULL, NULL, 'ABA / ketamine / TMS signal in name',      DATE'2024-01-01', current_timestamp());

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_size_tier (
  size_tier STRING NOT NULL, min_size INT NOT NULL, max_size INT NOT NULL, effective_from DATE NOT NULL
) USING DELTA;
INSERT INTO practice_radar.pr_rdv.ref_size_tier VALUES
  ('solo',1,1,DATE'2024-01-01'),('small',2,5,DATE'2024-01-01'),('mid',6,20,DATE'2024-01-01'),
  ('large',21,99,DATE'2024-01-01'),('system',100,9999,DATE'2024-01-01');

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_service_keyword (
  service STRING NOT NULL, keyword STRING NOT NULL, effective_from DATE NOT NULL
) USING DELTA;
INSERT INTO practice_radar.pr_rdv.ref_service_keyword VALUES
  ('ABA','ABA',DATE'2024-01-01'),('ABA','APPLIED BEHAVIOR',DATE'2024-01-01'),('ABA','AUTISM',DATE'2024-01-01'),
  ('KETAMINE','KETAMINE',DATE'2024-01-01'),('KETAMINE','SPRAVATO',DATE'2024-01-01'),
  ('KETAMINE','TMS',DATE'2024-01-01'),('KETAMINE','TRANSCRANIAL',DATE'2024-01-01');

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_data_source (
  source_code STRING NOT NULL, source_category STRING, source_tier_points INT, refresh_cadence STRING
) USING DELTA;
INSERT INTO practice_radar.pr_rdv.ref_data_source VALUES
  ('practice_radar','CMS_PDC',NULL,'WEEKLY'),
  ('tms_funded_entity','TMS_XLSX',40,'ON_DEMAND'),
  ('pe_behavioral_health','TMS_XLSX',30,'ON_DEMAND'),
  ('tms_practice','TMS_XLSX',20,'ON_DEMAND'),
  ('ketamine_focused','TMS_XLSX',10,'ON_DEMAND');

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_service_breadth (
  service STRING NOT NULL, points INT NOT NULL
) USING DELTA;
INSERT INTO practice_radar.pr_rdv.ref_service_breadth VALUES
  ('TMS★',30),('TMS+KETAMINE',25),('TMS',15),('KETAMINE',5);
