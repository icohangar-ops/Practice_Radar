# Practice Radar

> **A data-driven target list of 18,095 US healthcare practices** — built for
> commercial outreach in ENT, Speech-Language Pathology, Psychiatry, TMS,
> and Ketamine therapy.

**Repo:** https://github.com/icohangar-ops/Practice_Radar

---

## What this does

Practice Radar ingests clinician-level data from CMS, aggregates it into
practice-level records, enriches with NPPES NPI numbers, scores every
practice on six commercial-fit criteria, merges in 830 manually curated
TMS / behavioral-health providers, and exports a fully-formed HubSpot-ready
Excel workbook — with NPI validated and dirty rows flagged for review.

---

## Pipeline architecture

```
config.py          – Specialties, states, weights, API endpoints
     │
ingest.py          – CMS PDC API → 85,586 clinician rows
     │
practice_rollup.py – Aggregate clinicians → 17,265 practices
     │
nppes_enrich.py    – NPPES NPI-2 lookup for top 400 practices
     │
score.py           – Score 0–100 on 6 weighted criteria
     │
publish.py         – Export target_list.csv + manifest.json
     │
load_tms.py        – Load TMS Excel (830 rows, 5 categories)
     │
append_tms.py      – Merge TMS into combined 18,095-row list
     │
npi_append.py      – NPI lookup for TMS rows + HubSpot sheets
     │
cover_memo.py      – Styled Excel cover sheet
```

---

## Data sources

| Source | Description | Rows |
|--------|-------------|------|
| **CMS PDC API** | Doctors & Clinicians dataset (doctors.cms.gov) | 85,586 clinicians → 17,265 practices |
| **NPPES REST API** | NPI Registry — org NPI-2, authorized officials, FHIR endpoints | Top 400 practices enriched |
| **TMS Market Excel** | Manually curated: funded entities, practices, ketamine clinics, PE-backed providers | 830 rows |

---

## Scoring methodology

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Size fit | 24 pts | Practice size 3–15 clinicians = ideal sweet spot |
| Multi-site | 12 pts | Multiple location presence |
| Telehealth | 8 pts | % of clinicians with telehealth enrollment |
| Recency | 16 pts | Clinician graduation recency (proxy for modernity) |
| Contactability | 20 pts | Has phone number + website |
| Specialty service | 20 pts | ABA, Ketamine, or TMS signal in practice name |

Scores range **0–100**. CMS practices scored 4.8–71.8 (mean 28.5).
TMS rows use a priority score (0–100) based on source tier and service breadth.

---

## NPI methodology

| Row type | NPI source | Coverage |
|----------|-----------|---------|
| CMS rows | NPPES Enrich (top 400 by size) | 300/400 org NPI-2 (75%) |
| CMS rows | `npi_sample` individual NPI-1 | ~100% coverage |
| TMS rows | Live NPPES NPI-2 API by name | 365/830 (44%) |

**npi_match_confidence** levels:
- `org_npi` — NPI-2 confirmed ✅
- `individual_npi_only` — NPI-1 from CMS roster (no org NPI) ⚠️
- `unmatched` — no NPI found; **do not import to HubSpot without manual lookup** ❌

---

## HubSpot output

The final workbook `target_list_npi.xlsx` contains:

| Sheet | Rows | Purpose |
|-------|------|---------|
| **HubSpot – Ready** | ~17,630 | NPI confirmed — safe to import |
| **HubSpot – NPI Review** | ~465 | Unmatched — manual NPI lookup required |
| All Targets | 18,095 | Full unified list ranked by score |
| Practice Radar | 17,265 | CMS-sourced practices only |
| TMS Appended | 830 | TMS market research rows |
| + 5 per-source tabs | — | Filtered by data source |

> ⚠️ **Data quality warning:** Do not bulk-import the "NPI Review" sheet.
> Records without a confirmed NPI cannot be reliably deduplicated in HubSpot
> and will create dirty data. Verify NPI manually via
> [NPPES NPI Registry](https://npiregistry.cms.hhs.gov/) before importing.

---

## Setup & usage

### Requirements
- Python 3.10+
- `tms_market_data.xlsx` placed in the working directory

### Install
```bash
git clone https://github.com/icohangar-ops/Practice_Radar.git
cd Practice_Radar
pip install -r requirements.txt
```

### Run
```bash
python run_pipeline.py
```

Or run steps individually:
```bash
python config.py      # verify config
python ingest.py      # fetch CMS data  (~10 min, 153 API segments)
python practice_rollup.py
python nppes_enrich.py  # NPPES enrichment (~1 min)
python score.py
python publish.py
python load_tms.py
python append_tms.py
python npi_append.py    # TMS NPI lookup (~2 min for 830 rows)
python cover_memo.py    # optional styled cover sheet
```

---

## File structure

```
Practice_Radar/
├── config.py
├── ingest.py
├── practice_rollup.py
├── nppes_enrich.py
├── score.py
├── publish.py
├── load_tms.py
├── append_tms.py
├── npi_append.py
├── cover_memo.py
├── run_pipeline.py
├── requirements.txt
├── .gitignore
└── README.md
```

> Output files (`*.csv`, `*.xlsx`, `*.json`) are gitignored — they are
> generated locally when you run the pipeline. Two committed exceptions
> record the last published run as snapshots: `manifest.json` and
> `target_list_npi.xlsx` are checked in deliberately.

---

## Evidence matrix

Every capability claim in this file is backed by
[`evidence/matrix.yaml`](evidence/matrix.yaml); CI refuses builds while any
row is unverifiable. The verifier (`tools/verify_evidence_matrix.py`,
vendored byte-identical from the `consensus-hardening-protocol` standard
kit — verifier v1.0.0, vendored from kit commit `88067e4`) re-executes
every row's evidence on each run and prints a
`EVIDENCE MATRIX: VERIFIED (n/n)` verdict. A red `evidence-matrix` job
means a claim in this file is not currently evidence-backed.

Run it locally:

```bash
python3 tools/verify_evidence_matrix.py
```

---

## Known limitations

- **NPPES name matching is fuzzy** — org name lookup hits ~75% for CMS top-400 and ~44% for TMS rows.
  Mismatches are possible; treat `org_npi` as a strong signal, not a guaranteed key.
- **CMS data latency** — PDC dataset lags real-world enrollment by 3–6 months.
- **TMS rows have no CMS anchor** — address, phone, and ZIP are often missing.
  These records should be enriched from the source before HubSpot import.
- **Rate limits** — NPPES API is public and unauthenticated; the pipeline uses
  0.08–0.1 s delays per call. Run during off-peak hours for large batches.
