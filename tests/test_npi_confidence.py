"""NPI confidence levels + review flag, exercised offline (no network)."""
import pandas as pd
from openpyxl import Workbook

from npi_append import npi_append


def test_confidence_levels_and_review_flag(tmp_path):
    """Rows land in exactly one of org_npi / individual_npi_only / unmatched,
    and unmatched rows set npi_review_flag (the README's dirty-row guard).
    All rows are practice_radar, so the live NPPES lookup is never hit;
    npi_append only shutil-copies the source workbook."""
    src = tmp_path / "src.xlsx"
    Workbook().save(src)

    df = pd.DataFrame(
        {
            "facility_name": ["Org NPI Practice", "Individual Only Practice", "Unmatched Practice"],
            "npi_org": ["1234567893", None, None],
            "npi_sample": [None, 9876543210, None],
            "tms_source": ["practice_radar"] * 3,
        }
    )
    out = tmp_path / "out.xlsx"
    result, ready, review = npi_append(df, wb_src=str(src), wb_out=str(out))

    assert result["npi_match_confidence"].tolist() == ["org_npi", "individual_npi_only", "unmatched"]
    assert result["npi_review_flag"].tolist() == [False, False, True]
    assert len(ready) == 2 and len(review) == 1
