"""
run_duckdb.py – load Practice Radar sources into DuckDB and build the vault
──────────────────────────────────────────────────────────────────────────
Runs the VaultSpeed design end to end on a local DuckDB file:

  sources ─▶ staging ─▶ Raw Vault ─▶ Business Vault ─▶ marts ─▶ CSV exports

Usage (from the repo root, after `python ingest.py`):
    python vaultspeed/run_duckdb.py --clinicians clinicians_raw.csv \
        [--tms tms_market_data.xlsx] [--npi-results npi_registry_result.csv] \
        [--fetch-npi 400] [--db practice_radar.duckdb] [--out out/]

  --fetch-npi N   query the NPPES API (NPI-2, organization name + state) for the
                  N largest CMS practices plus every TMS row that has no stored
                  lookup yet (as nppes_enrich.py + npi_append.py do), and keep
                  every returned candidate (not just the first) in
                  nppes_api.npi_registry_result.
Re-running is safe: hubs, links and satellites are insert-only and only take
new keys or changed hash diffs; every run adds one score run.
"""
import argparse
import datetime as dt
import re
import sys
import time
from pathlib import Path

import duckdb
import pandas as pd
import requests

HERE = Path(__file__).resolve().parent
SQL_FILES = ["00_staging_keys.sql", "01_raw_vault_ddl.sql", "01b_raw_vault_load.sql",
             "02_business_vault.sql", "02b_bv_sal_pit_bridge.sql", "03_marts.sql"]
NPPES_URL = "https://npiregistry.cms.hhs.gov/api/"

SOURCE_COLUMNS = {
    "cms_pdc.clinician": [
        "npi", "ind_pac_id", "ind_enrl_id", "provider_last_name", "provider_first_name",
        "provider_middle_name", "suff", "gndr", "cred", "med_sch", "grd_yr", "pri_spec",
        "sec_spec_all", "telehlth", "facility_name", "org_pac_id", "num_org_mem", "adr_ln_1",
        "adr_ln_2", "ln_2_sprs", "citytown", "state", "zip_code", "telephone_number",
        "ind_assgn", "grp_assgn", "adrs_id"],
    "nppes_api.npi_registry_result": [
        "number", "enumeration_type", "organization_name", "authorized_official_first_name",
        "authorized_official_last_name", "enumeration_date", "address_state", "website",
        "endpoint_url", "query_practice_key", "query_org_name", "query_state", "result_rank"],
    "tms_xlsx.tms_funded_entity": ["facility_name", "hq_or_primary_market", "website",
                                   "primary_contact_name", "notes", "amount"],
    "tms_xlsx.tms_practice": ["practice_name", "hq_or_primary_market", "website", "primary_contact",
                              "notes", "states_or_footprint", "ketamine_spravato_offered"],
    "tms_xlsx.tms_ketamine_clinic": ["facility_name", "citytown", "country", "website"],
    "tms_xlsx.tms_pe_provider": ["facility_name", "citytown", "website"],
}


def _frame(df, table):
    """Conform a source frame to the registered columns (missing -> NULL, all text)."""
    cols = SOURCE_COLUMNS[table]
    df = (df if df is not None else pd.DataFrame()).copy()
    for c in cols:
        if c not in df.columns:
            df[c] = None
    df = df[cols]
    return df.astype(object).where(df.notna(), None).astype("string")


def load_source(con, table, df):
    schema = table.split(".")[0]
    con.execute(f"CREATE SCHEMA IF NOT EXISTS practice_radar.{schema}")
    con.register("_src", _frame(df, table))
    con.execute(f"CREATE OR REPLACE TABLE practice_radar.{table} AS SELECT * FROM _src")
    con.unregister("_src")


def read_tms(path):
    """Same sheet layout as load_tms.py: 0 funded, 2-4 practices, 5 ketamine, 6 PE."""
    if not path:
        return {}
    xl = pd.ExcelFile(path)
    names = xl.sheet_names
    return {
        "tms_xlsx.tms_funded_entity": xl.parse(names[0]),
        "tms_xlsx.tms_practice": pd.concat([xl.parse(names[i]) for i in range(2, 5)],
                                           ignore_index=True).drop_duplicates(),
        "tms_xlsx.tms_ketamine_clinic": xl.parse(names[5]),
        "tms_xlsx.tms_pe_provider": xl.parse(names[6]),
    }


def fetch_npi(con, n, existing):
    """NPPES NPI-2 lookups for the n largest practices without a stored lookup."""
    done = set(existing["query_practice_key"]) if existing is not None and len(existing) else set()
    # CMS practices (largest first), then TMS rows, as nppes_enrich.py and npi_append.py do.
    # TMS rows carry no state column; a two-letter code in hq_or_primary_market is used when present.
    cands = con.execute("""
        WITH cms AS (
          SELECT practice_key, mode(facility_name) AS name, mode(state) AS state,
                 count(DISTINCT npi) AS size, 0 AS src_order
          FROM practice_radar.cms_pdc__stg.clinician
          WHERE nullif(trim(facility_name), '') IS NOT NULL
          GROUP BY practice_key),
        tms AS (
          SELECT practice_key, name, nullif(regexp_extract(coalesce(market, ''), '\\b([A-Z]{2})\\b', 1), '') AS state,
                 0 AS size, 1 AS src_order
          FROM (SELECT practice_key, facility_name AS name, hq_or_primary_market AS market FROM practice_radar.tms_xlsx__stg.tms_funded_entity
                UNION ALL SELECT practice_key, practice_name, hq_or_primary_market FROM practice_radar.tms_xlsx__stg.tms_practice
                UNION ALL SELECT practice_key, facility_name, citytown FROM practice_radar.tms_xlsx__stg.tms_ketamine_clinic
                UNION ALL SELECT practice_key, facility_name, citytown FROM practice_radar.tms_xlsx__stg.tms_pe_provider))
        SELECT * FROM cms UNION ALL SELECT * FROM tms
        ORDER BY src_order, size DESC, practice_key""").df()
    cands = cands[~cands.practice_key.isin(done)]
    cands = pd.concat([cands[cands.src_order == 0].head(n), cands[cands.src_order == 1]], ignore_index=True)
    rows, s = [], requests.Session()
    for _, c in cands.iterrows():
        name = re.sub(r"[^A-Za-z0-9 &]", "", str(c["name"]))[:60].strip()
        if not name:
            continue
        try:
            r = s.get(NPPES_URL, params={"version": "2.1", "enumeration_type": "NPI-2",
                                         "organization_name": name + "*",
                                         "state": c["state"] if isinstance(c["state"], str) else None,
                                         "limit": 5}, timeout=20)
            results = r.json().get("results", []) if r.ok else []
        except (requests.RequestException, ValueError):
            results = []
        for rank, res in enumerate(results, 1):
            b = res.get("basic", {})
            ends = res.get("endpoints", []) or []
            loc = next((a for a in res.get("addresses", []) if a.get("address_purpose") == "LOCATION"), {})
            rows.append(dict(
                number=res.get("number"), enumeration_type=res.get("enumeration_type"),
                organization_name=b.get("organization_name"),
                authorized_official_first_name=b.get("authorized_official_first_name"),
                authorized_official_last_name=b.get("authorized_official_last_name"),
                enumeration_date=b.get("enumeration_date"), address_state=loc.get("state"),
                website=next((p.get("website") for p in res.get("practiceLocations", []) if p.get("website")), None),
                endpoint_url=next((e.get("endpoint") for e in ends if "fhir" in str(e.get("endpoint", "")).lower()), None),
                query_practice_key=c["practice_key"], query_org_name=name + "*",
                query_state=c["state"], result_rank=rank))
        time.sleep(0.1)
    print(f"  NPPES lookups: {len(cands)} practices queried, {len(rows)} candidate rows")
    new = pd.DataFrame(rows, columns=SOURCE_COLUMNS["nppes_api.npi_registry_result"])
    return pd.concat([existing, new], ignore_index=True) if existing is not None else new


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--clinicians", required=True)
    ap.add_argument("--tms")
    ap.add_argument("--npi-results")
    ap.add_argument("--fetch-npi", type=int, default=0)
    ap.add_argument("--db", default="practice_radar.duckdb")
    ap.add_argument("--out", default="out")
    ap.add_argument("--run-id", default=dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    a = ap.parse_args(argv)

    con = duckdb.connect()
    con.execute(f"ATTACH '{a.db}' AS practice_radar")
    con.execute("SET VARIABLE load_dts = current_timestamp::TIMESTAMP")
    con.execute(f"SET VARIABLE run_id = '{a.run_id}'")

    load_source(con, "cms_pdc.clinician", pd.read_csv(a.clinicians, dtype=str))
    for table, df in read_tms(a.tms).items():
        load_source(con, table, df)
    for table in SOURCE_COLUMNS:  # empty placeholders keep the SQL valid without optional sources
        con.execute(f"CREATE SCHEMA IF NOT EXISTS practice_radar.{table.split('.')[0]}")
        if not con.execute("SELECT count(*) FROM information_schema.tables WHERE table_catalog='practice_radar' "
                           "AND table_schema=? AND table_name=?", table.split(".")).fetchone()[0]:
            load_source(con, table, None)

    npi = pd.read_csv(a.npi_results, dtype=str) if a.npi_results else None
    if npi is not None:
        load_source(con, "nppes_api.npi_registry_result", npi)
    con.execute((HERE / "sql" / SQL_FILES[0]).read_text())  # staging, needed for NPPES candidates
    if a.fetch_npi:
        npi = fetch_npi(con, a.fetch_npi, npi)
        load_source(con, "nppes_api.npi_registry_result", npi)
        Path(a.out).mkdir(parents=True, exist_ok=True)
        npi.to_csv(Path(a.out) / "npi_registry_result.csv", index=False)

    for f in SQL_FILES:
        con.execute((HERE / "sql" / f).read_text())
        print(f"  ran {f}")

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for view in ("mart_hubspot_target_list", "mart_npi_review_queue"):
        df = con.execute(f"SELECT * FROM practice_radar.pr_mart.{view}").df()
        df.to_csv(out / f"{view}.csv", index=False)
        print(f"  {view}: {len(df):,} rows -> {out / (view + '.csv')}")
    counts = con.execute("""
        SELECT schema_name || '.' || table_name AS obj, estimated_size AS rows
        FROM duckdb_tables() WHERE database_name = 'practice_radar'
          AND schema_name IN ('pr_rdv', 'pr_bv') ORDER BY 1""").df()
    print(counts.to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
