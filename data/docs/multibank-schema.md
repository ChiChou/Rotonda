# Multi-bank schema (version 5)

`database/quiz.db` is an optional, ignored build artifact created from tracked
CSV, raw text, original image blobs, and translation sources. Its SQLite `user_version`
is 5. It is rebuilt from scratch; no migration or compatibility schema is required.
The earlier A/B tools are archival and independent.

## Identities

`exam_banks` separates the licence family, acquisition/re-examination purpose,
and CQC edition. A bank is the smallest selectable question pool. The ten bank
IDs are `am`, `ab`, `superiori`, `cqc_vecchio`, `cqc_nuovo`, `revisione_ab`,
`revisione_am`, `revisione_superiori`, `revisione_cqc_merci`, and
`revisione_cqc_persone`. `cqc_vecchio` is explicitly marked legacy. Listing an
attachment does not establish its current legal applicability; consumers must
choose the appropriate edition explicitly.

Questions use `<bank_id>:<official_number>`, for example `am:26067`.
The original numeric ID remains in `official_number`. Group IDs use
`<bank_id>:group:<official_id>`. Chapter IDs contain a hash of the Italian
category title; chapter ordering follows source-page order. Questions, groups,
and chapters have bank-enforcing foreign keys. Bare numeric IDs must never be
used as global primary keys or to merge revisione into conseguimento pools.

## Tables and views

| Object | Purpose |
| --- | --- |
| `exam_banks` | Selectable bank, Italian title, exam purpose, source language, legacy flag |
| `source_documents` | Exact PDF path/URL, SHA-256, retrieval/listing dates, page count |
| `chapters` | Bank-specific category titles and positions |
| `question_groups` | Official group number, chapter, first source page |
| `questions` | Bank-scoped ID, official number, group, Italian prompt, Boolean answer, page |
| `content_texts` | Deduplicated source strings keyed by normalized-text SHA-256 |
| `translations` | English/Chinese/Latin American Spanish value, origin and review status for each source string |
| `assets` | SHA-256 identity and repository-relative file path for a PDF illustration |
| `question_assets` | Question-to-figure occurrence with source page and bounding box |
| `content_manifest` | Build schema, languages, counts and translation completion |
| `localized_questions` | Questions with nullable `text_en`, `text_zh`, `text_es` and review statuses |
| `translation_coverage` | Per-bank question totals and available translation counts |

All `source_page` columns are **one-based PDF page numbers**. Figure coordinates
use PDF points measured from the top left, as recorded by pdfplumber. Intermediate
`source/banks/<bank>/figures.csv` pages are zero-based and converted during build.
An asset may occur many times. `question_assets` records each occurrence rather
than assuming a single shared group diagram.

Italian text is retained as extracted, including source typography and errors.
Deduplication normalizes Unicode compatibility, curly apostrophes and whitespace;
it does not remove punctuation or alter words. Identical source strings can reuse
translations across banks. Source answers are never inferred from translations.
Questions with identical wording can have different figures or answers. Only
their translations are deduplicated; question records and figure occurrences
remain separate.
Generated translations have `review_status='draft'`; inherited A/B translations
have `review_status='existing'`, which is provenance rather than a claim of a new
human review. Languages use `en`, `zh-Hans`, and `es-419`; localized columns are `text_en`,
`text_zh`, and `text_es`. Spanish CSV batches start as draft and require a separate complete batch review before becoming reviewed. Missing translations are SQL NULL.

After a separate GPT-6.1 Terra review of both target languages against the Italian,
verified generated translations use `review_status='reviewed'`. Translation JSONL
files retain reviewer/date/content fingerprints, with per-batch evidence and
correction histories in `reviews/translation-review/`. The importer rejects
reviewed wording that differs from its fingerprint or recorded batch evidence.
Spanish reports in `reviews/spanish-review/` bind the final CSV, Italian source
wording, and original draft hashes; correction histories retain before/after
wording and reasons. Edited source or target text invalidates the batch review.
`--require-reviewed` requires completed semantic-review evidence for every new
bilingual string while leaving inherited A/B provenance unchanged.

`content_manifest.content_hash` hashes the deterministically ordered content,
source metadata, translations and figure links. `content_version` combines the
source retrieval date with a hash prefix, so translation changes create a new
version even when the PDFs remain unchanged. Clients and explanation servers
should compare this version/hash before treating their data as interchangeable.
The build report also records the exact database file SHA-256.

## Queries

```sql
SELECT id, text_it, text_en, text_zh, answer, source_page
FROM localized_questions
WHERE bank_id = 'revisione_am'
ORDER BY official_number;

SELECT a.path, qa.source_page, qa.x0, qa.top, qa.x1, qa.bottom
FROM question_assets qa JOIN assets a ON a.id = qa.asset_id
WHERE qa.question_id = 'am:26067';

SELECT * FROM translation_coverage ORDER BY bank_id;
```

Rebuild verifies extracted-file/asset checksums, one-to-one question and answer token
counts, nonempty text, unique IDs, translation hashes, cross-bank referential
integrity, and SQLite integrity before replacing the final database. Pass
`--require-translations` to require all three target languages for every question and category.

The official A/B PDF yields 7,020 selectable-text questions. The legacy application
bank had 7,106; the 86 legacy IDs absent from the current PDF were removed from the
archived A/B sources, so both now hold the same 7,020 questions. See the existing
extraction comparison review for the removed IDs.

## Optional indexes

Primary and unique constraints create the indexes needed for identity and
uniqueness. Additional indexes in `schema/indexes.sql` are opt-in with
`build_database.py --with-indexes`; use query plans and measured application
queries to decide whether they are useful. There is no required search index or
word dictionary in the main bundle.

## Explanation packs (v5)

`question_explanations(question_id, language, text)` stores Italian and helper-language
explanations as rows. Sources are `explanations/<bank>/<BCP-47>.jsonl`. Existing A/B
rows keep their legacy status; new rows require source fingerprints and accepted review
bundles under `reviews/explanations/`. A source, answer, figure, translation, or final
explanation change invalidates that evidence. The app accepts a new question's
explanations only when Italian and every configured helper language are present.
Missing content is reported by `content_workflow.py coverage`; it is never manufactured
from a verdict alone. This does not add French/German quiz source modes.
