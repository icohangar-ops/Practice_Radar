"""
config.py – Practice Radar pipeline configuration
─────────────────────────────────────────────────────
Central place for all tunable parameters: specialties, states, scoring
weights, API endpoints, and schema versioning.
"""
import datetime

SPECIALTIES = [
    "OTOLARYNGOLOGY",
    "QUALIFIED SPEECH LANGUAGE PATHOLOGIST",
    "PSYCHIATRY",
]

STATES = [
    "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
    "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
    "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
    "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
    "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","DC",
]

SPECIALTY_SERVICES = {
    "ABA":      ["ABA","APPLIED BEHAVIOR","AUTISM"],
    "KETAMINE": ["KETAMINE","SPRAVATO","TMS","TRANSCRANIAL"],
}

PDC_DATASET = "mj5m-pzi6"
PDC_URL     = f"https://data.cms.gov/resource/{PDC_DATASET}.json"
NPPES_URL   = "https://npiregistry.cms.hhs.gov/api/"
PAGE_SIZE   = 500
NPPES_LIMIT = 5

WEIGHTS = {
    "size_fit":         24,
    "multi_site":       12,
    "telehealth":        8,
    "recency":          16,
    "contactability":   20,
    "specialty_service":20,
}

SIZE_FIT_TARGET = (3, 15)
SIZE_TIERS = {
    "solo":   (1,  1),
    "small":  (2,  5),
    "mid":    (6, 20),
    "large":  (21, 99),
    "system": (100, 9999),
}

SCHEMA_VERSION = "2.0"
RUN_ID = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")

if __name__ == "__main__":
    print("=== Practice Radar – Config ===")
    print(f"Specialties : {SPECIALTIES}")
    print(f"States      : {len(STATES)} (all US + DC)")
    print(f"Segments    : {len(SPECIALTIES) * len(STATES)} specialty × state pulls")
    print(f"Weights     : {WEIGHTS}")
    print(f"Run ID      : {RUN_ID}")
