# Rotonda — design

Rotonda (环岛) is the redesign of Patente30: an offline-first iPhone app that helps
people who don't speak Italian as a first language study for the Italian driving-theory
exams: category B first, and AM, C, D, CQC and the revisione exams (see Licences). It has two jobs that the old app mixed together:

1. **Get the content into memory**: words, numbers, rules and the statements themselves.
2. **Get past the language barrier**: every Italian sentence can be understood without
   leaving the screen, while the learner moves step by step toward reading Italian only.

## Who it is for

- English speakers first, then Mandarin and Spanish speakers. Every UI string, fact
  headline, explanation and question has Chinese; every UI string and question has
  Latin American Spanish. The *helper language* is chosen in-app and
  doesn't depend on the iPhone's language, so a Chinese learner with an English phone
  still gets Chinese help.
- Two study styles:
  - **In order**: chapter by chapter, on a sofa or at a desk.
  - **In fragments**: 2–5 minutes on a tram, or a whole offline flight. Every session
    is full-screen, saves each answer immediately, and can be closed at any time.

## Navigation (five tabs, three levels at most)

Each chapter starts with **Learn & quiz**. The Quiz tab groups the mock exam,
chapter learning, and quick practice, with compact actions and summaries.

| Tab | Intent | Contents |
|---|---|---|
| **Today** | "I have a few minutes" | Italian greeting, next-chapter *Learn & quiz* card, *Continue*, due reviews, compact progress, four quick sessions (Quick quiz, Words, Word quiz, Listen), Mock exam and week chart |
| **Learn** | "I study in order" | 25 chapters in compact grouped rows with progress rings and counts; translation visibility sits in the toolbar. Chapter titles on chapter pages and Quiz cards always show both languages. A chapter page leads with **Learn & quiz**, then grouped **study material** (key words and key facts with inline study actions, signs gallery, read-through with answers), then **more practice** (quiz, word quiz, numbers quiz, listen, fix mistakes). Swipe sideways to move between chapters. |
| **Quiz** | "Test me" | compact **Mock exam** → **Learn & quiz** (next chapter + all chapters) → **Quick quizzes** (mixed, mistakes, signs & pictures, word quiz, numbers quiz, saved) → history |
| **Memorize** | "Drill what I must know" | compact due summary with *Review*; the key-word ladder and inline *Learn* action grouped with word libraries; six fact decks; mistakes, saved questions, all signs |
| **Search** | "What does this mean?" | Italian and the selected helper language, accent-insensitive, across words, questions and facts; compact example buttons and question previews opening full details; online dictionaries when connected |

Progress and settings sit behind the profile button on Today, because people come for
them rarely.

Sessions are not stacked screens. Each one is a full-screen cover started from anywhere
through `SessionCoordinator`, so the same Quiz looks the same whether it was launched
from Today, a chapter or a sign. Closing a session returns you to where you started.

### Signs and pictures

Search and Memorize open the full gallery; Learn opens the same gallery filtered to
its chapter. Each tile labels its statement count and opens directly into reading.
There is no picture-only action screen between the gallery and the statements.

The reader places a compact, fixed-height picture strip above the statement position
and **Quiz** action. Tapping a thumbnail selects a picture without
pushing another screen. Each picture retains its statement position while the reader
is open. Horizontal paging changes statements; vertical scrolling reads long content.
The leading edge remains reserved for Back. The statement card starts at the top,
with verdict, bookmark and explanation controls in the scrolling content.

Quiz opens as a full-screen session and closes back to the same picture and statement.
Why opens as a sheet, so supplementary explanations do not deepen the main navigation.
Back returns directly to the gallery, preserving its existing scroll view.

### Session types

- **Learn & quiz**: the next statements of a chapter in book order, in batches of 5.
  Study each one with its answer, explanation and key words, then answer exactly
  those 5, shuffled. Progress is saved per chapter.
- **Quiz** (VERO/FALSO), **word quiz** (Italian word → pick the meaning out of 4) and
  **numbers quiz** (rule → pick the value out of 4, with wrong options in the same
  unit). Word and numbers answers feed the same spaced-repetition cards as the flashcards.
- **Flashcards** for words and facts, **mixed review**, **read-through**, **Listen**.
- **Mock exam**: see below.

### Gestures

| Where | Swipe right | Swipe left |
|---|---|---|
| VERO/FALSO card | VERO | FALSO, then Next once answered |
| Learn step, choice quizzes | — | Next |
| Flashcards | Got it | Again |
| Listen | previous | next |
| Chapter page | previous chapter | next chapter |
| Mock exam | previous question | next question |
| Study pager | previous item | next item |

**Study pager.** Questions, vocabulary, facts and signs use continuous horizontal
paging. Swiping left advances and swiping right returns to the previous item; the
leading screen edge belongs to navigation Back. Vertical scrolling reads content
that is taller than the screen and never advances to another item. The vertical
scrub rail is removed; the header retains the current position and total count.
Every list opens on the row that was tapped; *Read with answers* uses the same pager
for a whole chapter and resumes where you stopped. Supplementary examples,
questions and explanations open in a sheet. Lazy pages have fixed viewport widths,
so paging and saved positions share the same coordinates. Only the visible page is
exposed to accessibility. Quizzes keep their answer gestures separately.

The answer buttons sit on the same sides as the swipes (FALSO left, VERO right). On
question text, a tap opens the word card, and touch-and-hold then drag translates a
phrase, so a plain swipe always means "answer".

### Library filters

Question lists and chapter vocabulary have local search in Italian and the selected
helper language. Opening a match keeps horizontal paging within the filtered results.
The full word library retains its Importance / A–Z order. Signs & pictures can be
narrowed by chapter and searched through their associated question text; opening an
image preserves the selected chapter scope. Empty searches show a standard no-results
state, and clearing the query restores the library.

### Facts & numbers

The searchable library groups facts by topic, with a topic filter on the same page.
Search results and the fact library each use one toolbar translation control for all sections.
Selecting a row opens the shared horizontal reader in the filtered result order.
Related questions open directly in a sheet; Quiz and Memorize stay beside the fact.
Speed limits use comparable bars with Standard, Rain and New drivers conditions.
Licence renewal intervals use age-group bars. Bars open their source fact; only
complete, explicitly related groups with the same unit become charts. Scoped
lists with incomplete groups keep ordinary rows, and search always finds every
fact individually.

### Mock exam

It copies the ministry's exam program used at the Motorizzazione: question-group tabs
("Domande da 1 a 10"), numbered boxes, a strip with every question number, "Domanda
numero", square **V**/**F** buttons, "Tempo a disposizione", a question list (riepilogo),
round arrows, and the picture on the left with the statement on the right. It runs in
landscape: the app is otherwise portrait-only and rotates for the simulation. It is
**Italian only**, with no translations, word lookup or explanations.

Ending the test is always an explicit action:

- **Consegna** (hand in, any time) or the timer reaching zero corrects the test. As in
  the official test, an unanswered statement counts as an error, and passing means at
  most 3 errors. A full-screen verdict follows (green *Complimenti!* with *Esito: IDONEO*,
  or red *Prova non superata* with *Esito: NON IDONEO*, plus score and time), then the list of errors with
  the answer given and the correct one. Every error, unanswered ones included, becomes
  a mistake to study with explanations.
- **Interrompi** (abort, for interruptions) leaves without a score or a history entry.
  Answers already given are still recorded, so wrong ones become mistakes. The current
rules are 30 statements, 20 minutes, at most 3 errors. The older official program
shows 40 / 30 minutes; the layout is the same.

## Bridging the language

- **Tap any Italian word** (in questions, explanations, examples, chapter titles) → a word
  card: its base form ("vietata" → *vietato*), meaning in the helper language, level, a
  warning note for trap words, the share of statements with that word that are VERO,
  real exam statements using it, *Learn this* / *I know it*, pronunciation, and online
  lookups.
- **Drag across words** → Apple's system translator for the phrase.
- **Translation display** uses small `translate` buttons beside the affected card or
  section, sharing the persistent `Preferences.showsTranslations` state. There is
  no navigation-bar translation button. Hidden translations retain their measured
  space and leave accessibility and hit testing. Word-quiz answer choices remain
  visible; explicit word lookups always show their meaning. Mock exams hide help.
- **Pronunciation** uses a borderless speaker icon with a localized Listen/Stop
  accessibility label and a 44-point touch target.
- **Listen** reads Italian, then the helper language, then the answer (and optionally
  the explanation) with the screen locked, and has lock-screen controls.

## Memory model

- Automatic word, fact, question and Learn & quiz sessions explore unseen material
  first, then fill remaining places with reviews whose due date has arrived. Future
  reviews never fill a session; a session can be shorter or empty. Chapter and
  topic filters still apply. Mixed quizzes consider the full question bank.
- Explicit Review is due-only and respects the selected session length. Question
  review dates are derived from persisted last-answer time and consecutive successes:
  a mistake returns after ten minutes; successes return after 1, 3, 7, 16, 35 and
  90 days. Cards retain their persisted Leitner schedule. Manual mistake and saved
  question lists remain available on demand; mock exams retain their exam sampling.

- Leitner boxes with intervals of 10 min, 1, 3, 7, 16, 35 and 90 days. Two buttons only
  (*Again* / *Got it*), so you can review one-handed. A new card marked *Got it*
  straight away skips ahead, because the learner already knew it.
- A question is a **mistake** until it's answered correctly twice in a row.
- The **key word ladder** ranks the 3,278 base-form words by how many questions and
  chapters they appear in, with a weighting toward words above A2. Knowing the top 500
  covers 77% of the content words in the questions. The card shows the next milestone.

## Data

`Scripts/prepare_content.py` builds local SQLite inputs from data’s versioned text sources; `Scripts/build_content_db.py` then builds `Rotonda/Resources/patente.db` (read-only) from:

- `data/app/quiz.db`: the generated A/B app bank: 7,020 questions, 25 chapters, image groups, IT/EN/ZH
  texts and explanations, 162 study facts
- `data/app/banks.db`: the generated bank for every licence (AM, A/B, Superiori, CQC and the
  revisione exams) with reviewed EN/ZH translations, imported from the data
  repository by `Scripts/import_bank_data.py`, which also converts figures the A/B bundle
  lacks into `Rotonda/Resources/StudyImages`
- `data/app/word_study_metadata.json`: surface form → base form, CEFR estimate, English gloss
- `data/app/curated_study.json`: exam-language words, road terms and look-alike concept
  pairs, in EN and ZH
- `data/app/fact_topics.json`: Chinese (and missing English) fact headlines
- `data/app/word_meanings_zh.json`: Simplified Chinese vocabulary meanings, translated
  in the context of linked driving exam questions; supplements existing curated meanings

It adds base-form words with an importance rank, a word↔question index, per-chapter key
words, facts linked to their chapter, picture groups for the sign gallery, and
accent-folded search columns.

### Licences

The learner chooses a licence in the guide or in Progress and settings
(`Preferences.licence`): Patente AM, A e B, C, D, CQC merci or CQC persone, or the
revisione exam for AM, A/B, C/D, CQC merci or CQC persone. Everything the app shows
follows it: chapters, questions, word ranking, key words, facts, signs and the mock exam.

Ministry question numbers are global: the same number has the same Italian and the same
answer in every bank (the importer checks this). So `questions` holds each statement once
(19,048), and `licence_questions` places it in a licence's chapter and group.

Each licence has its own progress: answers, memory cards, saved words and questions, mock
exams, activity and streak live in a separate SwiftData store per licence
(`Progress.store` for A/B, the store from before licences existed, and
`Progress-<licence>.store` for the others). Switching licence opens its store; nothing
carries over. The helper language is not part of progress: switching it (it is also the
UI language) keeps every store as it is.

### Helper languages

Helper languages are English, Simplified Chinese and Latin American Spanish (`es-419`),
each a `HelperLanguage` case whose raw value is the BCP 47 code used in the database.
Translations are rows, not columns: `question_texts`, `chapter_texts`, `word_texts` and
`fact_texts` hold one row per item and language, and `languages` lists each language with
what it has bundled. Adding a language means a new case, its rows and its UI strings; the
schema does not change. A language without a text shows nothing in its place, never
another helper language.

Spanish comes from data for every official statement and chapter (the 86 legacy
A/B statements outside the current PDF have none). It has no bundled explanations, facts or
word meanings yet: explanations show in Italian only, and word meanings are translated on
device from the English meaning, like any meaning the bundle lacks.
`data/app/translation_fixes.json` holds reviewed corrections to upstream translations until
data includes them; the importer refuses a fix whose source text has changed.

| Table | Per licence |
|---|---|
| `licences` | bank, question/word/fact counts, exam questions, minutes and errors allowed, word coverage |
| `chapters`, `groups`, `licence_questions` | chapters, picture groups and membership; `chapters.exam_quota` is each chapter's share of the mock exam |
| `licence_words`, `chapter_words` | word rank and counts; key words per chapter |
| `licence_facts` | the facts whose questions the licence tests, in its chapter |

A/B keeps the ids of `data/app/quiz.db`, so existing progress is untouched. Other licences use
`ordinal × 100 + chapter` and `ordinal × 100000 + official group` ids. Superiori splits into
C and D by the exam codes at the end of its chapter titles ((3) C, (6) D), merging chapters
that repeat a topic per code. CQC splits into goods (tipologie 1–13) and passengers (1–10,
14–16); its mock exam takes 40 common and 30 specialist questions. Its chapters only have
numbers in the source, so their titles summarise the questions and are not official.

Exam formats: A/B 30 questions, 20 minutes, 3 errors; AM 30, 25, 3; C and D 40, 40, 4;
CQC 70, 90, 7; revisione AM 20, 20, 2; revisione A/B and C/D 30, 30, 3; revisione CQC 40,
40, 4. Vocabulary comes from the A/B bank, whose every word has a reviewed Chinese meaning;
other licences link their statements to those words, and words only they use stay plain
text. Explanations exist for statements shared with A/B. All 3,034 vocabulary entries have bundled Chinese meanings.
The builder rejects missing Chinese meanings, and `Scripts/test_content_translations.py`
checks coverage, stable word identifiers and reproducible database contents.

The learner's data lives in `Application Support/Rotonda/progress.db`. Rotonda has its own
bundle identifier (`me.chichou.rotonda`), so it installs next to Patente30 and starts with
fresh progress.

## Widgets

Widgets show study state, not shortcuts. The app writes `widget-snapshot.json` to the
App Group `group.me.chichou.rotonda` when it becomes active, goes to the background or
ends a session; widgets never open the study databases.

- **Review**: words, facts and questions due now. The snapshot carries due times for
  the next three days, so counts grow on schedule without the app running.
- **Exam readiness**: bank mastery, pass chance (at most the licence's allowed errors in
  its exam length, at the accuracy of the last 100 answers, once there are 30), the last five mock exams by error count,
  the streak, and the chapter with most open mistakes (or the next one to learn).
- **Vero o falso**: answer open mistakes, due statements and new ones from the current
  chapter in place. Answers wait in the App Group defaults and are recorded through
  `ProgressStore.record` when the app next becomes active.
- **Word**: due words, then the next ladder words, one per hour. Meanings follow the
  helper-language rule: no fallback to another language.

Taps open what the widget shows through `rotonda://open/...` links (`WidgetLink`):
Review, Exam readiness and the focus chapter start their session; a Vero o falso statement
opens full screen, as a quiz starting with it and continuing through the widget deck, or
with its answer and explanation once answered in the widget; a word opens its details.

## Online extras

Everything above works in airplane mode. When the device is online, word cards and
search also offer WordReference (EN) or Google Translate (ZH), Italian Wiktionary,
picture search and web search, all opened in an in-app browser. Vocabulary meanings
work offline immediately, without downloading an Apple translation language pack.

## Known gaps

- CEFR levels and base forms come from public data and a few ending rules, so a few
  forms stay unmerged or are attached to the wrong base word.
