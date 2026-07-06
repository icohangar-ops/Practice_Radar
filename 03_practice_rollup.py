"""
03_practice_rollup.py – Aggregate clinicians → practices
─────────────────────────────────────────────────────────
Groups clinician records by org_pac_id (groups) or address (solos)
to create one row per practice with size, telehealth, and site metrics.
"""
import pandas as pd
import numpy as np
from config import SIZE_TIERS

def rollup(clinicians):
    clinicians = clinicians.copy()
    clinicians["org_pac_id"] = clinicians.get("org_pac_id", pd.Series(dtype=str))
    clinicians["practice_key"] = clinicians["org_pac_id"].where(
        clinicians["org_pac_id"].notna() & (clinicians["org_pac_id"] != ""),
        "SOLO_" + clinicians.get("adr_ln_1", "").fillna("") + "_" +
        clinicians.get("cty_st_zip", "").fillna("")
    )
    grp = clinicians.groupby("practice_key")
    practices = grp.agg(
        facility_name  = ("org_lgl_nm", lambda x: x.mode().iloc[0] if not x.mode().empty else x.iloc[0]),
        pri_spec       = ("pri_spec",   lambda x: x.mode().iloc[0] if not x.mode().empty else x.iloc[0]),
        state          = ("nppes_provider_state", lambda x: x.mode().iloc[0] if not x.mode().empty else x.iloc[0]),
        citytown       = ("cty_st_zip", "first"),
        zip_code       = ("nppes_provider_zip", "first"),
        adr_ln_1       = ("adr_ln_1", "first"),
        telephone_number = ("phn_numbr", "first"),
        size           = ("npi", "count"),
        n_sites        = ("adr_ln_1", "nunique"),
        telehealth_share = ("ind_enrlt_flg", lambda x: (x == "Y").mean()),
        npi_sample     = ("npi", "first"),
        median_grad_yr = ("grd_yr", "median"),
        segment        = ("pri_spec", lambda x: x.mode().iloc[0] if not x.mode().empty else x.iloc[0]),
    ).reset_index()
    practices["median_exp_yrs"] = 2024 - practices["median_grad_yr"]
    practices["is_solo"]       = practices["n_sites"] == 1
    practices["is_multi_site"] = practices["n_sites"] > 1
    def _tier(s):
        for name, (lo, hi) in SIZE_TIERS.items():
            if lo <= s <= hi:
                return name
        return "system"
    practices["size_tier"] = practices["size"].apply(_tier)
    print(f"=== Practice Rollup ===")
    print(f"  Clinicians in   : {len(clinicians):,}")
    print(f"  Unique practices: {len(practices):,}")
    return practices

if __name__ == "__main__":
    import pandas as pd
    clinicians = pd.read_csv("clinicians_raw.csv")
    practices = rollup(clinicians)
    practices.to_csv("practices.csv", index=False)
    print("Saved: practices.csv")
