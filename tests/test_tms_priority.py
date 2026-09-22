"""TMS priority-score scale claim: source tier + service breadth, 0-100."""
from append_tms import SERVICE_BREADTH, SOURCE_TIER, tms_priority


def test_tms_priority_scale_0_to_100():
    """The priority score spans exactly 0-100: tier and breadth tables plus
    the three bonuses (website, contact, multi-state footprint) peak at 100
    and never go below 0."""
    combos = [
        tms_priority(tier, breadth, website, contact, footprint)
        for tier in SOURCE_TIER
        for breadth in SERVICE_BREADTH
        for website in (None, "https://example.com")
        for contact in (None, "Contact")
        for footprint in (None, "TX, OK")
    ]
    assert min(combos) >= 0
    assert max(combos) == 100
