# data

Source data for Italian driving-theory quizzes: AM, A/B, Superiori, CQC, and licence re-examination (revisione). English and Simplified Chinese translations are retained with their review evidence. Latin American Spanish (`es-419`) quiz translations retain their historical review evidence. New explanation work uses staged GPT-6.1 Terra generation without a review stage: Italian first, then one helper language at a time. Corrections retain their original wording and reasons.

Git tracks the source of truth. Original official PDFs are manually placed in an ignored input folder; application asset copies, SQLite bundles, exports, and translation task inputs are reproducible outputs.

## Layout

| Path | Contents |
| --- | --- |
| `source/official/manifest.json` | Official URLs, PDF names, retrieval date, SHA-256 checksums, audited counts, unavailable attachments |
| `inputs/official/2026-11-14/` | Ignored, manually supplied original Italian PDFs with descriptive names such as `conseguimento-ab-it.pdf` |
| `source/banks/<bank>/questions.csv` | One question per row, ordered by official number |
| `source/banks/<bank>/groups.csv` | Group/category records, with original source ordering |
| `source/banks/<bank>/images.csv` | All embedded image occurrences, including logos |
| `source/banks/<bank>/figures.csv` | Question illustration occurrences |
| `source/banks/<bank>/raw.txt` | Raw `pdftotext -layout` output, including page breaks |
| `source/banks/<bank>/extraction.json` | PDF identity and extracted file checksums |
| `source/images/` | Deduplicated, original PNG/JPEG blobs as `<sha256>.<format>` |
| `translations/multibank/` | English/Chinese translations and row review provenance |
| `translations/es-419/` | Latin American Spanish translation CSV batches |
| `reviews/translation-review/` | Evidence binding English/Chinese review status to exact wording |
| `reviews/spanish-review/` | Historical Spanish review evidence, source/file fingerprints, and correction history |
| `explanations/<bank>/<language>.jsonl` | Canonical Italian and localized explanation text |
| `provenance/explanations/` | Source/output fingerprints, frozen Italian baselines, and actual generation runs; new output is unreviewed |
| `source/banks/ab/` | Canonical official A/B questions and groups; no duplicate legacy source |
| `facts/ab/`, `app/ab_compatibility.json` | Curated study facts, stable image names and application text overrides |
| `schema/`, `scripts/`, `tests/`, `docs/` | Optional SQLite schema, tools, regression checks, and format documentation |
| `assets/`, `database/`, `exports/` | Ignored application asset copies and generated bundles |

CSV files use UTF-8, a header, standard quoting, and LF line endings. They retain the original field names and Italian wording, including false assertions. Pages in source records are zero-based; the database converts them to one-based pages. Fixed-schema CSV avoids repeating keys for every record. Translation files with varying review metadata remain JSONL.

Images stay as small binary blobs in Git. Their SHA-256 names deduplicate repeated PDF occurrences, and `.jpg`/`.jpeg` aliases share one blob; CSV files hold the occurrence metadata and question links. Builds copy the referenced originals into ignored application asset folders.

## Official sources

The [official portal listing](https://www.ilportaledellautomobilista.it/web/portale-automobilista/-/quiz-per-le-patenti-am-a-b-superiori-e-cqc) was checked on 2026-11-14 and displays an update date of 2026-10-30. All ten Italian PDFs were freshly fetched and verified against the recorded checksums. A listing date does not establish an attachment's edition or applicability to an exam.

| Bank | Questions |
| --- | ---: |
| `am` | 2,035 |
| `ab` | 7,020 |
| `superiori` | 3,456 |
| `cqc_vecchio` | 4,946 |
| `cqc_nuovo` | 5,528 |
| `revisione_ab` | 1,814 |
| `revisione_am` | 1,581 |
| `revisione_superiori` | 2,323 |
| `revisione_cqc_merci` | 2,485 |
| `revisione_cqc_persone` | 2,605 |
| **Total** | **33,793** |

CQC editions and all revisione banks stay separate. The old CQC list is marked legacy. The CAP link returned HTTP 404 and is recorded as unavailable. The generic revision ZIP is not imported because five explicit Italian revisione PDFs provide the bank-specific sources.

## Manual intake and extraction

PDF extraction needs Python 3.11+, Poppler (`pdftotext`, `pdfimages`), and `pdfplumber`. The scripts also discover the bundled Codex Poppler runtime when available.

```sh
python3 -m pip install -r requirements.txt
# macOS: brew install poppler
# Manually save the exact official attachments at the paths in the manifest.
python3 scripts/verify_official_pdfs.py
python3 scripts/extract_official_banks.py
# Also regenerate images and their occurrence records when auditing a new source:
python3 scripts/extract_official_banks.py --refresh-images
```

No script downloads PDFs. Use the official URLs and filenames in the manifest; do
not use reprinted, translated, OCR-rewritten, or third-party PDFs. Verification checks
the PDF header, byte count, and SHA-256 without changing the files or manifest.
For a new edition, manually supply a new dated input, audit its identity and counts,
then update the manifest explicitly. Extraction refreshes images when the PDF changes.
A normal app build uses tracked text and image sources and requires no PDF tooling.

See [the workflow and copyable prompts](docs/workflow.md) for bounded lower-cost worker
extraction, per-language quiz translation, Italian explanation authoring, and per-language explanation localization. The repository
skills live in `../.agents/skills/`. [Coverage](reviews/coverage.json) records gaps
without substituting empty or generic explanations. All ten supplied banks have
complete quiz translations in the three current helper languages. All 22,998 distinct
questions (33,793 bank memberships) also have Italian, English, Simplified Chinese
and Latin American Spanish explanations. Completion is checked with
`content_workflow.py coverage --require-translations --require-explanations`.
New explanation output is generated without semantic review; historical reviewed
content is retained. Localizations bind the actual Italian explanation version,
and source/answer/figure identity is required for reuse. Typography-only reuse
normalizes apostrophes and whitespace while preserving words, numbers and verdicts.

## Optional database and exports

The tracked CSV and image sources are sufficient for consumers that do not need SQLite. Building a database requires only Python's standard library and the tracked files; no PDF download or Poppler installation is required.

```sh
python3 scripts/build_database.py
python3 scripts/export_quiz.py
python3 -m unittest discover -s tests
```

The build creates `database/quiz.db` from scratch using [schema/quiz.sql](schema/quiz.sql). The current generated schema is v5, with per-language question explanations. Schema changes may break consumers; there is no migration layer. It validates extraction checksums, raw-text/CSV agreement, audited question/group counts, image bytes and links, translation provenance, foreign keys, and SQLite integrity before replacing the output. The generated report is `reviews/multibank-build.json`.

**Extra database indexes are optional.** SQLite's primary/unique-key indexes enforce identity and already serve ID lookups. No separate search database or word dictionary is needed. Use `--with-indexes` only if bank/group or text lookup queries justify the additional indexes in `schema/indexes.sql`. The default build omits them. See [the schema contract](docs/multibank-schema.md).

The localized view and exports expose `text_en`, `text_zh`, and `text_es`, plus language-specific review status. Missing translations are NULL. Use `python3 scripts/spanish_translations.py` for current Spanish coverage. `--require-translations` requires all three target languages; `--require-reviewed` additionally requires every newly generated translation to have review evidence. Reviewed Spanish batches require matching Italian-source and final-CSV fingerprints plus correction history that reconstructs the original draft.

Translation task inputs are generated and ignored:

```sh
python3 scripts/prepare_bank_translations.py
python3 scripts/check_bank_translations.py --require-complete --require-reviewed
python3 scripts/spanish_translations.py --prepare
python3 scripts/spanish_translations.py --require-complete --require-reviewed
```

The English/Chinese checker covers those languages; Spanish has its own coverage check. Semantic review is separate from structural validation. Existing English/Chinese audits remain bound to their exact files and fingerprints; Spanish review evidence is separate. Edited Italian or Spanish wording invalidates the corresponding Spanish review.

## A/B application adapter

A/B uses the canonical official bank CSVs and shared multilingual packs. The duplicate
`source/legacy/ab` and `translations/ab` inputs have been removed. Existing 7,020-question
explanations, curated study facts and stable application identifiers are preserved.
`app/ab_compatibility.json` retains image-name mappings and only the curated text
and typography differences required by the application. Original comparison and
image-audit evidence remains under `reviews/`.

```sh
python3 scripts/build_ab_database.py
python3 scripts/export_ab_quiz.py
```

The adapter generates SQLite and application image copies from tracked text/images;
these outputs are ignored. It does not restore a second legacy source bank.

## Monorepo provenance

Imported from `ChiChou/patente-data` at
`bead8850f3732894f3d9875dba8adcd8ef8da68b` (the `ab-explanations` checkout).
The tracked tree was copied into `Rotonda/data` without nested Git metadata,
databases, or generated asset directories. Historical review reports retain their
original paths and timestamps as evidence. The sibling checkout remains a local
history backup; the app no longer reads it. Future changes belong in this monorepo.

The duplicate `source/legacy/ab` and `translations/ab` inputs were removed. The A/B
app adapter reads canonical bank CSVs and multilingual packs. Stable image names
and only the differing curated text are retained in `app/ab_compatibility.json`.
Historical image audits live under `reviews/extraction/ab/archived-image-audit/`.
The separate historical CQC bank is retained.
