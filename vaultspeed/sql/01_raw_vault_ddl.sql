-- Practice Radar: Raw Vault DDL (DuckDB SQL)
-- Idempotent: safe to re-run before every load. Loads are in 01b_raw_vault_load.sql.
-- Hash keys: sha256(upper(trim(bk))). All objects are insert-only.

CREATE SCHEMA IF NOT EXISTS practice_radar.pr_rdv;

-- ── Hubs ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_provider (
  provider_hk     VARCHAR    NOT NULL,
  npi             VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_organization (
  organization_hk VARCHAR    NOT NULL,
  org_npi         VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_practice (
  practice_hk     VARCHAR    NOT NULL,
  practice_key    VARCHAR    NOT NULL,  -- org_pac_id | 'SOLO|'||location_key | 'TMS|'||norm_name
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_location (
  location_hk     VARCHAR    NOT NULL,
  location_key    VARCHAR    NOT NULL,  -- sha2 of standardised address
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.hub_taxonomy (
  taxonomy_hk     VARCHAR    NOT NULL,
  taxonomy_code   VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

-- ── Links ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_practice_provider (
  practice_provider_hk VARCHAR NOT NULL,
  practice_hk     VARCHAR    NOT NULL,
  provider_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_practice_location (
  practice_location_hk VARCHAR NOT NULL,
  practice_hk     VARCHAR    NOT NULL,
  location_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_provider_location (
  provider_location_hk VARCHAR NOT NULL,
  provider_hk     VARCHAR    NOT NULL,
  location_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_practice_npi_lookup (
  practice_npi_lookup_hk VARCHAR NOT NULL,
  practice_hk     VARCHAR    NOT NULL,
  organization_hk VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_provider_organization (
  provider_organization_hk VARCHAR NOT NULL,
  provider_hk     VARCHAR    NOT NULL,
  organization_hk VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.lnk_provider_taxonomy (
  provider_taxonomy_hk VARCHAR NOT NULL,
  provider_hk     VARCHAR    NOT NULL,
  taxonomy_hk     VARCHAR    NOT NULL,
  taxonomy_slot_number INT,             -- dependent child key (1-15)
  load_dts        TIMESTAMP NOT NULL,
  record_source   VARCHAR    NOT NULL
);

-- ── Satellites (split by source) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_provider_cms_pdc (
  provider_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  provider_first_name  VARCHAR,
  provider_last_name   VARCHAR,
  provider_middle_name VARCHAR,
  suff            VARCHAR,
  gndr            VARCHAR,
  cred            VARCHAR,
  med_sch         VARCHAR,
  grd_yr          INT,
  pri_spec        VARCHAR,
  sec_spec_all    VARCHAR,
  telehlth        VARCHAR,   -- 'Y' or blank (live CMS field; replaces ind_enrlt_flg)
  ind_assgn       VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_provider_nppes (
  provider_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  first_name      VARCHAR,
  last_name       VARCHAR,
  credential      VARCHAR,
  enumeration_date DATE,
  website         VARCHAR,
  endpoint_url    VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_cms_pdc (
  practice_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  facility_name      VARCHAR,
  num_org_mem     INT,
  telephone_number       VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_funded (
  practice_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  facility_name   VARCHAR,
  hq_or_primary_market VARCHAR,
  website         VARCHAR,
  primary_contact_name VARCHAR,
  notes           VARCHAR,
  amount          VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_practice (
  practice_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  practice_name   VARCHAR,
  hq_or_primary_market VARCHAR,
  website         VARCHAR,
  primary_contact VARCHAR,
  notes           VARCHAR,
  states_or_footprint VARCHAR,
  ketamine_spravato_offered VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_ketamine (
  practice_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  facility_name   VARCHAR,
  citytown        VARCHAR,
  country         VARCHAR,
  website         VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_practice_tms_pe (
  practice_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  facility_name   VARCHAR,
  citytown        VARCHAR,
  website         VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_location_cms_pdc (
  location_hk     VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  adr_ln_1        VARCHAR,
  citytown      VARCHAR,
  state VARCHAR,
  zip_code   VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_organization_nppes (
  organization_hk VARCHAR    NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  organization_name VARCHAR,
  authorized_official_first_name VARCHAR,
  authorized_official_last_name  VARCHAR,
  enumeration_date DATE,
  address_state   VARCHAR,
  website         VARCHAR,
  endpoint_url    VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_lnk_practice_npi_lookup (
  practice_npi_lookup_hk VARCHAR NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  query_org_name  VARCHAR,
  query_state     VARCHAR,
  result_rank     INT,
  enumeration_type VARCHAR
);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.sat_lnk_practice_provider (
  practice_provider_hk VARCHAR NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  hash_diff       VARCHAR    NOT NULL,
  record_source   VARCHAR    NOT NULL,
  membership_source VARCHAR
);

-- ── Reference data (replaces config.py) ─────────────────────────────
CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_score_criterion (
  criterion_code  VARCHAR NOT NULL,
  weight_points   INT    NOT NULL,
  ideal_range_min INT,
  ideal_range_max INT,
  description     VARCHAR,
  effective_from  DATE   NOT NULL,
  load_dts        TIMESTAMP NOT NULL,
  PRIMARY KEY (criterion_code, effective_from)
);

INSERT OR IGNORE INTO practice_radar.pr_rdv.ref_score_criterion VALUES
  ('size_fit',          24, 3, 15, 'Clinician count in target band',             DATE'2024-01-01', current_timestamp),
  ('multi_site',        12, NULL, NULL, 'More than one practice address',          DATE'2024-01-01', current_timestamp),
  ('telehealth',         8, NULL, NULL, 'Share of clinicians with telehealth flag', DATE'2024-01-01', current_timestamp),
  ('recency',           16, NULL, NULL, 'Median graduation year, min-max scaled',   DATE'2024-01-01', current_timestamp),
  ('contactability',    20, NULL, NULL, 'Phone (50%) + website (50%)',              DATE'2024-01-01', current_timestamp),
  ('specialty_service', 20, NULL, NULL, 'ABA / ketamine / TMS signal in name',      DATE'2024-01-01', current_timestamp);

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_size_tier (
  size_tier VARCHAR NOT NULL, min_size INT NOT NULL, max_size INT NOT NULL, effective_from DATE NOT NULL,
  PRIMARY KEY (size_tier, effective_from)
);
INSERT OR IGNORE INTO practice_radar.pr_rdv.ref_size_tier VALUES
  ('solo',1,1,DATE'2024-01-01'),('small',2,5,DATE'2024-01-01'),('mid',6,20,DATE'2024-01-01'),
  ('large',21,99,DATE'2024-01-01'),('system',100,9999,DATE'2024-01-01');

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_service_keyword (
  service VARCHAR NOT NULL, keyword VARCHAR NOT NULL, effective_from DATE NOT NULL,
  PRIMARY KEY (service, keyword, effective_from)
);
INSERT OR IGNORE INTO practice_radar.pr_rdv.ref_service_keyword VALUES
  ('ABA','ABA',DATE'2024-01-01'),('ABA','APPLIED BEHAVIOR',DATE'2024-01-01'),('ABA','AUTISM',DATE'2024-01-01'),
  ('KETAMINE','KETAMINE',DATE'2024-01-01'),('KETAMINE','SPRAVATO',DATE'2024-01-01'),
  ('KETAMINE','TMS',DATE'2024-01-01'),('KETAMINE','TRANSCRANIAL',DATE'2024-01-01');

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_data_source (
  source_code VARCHAR NOT NULL, source_category VARCHAR, source_tier_points INT, refresh_cadence VARCHAR,
  PRIMARY KEY (source_code)
);
INSERT OR IGNORE INTO practice_radar.pr_rdv.ref_data_source VALUES
  ('practice_radar','CMS_PDC',NULL,'WEEKLY'),
  ('tms_funded_entity','TMS_XLSX',40,'ON_DEMAND'),
  ('pe_behavioral_health','TMS_XLSX',30,'ON_DEMAND'),
  ('tms_practice','TMS_XLSX',20,'ON_DEMAND'),
  ('ketamine_focused','TMS_XLSX',10,'ON_DEMAND');

CREATE TABLE IF NOT EXISTS practice_radar.pr_rdv.ref_service_breadth (
  service VARCHAR NOT NULL, points INT NOT NULL,
  PRIMARY KEY (service)
);
INSERT OR IGNORE INTO practice_radar.pr_rdv.ref_service_breadth VALUES
  ('TMS★',30),('TMS+KETAMINE',25),('TMS',15),('KETAMINE',5);
