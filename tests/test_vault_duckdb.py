"""VaultSpeed DuckDB vault claims: the SQL runs end to end, loads are idempotent,
TMS duplicates of CMS practices are merged, and steward decisions are reused."""
import importlib.util
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("run_duckdb", ROOT / "vaultspeed" / "run_duckdb.py")
run_duckdb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run_duckdb)


def _clinician(npi, pac, name, adr, tele, grd, spec="PSYCHIATRY"):
    return dict(npi=npi, org_pac_id=pac, facility_name=name, pri_spec=spec, state="RI",
                citytown="PROVIDENCE", zip_code="029031234", adr_ln_1=adr, telephone_number="4015550100",
                telehlth=tele, grd_yr=grd, num_org_mem="3", provider_first_name="A", provider_last_name="B")


def _fixtures(tmp):
    clin = pd.DataFrame([
        _clinician("1000000001", "P1", "ACME PSYCHIATRY LLC", "1 MAIN ST", "Y", 2010),
        _clinician("1000000002", "P1", "ACME PSYCHIATRY LLC", "2 MAIN ST", "", 2016),
        _clinician("1000000003", "P1", "ACME PSYCHIATRY LLC", "1 MAIN ST", "Y", 2012),
        _clinician("1000000004", "", "", "9 ELM AVENUE", "", 1990),   # solo clinician
    ])
    clin.to_csv(tmp / "clinicians.csv", index=False)
    npi = pd.DataFrame([
        dict(number="1999999991", enumeration_type="NPI-2", organization_name="ACME PSYCHIATRY LLC",
             authorized_official_first_name="JANE", authorized_official_last_name="ROE",
             enumeration_date="2015-06-01", address_state="RI", website="https://www.acmepsych.example/",
             query_practice_key="P1", query_org_name="ACME PSYCHIATRY LLC*", query_state="RI", result_rank="1"),
        # TMS row resolves to the same organization NPI -> same-as duplicate of P1
        dict(number="1999999991", enumeration_type="NPI-2", organization_name="ACME PSYCHIATRY LLC",
             query_practice_key="TMS|ACMEPSYCHIATRY", query_org_name="Acme Psychiatry*", result_rank="1"),
    ])
    npi.to_csv(tmp / "npi.csv", index=False)
    sheets = {
        "Funded": pd.DataFrame([dict(facility_name="Bright TMS", website="https://brighttms.example",
                                     primary_contact_name="C", amount="$12.5M")]),
        "Society": pd.DataFrame([dict(name="unused")]),
        "Practices A": pd.DataFrame([dict(practice_name="Acme Psychiatry", website="", primary_contact="",
                                          states_or_footprint="RI, MA", ketamine_spravato_offered="yes")]),
        "Practices B": pd.DataFrame(columns=["practice_name"]),
        "Practices C": pd.DataFrame(columns=["practice_name"]),
        "Ketamine": pd.DataFrame([dict(facility_name="K Clinic", citytown="Providence", country="US")]),
        "PE": pd.DataFrame([dict(facility_name="PE Partners", citytown="Boston")]),
    }
    with pd.ExcelWriter(tmp / "tms.xlsx") as xw:
        for n, df in sheets.items():
            df.to_excel(xw, sheet_name=n, index=False)


def _run(tmp, run_id):
    assert run_duckdb.main(["--clinicians", str(tmp / "clinicians.csv"), "--npi-results", str(tmp / "npi.csv"),
                            "--tms", str(tmp / "tms.xlsx"), "--db", str(tmp / "pr.duckdb"),
                            "--out", str(tmp / "out"), "--run-id", run_id]) == 0
    return duckdb.connect(str(tmp / "pr.duckdb"))


def _one(con, sql):
    return con.execute(sql).fetchone()[0]


def test_vault_end_to_end_idempotent_and_deduplicated(tmp_path):
    _fixtures(tmp_path)
    con = _run(tmp_path, "r1")
    hubs = {t: _one(con, f"SELECT count(*) FROM pr_rdv.{t}")
            for t in ("hub_provider", "hub_practice", "hub_location", "hub_organization",
                      "sat_provider_cms_pdc", "sat_practice_cms_pdc", "lnk_practice_provider")}
    assert hubs["hub_provider"] == 4
    assert hubs["hub_practice"] == 6          # P1, one solo, four TMS keys
    assert hubs["hub_organization"] == 1

    # rollup: distinct clinicians, sites and telehealth share from the live 'telehlth' column
    size, sites, tele = con.execute("""SELECT size, n_sites, telehealth_share FROM pr_bv.bv_sat_practice_rollup r
        JOIN pr_rdv.hub_practice h USING (practice_hk) WHERE h.practice_key = 'P1'""").fetchone()
    assert (size, sites) == (3, 2) and abs(tele - 2 / 3) < 1e-9

    # same-as: the TMS 'Acme Psychiatry' row is merged into CMS practice P1
    assert con.execute("""SELECT h.practice_key, s.match_rule FROM pr_bv.bv_sal_practice s
        JOIN pr_rdv.hub_practice h ON h.practice_hk = s.master_practice_hk""").fetchall() == [("P1", "org_npi")]
    tl = con.execute('SELECT "Company Name", "Data Source", "NPI Match Confidence" FROM pr_mart.mart_hubspot_target_list').fetchall()
    assert ("ACME PSYCHIATRY LLC", "tms_practice", "org_npi") in tl
    assert not any(name == "Acme Psychiatry" for name, _, _ in tl)

    # TMS priority matches append_tms.tms_priority: funded 40 + TMS★ 30 + website 10 + contact 10
    assert _one(con, "SELECT tms_priority_score FROM pr_bv.bv_sat_practice_tms_priority WHERE tms_source = 'tms_funded_entity'") == 90
    assert _one(con, "SELECT funding_amount_usd FROM pr_bv.bv_sat_practice_tms_priority WHERE tms_source = 'tms_funded_entity'") == 12_500_000
    queue = {r[0] for r in con.execute("SELECT facility_name FROM pr_mart.mart_npi_review_queue").fetchall()}
    assert queue == {"Bright TMS", "K Clinic", "PE Partners"}
    con.close()

    # re-run with identical sources: no new hub/link/sat rows, one extra score run
    con = _run(tmp_path, "r2")
    for t, n in hubs.items():
        assert _one(con, f"SELECT count(*) FROM pr_rdv.{t}") == n, t
    assert _one(con, "SELECT count(DISTINCT score_run_id) FROM pr_bv.bv_sat_practice_score") == 2

    # a steward decision is stored once and reused: confirming 'Bright TMS' moves it to the target list
    con.execute("""INSERT INTO pr_bv.npi_review_decision
        SELECT practice_hk, '1888888881', 'confirmed', 'steward@example', current_timestamp
        FROM pr_rdv.hub_practice WHERE practice_key = 'TMS|BRIGHTTMS'""")
    assert "Bright TMS" not in {r[0] for r in con.execute("SELECT facility_name FROM pr_mart.mart_npi_review_queue").fetchall()}
    assert _one(con, """SELECT "NPI (Organization NPI-2)" FROM pr_mart.mart_hubspot_target_list
        WHERE "Company Name" = 'Bright TMS'""") == "1888888881"
    con.close()
