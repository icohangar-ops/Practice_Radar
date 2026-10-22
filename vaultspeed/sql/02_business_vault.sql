-- Practice Radar: Business Vault (Databricks SQL)
-- Ports practice_rollup.py, score.py, append_tms.py (priority) and npi_append.py (confidence)
-- into versioned, set-based logic. All weights are read from the REF_* tables.

CREATE SCHEMA IF NOT EXISTS practice_radar.pr_bv;

-- Current row per satellite (helper views)
CREATE OR REPLACE VIEW practice_radar.pr_bv.cur_sat_provider_cms_pdc AS
SELECT * FROM practice_radar.pr_rdv.sat_provider_cms_pdc
QUALIFY row_number() OVER (PARTITION BY provider_hk ORDER BY load_dts DESC) = 1;

CREATE OR REPLACE VIEW practice_radar.pr_bv.cur_sat_practice_cms_pdc AS
SELECT * FROM practice_radar.pr_rdv.sat_practice_cms_pdc
QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1;

CREATE OR REPLACE VIEW practice_radar.pr_bv.cur_sat_organization_nppes AS
SELECT * FROM practice_radar.pr_rdv.sat_organization_nppes
QUALIFY row_number() OVER (PARTITION BY organization_hk ORDER BY load_dts DESC) = 1;

CREATE OR REPLACE VIEW practice_radar.pr_bv.cur_ref_score_criterion AS
SELECT * FROM practice_radar.pr_rdv.ref_score_criterion
WHERE effective_from <= current_date()
QUALIFY row_number() OVER (PARTITION BY criterion_code ORDER BY effective_from DESC, load_dts DESC) = 1;

-- ── BV_SAT_PRACTICE_NPI_MATCH (npi_append.py) ────────────────────────
-- Best API candidate per practice (rank 1). A steward decision overrides it
-- (see practice_radar.pr_bv.npi_review_decision).
CREATE TABLE IF NOT EXISTS practice_radar.pr_bv.npi_review_decision (
  practice_hk   STRING NOT NULL,
  decided_npi   STRING,
  review_status STRING NOT NULL,          -- open | confirmed | rejected
  reviewer      STRING,
  reviewed_at   TIMESTAMP
) USING DELTA;

CREATE OR REPLACE VIEW practice_radar.pr_bv.bv_sat_practice_npi_match AS
WITH api AS (
  SELECT l.practice_hk, h.org_npi, s.result_rank, s.query_org_name
  FROM practice_radar.pr_rdv.lnk_practice_npi_lookup l
  JOIN practice_radar.pr_rdv.hub_organization h USING (organization_hk)
  JOIN practice_radar.pr_rdv.sat_lnk_practice_npi_lookup s USING (practice_npi_lookup_hk)
  WHERE s.enumeration_type = 'NPI-2'
  QUALIFY row_number() OVER (PARTITION BY l.practice_hk ORDER BY s.result_rank, s.load_dts DESC) = 1
),
ind AS (  -- first clinician NPI, as in npi_sample
  SELECT lp.practice_hk, min(hp.npi) AS npi_individual
  FROM practice_radar.pr_rdv.lnk_practice_provider lp
  JOIN practice_radar.pr_rdv.hub_provider hp USING (provider_hk)
  GROUP BY lp.practice_hk
),
dec AS (
  SELECT * FROM practice_radar.pr_bv.npi_review_decision
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY reviewed_at DESC) = 1
)
SELECT
  p.practice_hk,
  CASE WHEN dec.review_status = 'rejected' THEN NULL
       ELSE coalesce(dec.decided_npi, api.org_npi) END            AS npi_org,
  ind.npi_individual,
  CASE WHEN dec.review_status = 'confirmed' AND coalesce(dec.decided_npi, api.org_npi) IS NOT NULL
                                                                     THEN 'org_npi'
       WHEN coalesce(dec.review_status, '') <> 'rejected' AND api.org_npi IS NOT NULL
                                                                     THEN 'org_npi'
       WHEN ind.npi_individual IS NOT NULL                          THEN 'individual_npi_only'
       ELSE 'unmatched' END                                         AS npi_match_confidence,
  CASE WHEN dec.review_status IS NOT NULL THEN 'steward'
       WHEN api.org_npi IS NOT NULL       THEN 'nppes_api_org_name_state'
       WHEN ind.npi_individual IS NOT NULL THEN 'cms_clinician_npi'
       ELSE 'none' END                                              AS match_method,
  api.query_org_name                                                AS matched_on,
  coalesce(dec.review_status,
           CASE WHEN api.org_npi IS NULL AND ind.npi_individual IS NULL THEN 'open' END) AS review_status,
  dec.reviewer, dec.reviewed_at
FROM practice_radar.pr_rdv.hub_practice p
LEFT JOIN api USING (practice_hk)
LEFT JOIN ind USING (practice_hk)
LEFT JOIN dec USING (practice_hk);

-- ── BV_SAT_PRACTICE_ROLLUP (practice_rollup.py) ──────────────────────
-- Change versus the pandas version: size counts DISTINCT providers. The pandas
-- version counted npi x address rows, so a clinician with two addresses was counted twice.
CREATE OR REPLACE VIEW practice_radar.pr_bv.bv_sat_practice_rollup AS
WITH members AS (
  SELECT lp.practice_hk, lp.provider_hk, sp.grd_yr, sp.telehlth, sp.pri_spec
  FROM practice_radar.pr_rdv.lnk_practice_provider lp
  LEFT JOIN practice_radar.pr_bv.cur_sat_provider_cms_pdc sp USING (provider_hk)
),
sites AS (
  SELECT practice_hk, count(DISTINCT location_hk) AS n_sites
  FROM practice_radar.pr_rdv.lnk_practice_location GROUP BY practice_hk
),
agg AS (
  SELECT practice_hk,
         count(DISTINCT provider_hk)                          AS size,
         avg(CASE WHEN telehlth = 'Y' THEN 1.0 ELSE 0 END) AS telehealth_share,
         percentile(grd_yr, 0.5)                               AS median_grad_yr,
         mode(pri_spec)                                        AS pri_spec
  FROM members GROUP BY practice_hk
),
named AS (
  SELECT a.*, coalesce(s.n_sites, 0) AS n_sites,
         c.facility_name AS facility_name, c.telephone_number AS telephone_number
  FROM agg a
  LEFT JOIN sites s USING (practice_hk)
  LEFT JOIN practice_radar.pr_bv.cur_sat_practice_cms_pdc c USING (practice_hk)
),
svc AS (
  SELECT n.practice_hk,
         min_by(k.service, CASE k.service WHEN 'ABA' THEN 1 ELSE 2 END) AS specialty_service
  FROM named n
  JOIN practice_radar.pr_rdv.ref_service_keyword k
    ON instr(upper(n.facility_name), k.keyword) > 0
  GROUP BY n.practice_hk
)
SELECT n.*,
       year(current_date()) - n.median_grad_yr AS median_exp_yrs,
       n.n_sites = 1                           AS is_solo,
       n.n_sites > 1                           AS is_multi_site,
       coalesce(t.size_tier, 'system')         AS size_tier,
       coalesce(svc.specialty_service, '—')    AS specialty_service
FROM named n
LEFT JOIN practice_radar.pr_rdv.ref_size_tier t ON n.size BETWEEN t.min_size AND t.max_size
LEFT JOIN svc USING (practice_hk);

-- ── BV_SAT_PRACTICE_SCORE (score.py) ─────────────────────────────────
-- Materialise one row per practice per score run so runs can be compared.
CREATE TABLE IF NOT EXISTS practice_radar.pr_bv.bv_sat_practice_score (
  practice_hk          STRING    NOT NULL,
  score_run_id         STRING    NOT NULL,
  scored_at            TIMESTAMP NOT NULL,
  criterion_version    DATE      NOT NULL,
  sc_size_fit          DOUBLE, sc_multi_site DOUBLE, sc_telehealth DOUBLE,
  sc_recency           DOUBLE, sc_contactability DOUBLE, sc_specialty_service DOUBLE,
  total_score          DOUBLE,
  score_source         STRING
) USING DELTA;

-- Run once per score run (pass :run_id from the orchestrator).
INSERT INTO practice_radar.pr_bv.bv_sat_practice_score
WITH w AS (
  SELECT max(CASE WHEN criterion_code='size_fit'          THEN weight_points END)   AS w_size,
         max(CASE WHEN criterion_code='size_fit'          THEN ideal_range_min END) AS lo,
         max(CASE WHEN criterion_code='size_fit'          THEN ideal_range_max END) AS hi,
         max(CASE WHEN criterion_code='multi_site'        THEN weight_points END)   AS w_multi,
         max(CASE WHEN criterion_code='telehealth'        THEN weight_points END)   AS w_tele,
         max(CASE WHEN criterion_code='recency'           THEN weight_points END)   AS w_rec,
         max(CASE WHEN criterion_code='contactability'    THEN weight_points END)   AS w_contact,
         max(CASE WHEN criterion_code='specialty_service' THEN weight_points END)   AS w_svc,
         max(effective_from)                                                        AS criterion_version
  FROM practice_radar.pr_bv.cur_ref_score_criterion
),
r AS (
  SELECT r.*, o.website,
         min(median_grad_yr) OVER () AS yr_min,
         max(median_grad_yr) OVER () AS yr_max
  FROM practice_radar.pr_bv.bv_sat_practice_rollup r
  LEFT JOIN practice_radar.pr_bv.bv_sat_practice_npi_match m USING (practice_hk)
  LEFT JOIN practice_radar.pr_rdv.hub_organization ho ON ho.org_npi = m.npi_org
  LEFT JOIN practice_radar.pr_bv.cur_sat_organization_nppes o USING (organization_hk)
),
s AS (
  SELECT r.practice_hk, w.criterion_version,
    CASE WHEN size BETWEEN lo AND hi THEN w_size
         WHEN size < lo THEN w_size * 0.5
         ELSE greatest(0, w_size * (1 - (size - hi) / hi)) END                    AS sc_size_fit,
    CAST(is_multi_site AS INT) * w_multi                                          AS sc_multi_site,
    least(coalesce(telehealth_share, 0) * w_tele, w_tele)                         AS sc_telehealth,
    least((coalesce(median_grad_yr, yr_min) - yr_min)
          / CASE WHEN yr_max = yr_min THEN 1 ELSE yr_max - yr_min END * w_rec, w_rec) AS sc_recency,
    ( CASE WHEN nullif(trim(telephone_number), '') IS NOT NULL THEN 0.5 ELSE 0 END
    + CASE WHEN nullif(trim(website), '')          IS NOT NULL THEN 0.5 ELSE 0 END) * w_contact AS sc_contactability,
    CASE WHEN specialty_service <> '—' THEN w_svc ELSE 0 END                       AS sc_specialty_service
  FROM r CROSS JOIN w
)
SELECT practice_hk, :run_id, current_timestamp(), criterion_version,
       sc_size_fit, sc_multi_site, sc_telehealth, sc_recency, sc_contactability, sc_specialty_service,
       round(sc_size_fit + sc_multi_site + sc_telehealth + sc_recency + sc_contactability + sc_specialty_service, 1),
       'cms_practice_radar'
FROM s;

-- ── BV_SAT_PRACTICE_TMS_PRIORITY (append_tms.py) ─────────────────────
CREATE OR REPLACE VIEW practice_radar.pr_bv.bv_sat_practice_tms_priority AS
WITH tms AS (
  SELECT practice_hk, 'tms_funded_entity' AS tms_source, 'TMS★' AS specialty_service,
         website, primary_contact_name AS contact, NULL AS footprint, amount
  FROM practice_radar.pr_rdv.sat_practice_tms_funded
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
  UNION ALL
  SELECT practice_hk, 'tms_practice',
         CASE WHEN lower(ketamine_spravato_offered) IN ('yes','y','true','1') THEN 'TMS+KETAMINE' ELSE 'TMS' END,
         website, primary_contact, states_or_footprint, NULL
  FROM practice_radar.pr_rdv.sat_practice_tms_practice
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
  UNION ALL
  SELECT practice_hk, 'ketamine_focused', 'KETAMINE', website, NULL, NULL, NULL
  FROM practice_radar.pr_rdv.sat_practice_tms_ketamine
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
  UNION ALL
  SELECT practice_hk, 'pe_behavioral_health', 'TMS', website, NULL, NULL, NULL
  FROM practice_radar.pr_rdv.sat_practice_tms_pe
  QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY load_dts DESC) = 1
)
SELECT t.practice_hk, t.tms_source, t.specialty_service,
       coalesce(ds.source_tier_points, 0) + coalesce(sb.points, 0)
       + CASE WHEN nullif(trim(t.website), '') IS NOT NULL THEN 10 ELSE 0 END
       + CASE WHEN nullif(trim(t.contact), '') IS NOT NULL THEN 10 ELSE 0 END
       + CASE WHEN size(split(t.footprint, ',')) > 1 THEN 10 ELSE 0 END AS tms_priority_score,
       -- '$12.5M' -> 12500000
       try_cast(regexp_extract(replace(upper(t.amount), ',', ''), '([0-9]+(\\.[0-9]+)?)', 1) AS DOUBLE)
       * CASE regexp_extract(replace(upper(t.amount), ',', ''), '[0-9.]+\\s*([MBK]?)', 1)
           WHEN 'M' THEN 1e6 WHEN 'B' THEN 1e9 WHEN 'K' THEN 1e3 ELSE 1 END AS funding_amount_usd
FROM tms t
LEFT JOIN practice_radar.pr_rdv.ref_data_source     ds ON ds.source_code = t.tms_source
LEFT JOIN practice_radar.pr_rdv.ref_service_breadth sb ON sb.service     = t.specialty_service;
