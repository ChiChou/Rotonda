# Build and commits

- Build with `Scripts/build.sh` (signing team from git-ignored `team.txt`; never commit it) and
  test in the simulator after each batch of changes; shut the simulator down when done.
- Use a physical device only when asked. Never commit device names or identifiers; if
  deployment is blocked, report the blocker instead of switching devices.
- Keep build products and logs outside the repository. Commit each completed logical change.

# Content and data

- SQLite databases are generated and not committed. After data changes, run
  `python3 Scripts/prepare_content.py`; the build does not.
- Data tasks run on a lower-cost worker model (`--model`, see `data/scripts/worker_models.py`),
  never a frontier model.
- Progress is per licence (`ProgressStore.storeURL(for:)`), never per language.
- Query content through `ContentStore`, which filters by `Preferences.licence`. Take exam format
  from `ContentStore.examRules`, never hard-coded.
- Helper-language text is per-language rows (`*_texts`, `Localized`); switch over
  `HelperLanguage`, never add per-language columns.
- UI strings live in `Rotonda/Localizable.xcstrings`. Check Apple Translation on a device; it
  doesn't run in the simulator.

# Interface copy

- Keep copy concise: **no descriptive subtitles or persistent gesture hints when the action is
  clear**, no decorative arrows on buttons.
- No middle-dot separators (U+00B7) or numbered section prefixes; group with titles and layout.
- Never promise the learner will pass the exam.

# Navigation

- Browsing (questions, vocabulary, facts, signs) pages horizontally; vertical scrolling only
  reads long content. Keep left-edge swipe Back.
- Study and quiz feedback advance by horizontal swipe with accessibility actions, no fixed Next
  bar; answer and bookmark controls stay in the scrolling content.
- iPad pagers and sessions add side-edge previous/next buttons (`pagerEdgeButtons`).
- Only full-screen cards swipe as a whole. An embedded card (Today's daily challenge) pages
  inside its own clipped frame, without a Next button, and follows the visible page's height.

# Translations

- Translations sit below the Italian in a smaller secondary font and never replace it. Keep
  VERO/FALSO pills and answer buttons in Italian.
- Visibility is one global setting (`Preferences.showsTranslations`), toggled by one `translate`
  control per screen in the navigation or session top bar (`translationToggle()`,
  `SessionTopBar`); iPad split-view lists use `TranslationToggleItem`. Never in cards, rows or
  headers.
- Hiding translations must not change layout: keep them measured, without hit testing or
  accessibility.
- Vocabulary uses `GlossText`, in the selected helper language only, with no fallback.
- Quiz answer choices stay visible regardless of translation visibility; no toggle on the word
  quiz prompt.

# Mock exam

- Landscape only on every device, in the official layout; no responsive variants. iPad uses
  `UIRequiresFullScreen`, and the exam waits for landscape if rotation is refused.
