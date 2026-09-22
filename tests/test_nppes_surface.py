"""NPPES enrichment claim: top-400 practices by size."""
import inspect

from nppes_enrich import enrich


def test_enrich_defaults_to_top_400():
    """nppes_enrich.enrich queries NPPES for the top 400 practices by size."""
    params = inspect.signature(enrich).parameters
    assert params["n_candidates"].default == 400
