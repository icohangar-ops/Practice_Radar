-- Practice Radar: Business Vault same-as link, point-in-time and bridge (DuckDB)
-- Run after 02_business_vault.sql and before 03_marts.sql.

-- ── BV_SAL_PRACTICE ──────────────────────────────────────────────────
-- Same-as link: points a duplicate practice key at its master key.
-- Replaces the blind concat in append_tms.py, which listed TMS practices
-- twice when they were already in the CMS data.
-- Rules, in priority order:
--   1. same organization NPI (NPI-2)           confidence 1.0
--   2. same website domain (registrable part)  confidence 0.8
-- The master is always the CMS practice (org_pac_id / SOLO key). A TMS key
-- never becomes the master of another TMS key, so there are no chains.
CREATE OR REPLACE VIEW practice_radar.pr_bv.bv_practice_domain AS
WITH sites AS (
  SELECT m.practice_hk, o.website
  FROM practice_radar.pr_bv.bv_sat_practice_npi_match m
  JOIN practice_radar.pr_rdv.hub_organization ho ON ho.org_npi = m.npi_org
  JOIN practice_radar.pr_bv.cur_sat_organization_nppes o ON o.organization_hk = ho.organization_hk
  UNION ALL SELECT practice_hk, website FROM practice_radar.pr_rdv.sat_practice_tms_funded
  UNION ALL SELECT practice_hk, website FROM practice_radar.pr_rdv.sat_practice_tms_practice
  UNION ALL SELECT practice_hk, website FROM practice_radar.pr_rdv.sat_practice_tms_ketamine
  UNION ALL SELECT practice_hk, website FROM practice_radar.pr_rdv.sat_practice_tms_pe
)
SELECT DISTINCT practice_hk,
       lower(regexp_extract(website, '^(?:https?://)?(?:www\.)?([^/:?#\s]+)', 1)) AS domain
FROM sites
WHERE nullif(trim(website), '') IS NOT NULL;

CREATE OR REPLACE VIEW practice_radar.pr_bv.bv_sal_practice AS
WITH keyed AS (
  SELECT h.practice_hk, h.practice_key,
         h.practice_key LIKE 'TMS|%' AS is_tms,
         m.npi_org
  FROM practice_radar.pr_rdv.hub_practice h
  LEFT JOIN practice_radar.pr_bv.bv_sat_practice_npi_match m USING (practice_hk)
),
by_npi AS (
  SELECT t.practice_hk AS dup_practice_hk, c.practice_hk AS master_practice_hk,
         'org_npi' AS match_rule, 1.0 AS match_confidence
  FROM keyed t JOIN keyed c
    ON t.is_tms AND NOT c.is_tms AND t.npi_org IS NOT NULL AND t.npi_org = c.npi_org
),
by_domain AS (
  SELECT t.practice_hk, c.practice_hk AS master_practice_hk,
         'website_domain' AS match_rule, 0.8 AS match_confidence
  FROM keyed t
  JOIN practice_radar.pr_bv.bv_practice_domain td ON td.practice_hk = t.practice_hk
  JOIN practice_radar.pr_bv.bv_practice_domain cd ON cd.domain = td.domain
  JOIN keyed c ON c.practice_hk = cd.practice_hk
  WHERE t.is_tms AND NOT c.is_tms
    -- generic hosting/social domains are not identity evidence
    AND td.domain NOT IN ('facebook.com','linkedin.com','instagram.com','google.com',
                          'sites.google.com','wixsite.com','squarespace.com','yelp.com')
),
candidates AS (
  SELECT * FROM by_npi
  UNION ALL
  SELECT practice_hk, master_practice_hk, match_rule, match_confidence FROM by_domain
)
SELECT sha256(concat_ws('||', dup_practice_hk, master_practice_hk)) AS sal_practice_hk,
       dup_practice_hk, master_practice_hk, match_rule, match_confidence,
       current_timestamp AS load_dts, 'BV.same_as_rules.v1' AS record_source
FROM candidates
-- one master per duplicate: highest confidence first, then lowest key so the result is deterministic
QUALIFY row_number() OVER (PARTITION BY dup_practice_hk
                           ORDER BY match_confidence DESC, master_practice_hk) = 1;

-- ── PIT_PRACTICE ─────────────────────────────────────────────────────
-- One row per practice per snapshot date, holding the load_dts of the satellite
-- row that was current on that date (or the ghost date 1900-01-01 if there was none).
-- Rebuilt after each load, and the marts join through it instead of using QUALIFY.
CREATE OR REPLACE TABLE practice_radar.pr_bv.pit_practice AS
WITH snapshots AS (
  SELECT DISTINCT CAST(load_dts AS DATE) AS snapshot_date FROM (
    SELECT load_dts FROM practice_radar.pr_rdv.sat_practice_cms_pdc
    UNION ALL SELECT load_dts FROM practice_radar.pr_rdv.sat_practice_tms_funded
    UNION ALL SELECT load_dts FROM practice_radar.pr_rdv.sat_practice_tms_practice
    UNION ALL SELECT load_dts FROM practice_radar.pr_rdv.sat_practice_tms_ketamine
    UNION ALL SELECT load_dts FROM practice_radar.pr_rdv.sat_practice_tms_pe)
),
grid AS (
  SELECT h.practice_hk, s.snapshot_date
  FROM practice_radar.pr_rdv.hub_practice h
  CROSS JOIN snapshots s
  WHERE CAST(h.load_dts AS DATE) <= s.snapshot_date
)
SELECT g.practice_hk, g.snapshot_date,
  coalesce((SELECT max(load_dts) FROM practice_radar.pr_rdv.sat_practice_cms_pdc x
            WHERE x.practice_hk = g.practice_hk AND CAST(x.load_dts AS DATE) <= g.snapshot_date),
           TIMESTAMP'1900-01-01') AS sat_practice_cms_pdc_ldts,
  coalesce((SELECT max(load_dts) FROM practice_radar.pr_rdv.sat_practice_tms_funded x
            WHERE x.practice_hk = g.practice_hk AND CAST(x.load_dts AS DATE) <= g.snapshot_date),
           TIMESTAMP'1900-01-01') AS sat_practice_tms_funded_ldts,
  coalesce((SELECT max(load_dts) FROM practice_radar.pr_rdv.sat_practice_tms_practice x
            WHERE x.practice_hk = g.practice_hk AND CAST(x.load_dts AS DATE) <= g.snapshot_date),
           TIMESTAMP'1900-01-01') AS sat_practice_tms_practice_ldts,
  coalesce((SELECT max(load_dts) FROM practice_radar.pr_rdv.sat_practice_tms_ketamine x
            WHERE x.practice_hk = g.practice_hk AND CAST(x.load_dts AS DATE) <= g.snapshot_date),
           TIMESTAMP'1900-01-01') AS sat_practice_tms_ketamine_ldts,
  coalesce((SELECT max(load_dts) FROM practice_radar.pr_rdv.sat_practice_tms_pe x
            WHERE x.practice_hk = g.practice_hk AND CAST(x.load_dts AS DATE) <= g.snapshot_date),
           TIMESTAMP'1900-01-01') AS sat_practice_tms_pe_ldts
FROM grid g;
-- At full CMS volume (~17k practices x weekly snapshots), replace the correlated
-- subqueries with an ASOF-style window join, or let VaultSpeed generate the PIT.

-- ── BRIDGE_PRACTICE_PROVIDER ─────────────────────────────────────────
-- Practice → provider → shared location, resolved to the master practice through
-- the same-as link, so the marts never join three links by hand.
CREATE OR REPLACE TABLE practice_radar.pr_bv.bridge_practice_provider AS
SELECT
  coalesce(sal.master_practice_hk, lpp.practice_hk) AS practice_hk,
  lpp.practice_hk                                   AS source_practice_hk,
  lpp.provider_hk,
  lprl.location_hk,
  lpp.practice_provider_hk,
  lprl.provider_location_hk,
  current_date()                                    AS snapshot_date
FROM practice_radar.pr_rdv.lnk_practice_provider lpp
LEFT JOIN practice_radar.pr_rdv.lnk_provider_location lprl
       ON lprl.provider_hk = lpp.provider_hk
      -- keep only the provider's addresses that belong to this practice
      AND EXISTS (SELECT 1 FROM practice_radar.pr_rdv.lnk_practice_location lpl
                  WHERE lpl.practice_hk = lpp.practice_hk AND lpl.location_hk = lprl.location_hk)
LEFT JOIN practice_radar.pr_bv.bv_sal_practice sal ON sal.dup_practice_hk = lpp.practice_hk;
