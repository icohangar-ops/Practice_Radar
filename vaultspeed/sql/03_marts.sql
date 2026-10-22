-- Practice Radar: marts (Databricks SQL)
-- Backs the data products practice_radar_hubspot_target_list and practice_radar_npi_review_queue.
-- Column aliases keep the HubSpot import headers from npi_append.py unchanged.

CREATE SCHEMA IF NOT EXISTS practice_radar.pr_mart;

CREATE OR REPLACE VIEW practice_radar.pr_mart.latest_practice_score AS
SELECT * FROM practice_radar.pr_bv.bv_sat_practice_score
QUALIFY row_number() OVER (PARTITION BY practice_hk ORDER BY scored_at DESC) = 1;

CREATE OR REPLACE VIEW practice_radar.pr_mart.practice_target_base AS
WITH loc AS (   -- primary location = first linked address
  SELECT lpl.practice_hk, sl.adr_ln_1, sl.citytown, sl.state, sl.zip_code
  FROM practice_radar.pr_rdv.lnk_practice_location lpl
  JOIN practice_radar.pr_rdv.sat_location_cms_pdc sl USING (location_hk)
  QUALIFY row_number() OVER (PARTITION BY lpl.practice_hk ORDER BY sl.load_dts DESC, sl.adr_ln_1) = 1
),
tms_name AS (
  SELECT practice_hk, facility_name, website FROM practice_radar.pr_rdv.sat_practice_tms_funded
  UNION ALL SELECT practice_hk, practice_name, website FROM practice_radar.pr_rdv.sat_practice_tms_practice
  UNION ALL SELECT practice_hk, facility_name, website FROM practice_radar.pr_rdv.sat_practice_tms_ketamine
  UNION ALL SELECT practice_hk, facility_name, website FROM practice_radar.pr_rdv.sat_practice_tms_pe
)
SELECT
  h.practice_hk,
  h.practice_key,
  coalesce(r.facility_name, tn.facility_name)                     AS facility_name,
  m.npi_org, m.npi_individual, m.npi_match_confidence, m.match_method, m.review_status,
  m.reviewer, m.reviewed_at,
  loc.state                                        AS state,
  loc.citytown                                                  AS citytown,
  loc.zip_code                                          AS zip_code,
  loc.adr_ln_1,
  r.telephone_number,
  coalesce(o.website, tn.website)                                 AS website,
  r.pri_spec,
  coalesce(tp.specialty_service, r.specialty_service)             AS specialty_service,
  concat_ws(' ', o.authorized_official_first_name, o.authorized_official_last_name) AS authorized_official,
  r.size_tier,
  s.sc_size_fit, s.sc_multi_site, s.sc_telehealth, s.sc_recency, s.sc_contactability, s.sc_specialty_service,
  coalesce(s.total_score, tp.tms_priority_score)                  AS unified_score,
  CASE WHEN s.total_score IS NOT NULL THEN 'cms_practice_radar' ELSE 'tms_priority' END AS score_source,
  coalesce(tp.tms_source, dup_tp.tms_source, 'practice_radar')    AS tms_source,
  tp.funding_amount_usd,
  s.score_run_id,
  o.endpoint_url IS NOT NULL                                      AS has_fhir_endpoint
FROM practice_radar.pr_rdv.hub_practice h
LEFT JOIN practice_radar.pr_bv.bv_sat_practice_rollup      r  USING (practice_hk)
LEFT JOIN practice_radar.pr_bv.bv_sat_practice_npi_match   m  USING (practice_hk)
LEFT JOIN practice_radar.pr_bv.bv_sat_practice_tms_priority tp USING (practice_hk)
LEFT JOIN practice_radar.pr_mart.latest_practice_score     s  USING (practice_hk)
LEFT JOIN loc                                                  USING (practice_hk)
LEFT JOIN (SELECT practice_hk, max(facility_name) AS facility_name, max(website) AS website
           FROM tms_name GROUP BY practice_hk) tn
                                                               USING (practice_hk)
LEFT JOIN practice_radar.pr_rdv.hub_organization ho ON ho.org_npi = m.npi_org
LEFT JOIN practice_radar.pr_bv.cur_sat_organization_nppes o ON o.organization_hk = ho.organization_hk
-- TMS duplicates of this (master) practice: carry their TMS source over
LEFT JOIN (SELECT sal.master_practice_hk, max(t.tms_source) AS tms_source
           FROM practice_radar.pr_bv.bv_sal_practice sal
           JOIN practice_radar.pr_bv.bv_sat_practice_tms_priority t ON t.practice_hk = sal.dup_practice_hk
           GROUP BY sal.master_practice_hk) dup_tp ON dup_tp.master_practice_hk = h.practice_hk
-- drop practices that are a same-as duplicate of a CMS practice
WHERE NOT EXISTS (SELECT 1 FROM practice_radar.pr_bv.bv_sal_practice sal
                  WHERE sal.dup_practice_hk = h.practice_hk);

-- ── HubSpot target list (NPI-confirmed, ranked) ──────────────────────
CREATE OR REPLACE VIEW practice_radar.pr_mart.mart_hubspot_target_list AS
SELECT
  dense_rank() OVER (ORDER BY unified_score DESC) AS `Rank`,
  facility_name        AS `Company Name`,
  npi_org              AS `NPI (Organization NPI-2)`,
  npi_individual       AS `NPI (Individual NPI-1)`,
  npi_match_confidence AS `NPI Match Confidence`,
  state                AS `State/Region`,
  citytown             AS `City`,
  zip_code             AS `Postal Code`,
  adr_ln_1             AS `Street Address`,
  telephone_number     AS `Phone Number`,
  website              AS `Website`,
  pri_spec             AS `Primary Specialty`,
  specialty_service    AS `Specialty Service`,
  authorized_official  AS `Contact Name`,
  unified_score        AS `Practice Radar Score`,
  score_source         AS `Score Source`,
  tms_source           AS `Data Source`,
  funding_amount_usd   AS `Funding Amount (USD)`,
  size_tier            AS `Size Tier`,
  sc_size_fit, sc_multi_site, sc_telehealth, sc_recency, sc_contactability, sc_specialty_service,
  score_run_id
FROM practice_radar.pr_mart.practice_target_base
WHERE npi_match_confidence IN ('org_npi', 'individual_npi_only');

-- ── NPI review queue (unmatched, highest value first) ────────────────
CREATE OR REPLACE VIEW practice_radar.pr_mart.mart_npi_review_queue AS
SELECT
  practice_hk, practice_key, facility_name, state, citytown, adr_ln_1, telephone_number, website,
  tms_source AS data_source,
  npi_org    AS candidate_npi,
  match_method, npi_match_confidence,
  coalesce(review_status, 'open') AS review_status,
  reviewer, reviewed_at,
  unified_score AS practice_radar_score
FROM practice_radar.pr_mart.practice_target_base
WHERE npi_match_confidence = 'unmatched'
ORDER BY unified_score DESC NULLS LAST;
