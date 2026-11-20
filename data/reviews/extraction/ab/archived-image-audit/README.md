# Official PDF image extraction

`placements.jsonl` and `metadata.json` indexes every embedded image placement in the official
`210926_Conseguimento A-B italiano.pdf` downloaded on 2026-11-04. Extracted
files are restored under the ignored `pdf_images/assets/` by `python3 scripts/source_files.py`; the index records the source PDF SHA-256, PDF page,
image object, dimensions, encoded format, extracted asset path, and asset SHA-256.

The index also joins exact asset SHA-256 values to files now in `assets/ab/`
and lists related legacy question IDs from `database/ab/quiz.db`. `direct_question_ids`
come from `questions.image`. `group_question_ids` come from
`question_groups.image` and include all questions in those groups. The two
relations are separate because the canonical database can assign an image at
either level. These joins identify reusable assets; a repeated illustration
can therefore relate to many question IDs and does not by itself establish
which question occurrence it accompanied in the PDF.

To regenerate from a later PDF, first restore the legacy inputs and build the archived A/B database using the commands in the root README:

```sh
python3 scripts/extract_pdf_images.py /path/to/official.pdf
```

The script uses Poppler's `pdfimages` and writes the ignored `pdf_images/` directory by default.
Use `--output DIR` to write elsewhere.
