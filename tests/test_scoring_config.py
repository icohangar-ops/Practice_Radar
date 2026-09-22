"""Scoring methodology claims: weights in config match README table and manifest."""
import json
from pathlib import Path

import config

ROOT = Path(__file__).resolve().parent.parent


def test_weights_sum_to_100():
    """Six criteria, weights summing to 100 (README scoring table)."""
    assert sum(config.WEIGHTS.values()) == 100
    assert config.WEIGHTS == {
        "size_fit": 24,
        "multi_site": 12,
        "telehealth": 8,
        "recency": 16,
        "contactability": 20,
        "specialty_service": 20,
    }


def test_specialties_match_config():
    """The three target specialties (README header / data sources)."""
    assert config.SPECIALTIES == [
        "OTOLARYNGOLOGY",
        "QUALIFIED SPEECH LANGUAGE PATHOLOGIST",
        "PSYCHIATRY",
    ]


def test_manifest_scoring_weights_match_config():
    """The committed manifest's scoring weights match config. publish.py writes
    config.WEIGHTS under key 'specialty_service'; the committed manifest (an
    older publish revision) names the same criterion 'specialty_service_fit'."""
    manifest = json.loads((ROOT / "manifest.json").read_text())
    renamed = {
        ("specialty_service_fit" if key == "specialty_service" else key): weight
        for key, weight in config.WEIGHTS.items()
    }
    assert renamed == manifest["scoring_weights"]
