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
01_config.py          – Specialties, states, weights, API endpoints
     │
02_ingest.py          – CMS PDC API → 85,586 clinician rows
     │
03_practice_rollup.py – Aggregate clinicians → 17,265 practices
     │
04_nppes_enrich.py    – NPPES NPI-2 lookup for top 400 practices
     │
05_score.py           – Score 0–100 on 6 weighted criteria
     │
06_publish.py         – Export target_list.csv + manifest.json
     │
07_load_tms.py        – Load TMS Excel (830 rows, 5 categories)
     │
08_append_tms.py      – Merge TMS into combined 18,095-row list
     │
09_npi_append.py      – NPI lookup for TMS rows + HubSpot sheets
     │
10_cover_memo.py      – Styled Excel cover sheet
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
python 01_config.py      # verify config
python 02_ingest.py      # fetch CMS data  (~10 min, 153 API segments)
python 03_practice_rollup.py
python 04_nppes_enrich.py  # NPPES enrichment (~1 min)
python 05_score.py
python 06_publish.py
python 07_load_tms.py
python 08_append_tms.py
python 09_npi_append.py    # TMS NPI lookup (~2 min for 830 rows)
python 10_cover_memo.py    # optional styled cover sheet
```

---

## File structure

```
Practice_Radar/
├── 01_config.py
├── 02_ingest.py
├── 03_practice_rollup.py
├── 04_nppes_enrich.py
├── 05_score.py
├── 06_publish.py
├── 07_load_tms.py
├── 08_append_tms.py
├── 09_npi_append.py
├── 10_cover_memo.py
├── run_pipeline.py
├── requirements.txt
├── .gitignore
└── README.md
```

> Output files (`*.csv`, `*.xlsx`, `*.json`) are gitignored — they are
> generated locally when you run the pipeline.

---

## Known limitations

- **NPPES name matching is fuzzy** — org name lookup hits ~75% for CMS top-400 and ~44% for TMS rows.
  Mismatches are possible; treat `org_npi` as a strong signal, not a guaranteed key.
- **CMS data latency** — PDC dataset lags real-world enrollment by 3–6 months.
- **TMS rows have no CMS anchor** — address, phone, and ZIP are often missing.
  These records should be enriched from the source before HubSpot import.
- **Rate limits** — NPPES API is public and unauthenticated; the pipeline uses
  0.08–0.1 s delays per call. Run during off-peak hours for large batches.
