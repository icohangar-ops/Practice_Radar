"""
score.py – Practice scoring (0-100)
──────────────────────────────────────
Scores every practice on 6 weighted criteria:
  - size_fit        (24 pts) – practice size vs. sweet spot
  - multi_site      (12 pts) – multi-location presence
  - telehealth       (8 pts) – telehealth adoption
  - recency         (16 pts) – clinician graduation recency
  - contactability  (20 pts) – phone + website completeness
  - specialty_service (20 pts) – ABA / Ketamine signal detection
"""
import pandas as pd
import numpy as np
from config import SPECIALTY_SERVICES, WEIGHTS, SIZE_FIT_TARGET

def score(enriched_practices):
    df = enriched_practices.copy()
    lo, hi = SIZE_FIT_TARGET

    # size_fit
    df["sc_size_fit"] = df["size"].apply(
        lambda s: WEIGHTS["size_fit"] if lo <= s <= hi
        else WEIGHTS["size_fit"] * 0.5 if s < lo
        else max(0, WEIGHTS["size_fit"] * (1 - (s - hi) / hi))
    )
    # multi_site
    df["sc_multi_site"] = df["is_multi_site"].astype(float) * WEIGHTS["multi_site"]

    # telehealth
    df["sc_telehealth"] = (df["telehealth_share"].fillna(0) * WEIGHTS["telehealth"]).clip(upper=WEIGHTS["telehealth"])

    # recency
    yr_max = df["median_grad_yr"].max()
    yr_min = df["median_grad_yr"].min()
    yr_range = yr_max - yr_min if yr_max != yr_min else 1
    df["sc_recency"] = ((df["median_grad_yr"].fillna(yr_min) - yr_min) / yr_range * WEIGHTS["recency"]).clip(upper=WEIGHTS["recency"])

    # contactability
    has_phone   = (df["telephone_number"].notna() & (df["telephone_number"].astype(str).str.strip() != "")).astype(float)
    has_website = (df["website"].notna() & (df["website"].astype(str).str.strip() != "")).astype(float)
    df["sc_contactability"] = (has_phone * 0.5 + has_website * 0.5) * WEIGHTS["contactability"]

    # specialty_service
    def detect_service(name):
        name = str(name).upper()
        for svc, kws in SPECIALTY_SERVICES.items():
            if any(kw in name for kw in kws):
                return svc
        return "—"
    df["specialty_service"] = df["facility_name"].apply(detect_service)
    df["sc_specialty_service"] = df["specialty_service"].apply(
        lambda s: WEIGHTS["specialty_service"] if s != "—" else 0
    )

    df["total_score"] = (
        df["sc_size_fit"] + df["sc_multi_site"] + df["sc_telehealth"] +
        df["sc_recency"]  + df["sc_contactability"] + df["sc_specialty_service"]
    ).round(1)

    scored = df.sort_values("total_score", ascending=False).reset_index(drop=True)
    print(f"=== Score ===")
    print(f"  Scored   : {len(scored):,}")
    print(f"  Range    : {scored['total_score'].min()} – {scored['total_score'].max()}")
    print(f"  Mean     : {scored['total_score'].mean():.1f}")
    return scored

if __name__ == "__main__":
    enriched = pd.read_csv("enriched_practices.csv")
    scored = score(enriched)
    scored.to_csv("scored_practices.csv", index=False)
    print("Saved: scored_practices.csv")
