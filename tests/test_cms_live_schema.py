"""CMS PDC live-schema claims: new endpoint, live column names, complete paging."""
import pandas as pd
import pytest

import config
import ingest
from practice_rollup import rollup


def test_pdc_url_uses_datastore_api():
    """The retired Socrata endpoint (/resource/mj5m-pzi6.json) returns HTTP 410."""
    assert "/provider-data/api/1/datastore/query/mj5m-pzi6/0" in config.PDC_URL
    assert "/resource/" not in config.PDC_URL


class _Resp:
    def __init__(self, payload, content_type="application/json", status=200):
        self._payload, self.status_code = payload, status
        self.headers = {"Content-Type": content_type}

    def raise_for_status(self):
        if self.status_code >= 400:
            import requests
            raise requests.HTTPError(str(self.status_code))

    def json(self):
        return self._payload


class _Session:
    def __init__(self, responses):
        self.responses, self.bodies = list(responses), []

    def post(self, url, json, timeout):
        self.bodies.append(json)
        return self.responses.pop(0)


@pytest.fixture(autouse=True)
def _no_sleep(monkeypatch):
    monkeypatch.setattr(ingest.time, "sleep", lambda s: None)


def test_fetch_segment_pages_until_server_count():
    s = _Session([_Resp({"results": [{"npi": "1"}, {"npi": "2"}], "count": 3}),
                  _Resp({"results": [{"npi": "3"}], "count": 3})])
    rows = ingest.fetch_segment("PSYCHIATRY", "RI", page_size=2, session=s)
    assert [r["npi"] for r in rows] == ["1", "2", "3"]
    assert [b["offset"] for b in s.bodies] == [0, 2]
    assert s.bodies[0]["conditions"][1] == {"property": "state", "value": "RI", "operator": "="}


def test_fetch_segment_retries_html_error_page():
    s = _Session([_Resp("<html>Temporarily Unavailable</html>", content_type="text/html"),
                  _Resp({"results": [{"npi": "1"}], "count": 1})])
    assert len(ingest.fetch_segment("PSYCHIATRY", "RI", session=s)) == 1


def test_fetch_segment_raises_instead_of_truncating():
    s = _Session([_Resp({"results": [{"npi": "1"}], "count": 2})]
                 + [_Resp({}, status=503)] * config.PDC_RETRIES)
    with pytest.raises(ingest.IngestError):
        ingest.fetch_segment("PSYCHIATRY", "RI", page_size=1, session=s)


def test_rollup_reads_live_column_names():
    rows = pd.DataFrame([
        dict(npi="1", org_pac_id="P1", facility_name="ACME PSYCHIATRY", pri_spec="PSYCHIATRY",
             state="RI", citytown="PROVIDENCE", zip_code="029031234", adr_ln_1="1 MAIN ST",
             telephone_number="4015550100", telehlth="Y", grd_yr=2010),
        dict(npi="2", org_pac_id="P1", facility_name="ACME PSYCHIATRY", pri_spec="PSYCHIATRY",
             state="RI", citytown="PROVIDENCE", zip_code="029031234", adr_ln_1="2 MAIN ST",
             telephone_number="4015550100", telehlth="", grd_yr=2016),
    ])
    p = rollup(rows).iloc[0]
    assert p["facility_name"] == "ACME PSYCHIATRY"
    assert p["state"] == "RI" and p["citytown"] == "PROVIDENCE"
    assert p["telephone_number"] == "4015550100"
    assert p["telehealth_share"] == 0.5
    assert p["n_sites"] == 2 and p["size"] == 2
