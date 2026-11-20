# Rotonda

Offline-first iPhone app for studying the Italian driving-theory exams when Italian isn't
your first language: Patente AM, A e B, C, D, CQC and the revisione exams. Helper language:
English, 简体中文 or Español.
All 3,034 vocabulary meanings include bundled Chinese and work offline without a language pack.

Read [docs/DESIGN.md](docs/DESIGN.md) for the product structure and data model.

## Layout

- `Rotonda/`: SwiftUI app (`App`, `Data`, `Design`, `Reading`, `Today`, `Chapters`,
  `Memorize`, `Quiz`, `Search`, `Profile`, `Sessions`) and bundled resources.
- `data/app/`: vocabulary overlays and curated content. SQLite build inputs are generated locally.
- `data/`: versioned official quiz text, original extracted images, translations,
  explanations, and the [content workflow](data/docs/workflow.md).
- `Scripts/import_bank_data.py`: imports every licence's official bank from data.
- `Scripts/prepare_content.py`: builds local databases from the data text sources.
- `Scripts/build_content_db.py`: builds the app content database from those inputs and overlays.

## Build

```sh
python3 Scripts/prepare_content.py   # only after data changes, or on a fresh checkout
Scripts/build.sh
python3 Scripts/test_content_translations.py
```

The content sources are included in `data/`; a fresh checkout builds without PDFs
or a sibling repository. `PATENTE_DATA` or `prepare_content.py --source` can explicitly
override the source directory. `prepare_content.py` regenerates the ignored SQLite files; run
it manually when the data changes. `Scripts/build.sh` only builds, for the simulator by default. To sign for a device, put your Apple team ID in
`team.txt` (git-ignored) at the repository root; the script picks it up. Set `DESTINATION` to
build for another target.

Requires iOS 18 (SwiftUI Translation APIs, `Tab`). Bundle identifier: `me.chichou.rotonda`.

## Privacy

Rotonda keeps study data on your device. See the [privacy policy](PRIVACY.md).

## License

Source code is licensed under the [Apache License 2.0](LICENSE). Bundled study content and
third-party data keep their own terms; see `Rotonda/Resources/VocabularyDataNotices.txt`.
