#!/usr/bin/env python3
"""Build the app's read-only content database (Rotonda/Resources/patente.db).

Inputs (not bundled):
  data/app/quiz.db                    A/B questions, chapters, groups, explanations, study facts
  data/app/banks.db                   every licence's official bank (Scripts/import_bank_data.py)
  data/app/word_study_metadata.json   surface form -> base form (lemma), CEFR estimate, English gloss
  data/app/curated_study.json         exam-language words, road terms, concept contrasts (EN + ZH)
  data/app/fact_topics.json           helper-language fact headlines and cleaned quiz values
  data/app/word_glossary.json         form -> {lemma, en, zh} or "skip", for forms the lexicon lacks
  data/app/word_meanings_zh.json      missing lexicon meanings in Simplified Chinese
  data/app/word_examples_zh.json      Italian example sentence -> Simplified Chinese translation
  data/app/word_texts_es.json         word meanings, notes and example sentences in Latin American Spanish
  data/app/explanations_es.json       A/B explanations in Latin American Spanish, by question id
  data/app/facts_es.json              fact headlines and texts in Latin American Spanish, by fact id
  data/app/word_ids.json              lemma -> word id, kept across rebuilds (updated in place)

Questions are stored once, keyed by their official ministry number, which is the same in
every bank. Each licence (AM, A/B, Superiori, CQC and the revisione exams) has its own
chapters, groups and membership rows, word ranking, key words per chapter, facts and mock
exam rules, so the app filters everything by the licence the learner chose. Progress stays
per question, so answers carry over between licences that share questions.

The output adds what the app needs to teach vocabulary offline: base-form words ranked by
importance per licence, a word <-> question index, per-chapter key words, facts linked to
chapters, image groups for the sign gallery, and accent-folded search columns.
"""
import argparse
import json
import math
import re
import sqlite3
import tempfile
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL_WEIGHT = {"A1": 0.35, "A2": 0.6, "B1": 1.0, "B2": 1.1, "C1": 1.2, "C2": 1.2, None: 0.9}


def fold(text: str) -> str:
    text = unicodedata.normalize("NFD", text.lower().replace("’", "'"))
    return "".join(c for c in text if unicodedata.category(c) != "Mn")


def tokens(text: str) -> list[str]:
    # Must match ContentStore.tokens(_:) in the app: lowercase, split on anything that is not a letter.
    return [t for t in re.split(r"[^\w]|[\d_]", text.lower().replace("’", "'")) if t]


def base_candidates(form: str) -> list[str]:
    """Likely dictionary forms for an inflected Italian word, most specific first."""
    out = []
    for endings, bases in (
        (("ata", "ate", "ati", "ato"), ("are",)),
        (("uta", "ute", "uti", "uto"), ("ere",)),
        (("ita", "ite", "iti", "ito"), ("ire",)),
        (("ando",), ("are",)),
        (("endo",), ("ere", "ire")),
    ):
        for ending in endings:
            if form.endswith(ending) and len(form) > len(ending) + 2:
                stem = form[: -len(ending)]
                out += [stem + ending[:-1] + "o"] + [stem + b for b in bases]
    if len(form) > 3 and form[-1] in "aeio":
        stem = form[:-1]
        out += [stem + "o", stem + "e", stem + "a"]
        if form.endswith(("chi", "ghi", "che", "ghe")):
            out += [form[:-2] + "o", form[:-2] + "a"]
    # Present tense last, so nouns and adjectives win: indica → indicare, passano → passare.
    for endings, bases in ((("ano",), ("are",)), (("ono",), ("ere", "ire")), (("a",), ("are",)), (("e",), ("ere", "ire"))):
        for ending in endings:
            if form.endswith(ending) and len(form) > len(ending) + 3:
                out += [form[: -len(ending)] + b for b in bases]
    return [c for c in dict.fromkeys(out) if c != form]


def short_title(title: str) -> str:
    return re.split(r"\s*[;；]\s*", title)[0].strip()


# Licences the learner can choose, in display order. `id` is stored in the app's preferences
# and must not change. Chapter and group ids are `ordinal * 100 + bank chapter` and
# `ordinal * 100000 + official group number`; A/B is ordinal 0, so its ids stay those of
# data/app/quiz.db and existing progress keeps its chapters.
#
# Exam formats (questions, minutes, errors allowed): A/B DM 27/10/2021; AM circolare
# 7260/2017; C and D DM 2/12/2014 art. 1; CQC DM 30/7/2021 art. 14 (40 common + 30
# specialist); revisione DM 15/2/2016.
#
# Superiori chapter titles end with the exams they belong to: (1) C1, (2) C1 code 97,
# (3) C, (4) C from C1, (5) D1, (6) D, (7) D from D1. C and D take the chapters tagged 3 or
# 6 plus the untagged ones; the goods-delivery chapter is C only. CQC tipologie 1-10 are the
# common part, 11-13 goods and 14-16 passengers.
CQC_COMMON = range(1, 11)
LICENCES = [
    {"id": "ab", "bank": "ab", "exam": (30, 20, 3)},
    {"id": "am", "bank": "am", "exam": (30, 25, 3)},
    {"id": "c", "bank": "superiori", "exam": (40, 40, 4), "code": "3"},
    {"id": "d", "bank": "superiori", "exam": (40, 40, 4), "code": "6",
     "exclude": ("Responsabilità del conducente in merito a ricevimento",)},
    {"id": "cqc_merci", "bank": "cqc_nuovo", "exam": (70, 90, 7),
     "tipologie": [*CQC_COMMON, 11, 12, 13], "parts": {"common": 40, "special": 30}},
    {"id": "cqc_persone", "bank": "cqc_nuovo", "exam": (70, 90, 7),
     "tipologie": [*CQC_COMMON, 14, 15, 16], "parts": {"common": 40, "special": 30}},
    {"id": "revisione_ab", "bank": "revisione_ab", "exam": (30, 30, 3)},
    {"id": "revisione_am", "bank": "revisione_am", "exam": (20, 20, 2)},
    {"id": "revisione_superiori", "bank": "revisione_superiori", "exam": (30, 30, 3)},
    {"id": "revisione_cqc_merci", "bank": "revisione_cqc_merci", "exam": (40, 40, 4)},
    {"id": "revisione_cqc_persone", "bank": "revisione_cqc_persone", "exam": (40, 40, 4)},
]

# The CQC bank names its chapters only by number ("01##tipologia1 CQC - DL 30 LUGLIO 2021").
# These titles summarise each tipologia's questions; they are not official names.
# Order: Italian, English, Chinese, Spanish.
CQC_TITLES = {
    1: ("Fisica del veicolo, motore e consumi", "Vehicle physics, engine and fuel use", "车辆物理、发动机与油耗", "Física del vehículo, motor y consumo"),
    2: ("Impianti frenanti e sistemi di assistenza alla guida", "Brakes and driver assistance systems", "制动系统与驾驶辅助系统", "Frenos y sistemas de asistencia a la conducción"),
    3: ("Pneumatici e sistemi telematici", "Tyres and telematics", "轮胎与智能交通系统", "Neumáticos y sistemas telemáticos"),
    4: ("Incidenti, responsabilità e primo soccorso", "Accidents, liability and first aid", "事故、责任与急救", "Accidentes, responsabilidad y primeros auxilios"),
    5: ("Sicurezza stradale e sul lavoro, ergonomia", "Road and workplace safety, ergonomics", "道路与工作安全、人体工学", "Seguridad vial y laboral, ergonomía"),
    6: ("Tempi di guida e di riposo, cronotachigrafo", "Driving and rest times, tachograph", "驾驶与休息时间、行车记录仪", "Tiempos de conducción y descanso, tacógrafo"),
    7: ("Frontiere, immigrazione e criminalità", "Borders, immigration and crime", "边境、移民与犯罪", "Fronteras, inmigración y delincuencia"),
    8: ("Manutenzione del veicolo", "Vehicle maintenance", "车辆维护", "Mantenimiento del vehículo"),
    9: ("Salute, stress e stanchezza", "Health, stress and fatigue", "健康、压力与疲劳", "Salud, estrés y fatiga"),
    10: ("Alcol, droghe e alimentazione", "Alcohol, drugs and diet", "酒精、毒品与饮食", "Alcohol, drogas y alimentación"),
    11: ("Carico e fissaggio delle merci", "Loading and securing goods", "货物装载与固定", "Carga y sujeción de mercancías"),
    12: ("Norme e documenti per il trasporto di merci", "Goods transport rules and documents", "货运法规与单证", "Normas y documentos del transporte de mercancías"),
    13: ("Merci speciali e deperibili, carburanti alternativi", "Special and perishable goods, alternative fuels", "特殊与易腐货物、替代燃料", "Mercancías especiales y perecederas, combustibles alternativos"),
    14: ("Servizio ai passeggeri e accessibilità", "Passenger service and accessibility", "乘客服务与无障碍", "Servicio a los pasajeros y accesibilidad"),
    15: ("Autobus, classi e cinture di sicurezza", "Buses, vehicle classes and seat belts", "客车、车辆类别与安全带", "Autobuses, clases y cinturones de seguridad"),
    16: ("Norme sul trasporto di persone", "Passenger transport rules", "客运法规", "Normas del transporte de pasajeros"),
}
TIPOLOGIA = re.compile(r"^(\d+)##tipologia")
CODES = re.compile(r"\s*[(（]([\d ]+)[)）]\s*[.。]?\s*$")


def chapter_codes(title_it: str) -> set[str]:
    match = CODES.search(title_it)
    return set(match.group(1).split()) if match else set()


def without_codes(title: str) -> str:
    # Translated titles sometimes end like sentences ("Use of the tachograph.").
    return CODES.sub("", title).strip().rstrip(".。").strip()


SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE licences (
    id TEXT PRIMARY KEY, position INTEGER NOT NULL UNIQUE, bank TEXT NOT NULL,
    exam_kind TEXT NOT NULL CHECK (exam_kind IN ('conseguimento', 'revisione')),
    question_count INTEGER NOT NULL, chapter_count INTEGER NOT NULL,
    word_count INTEGER NOT NULL, fact_count INTEGER NOT NULL,
    exam_questions INTEGER NOT NULL, exam_seconds INTEGER NOT NULL, exam_max_errors INTEGER NOT NULL,
    coverage_100 REAL NOT NULL, coverage_250 REAL NOT NULL, coverage_500 REAL NOT NULL,
    coverage_1000 REAL NOT NULL, coverage_2000 REAL NOT NULL
);
CREATE TABLE languages (
    code TEXT PRIMARY KEY, position INTEGER NOT NULL UNIQUE,
    question_count INTEGER NOT NULL, explanation_count INTEGER NOT NULL,
    word_count INTEGER NOT NULL, fact_count INTEGER NOT NULL
);
CREATE TABLE chapters (
    id INTEGER PRIMARY KEY, licence TEXT NOT NULL REFERENCES licences(id), position INTEGER NOT NULL,
    title_it TEXT NOT NULL, short_it TEXT NOT NULL,
    question_count INTEGER NOT NULL, image_group_count INTEGER NOT NULL,
    exam_quota REAL NOT NULL,
    UNIQUE (licence, position)
);
CREATE TABLE chapter_texts (
    chapter_id INTEGER NOT NULL REFERENCES chapters(id), language TEXT NOT NULL REFERENCES languages(code),
    title TEXT NOT NULL, short TEXT NOT NULL,
    PRIMARY KEY (chapter_id, language)
);
CREATE TABLE groups (
    id INTEGER PRIMARY KEY, licence TEXT NOT NULL REFERENCES licences(id),
    chapter_id INTEGER NOT NULL REFERENCES chapters(id), image TEXT,
    question_count INTEGER NOT NULL, position INTEGER NOT NULL
);
CREATE TABLE questions (
    id INTEGER PRIMARY KEY,
    text_it TEXT NOT NULL, answer INTEGER NOT NULL, image TEXT,
    expl_it TEXT NOT NULL, fold_it TEXT NOT NULL
);
-- A statement's translation and explanation in one helper language. `fold` is the
-- accent-folded, lowercased text for search, stored only when it differs from the lowercased
-- text (accented languages); search matches either column.
CREATE TABLE question_texts (
    question_id INTEGER NOT NULL REFERENCES questions(id), language TEXT NOT NULL REFERENCES languages(code),
    text TEXT NOT NULL, explanation TEXT NOT NULL, fold TEXT NOT NULL,
    PRIMARY KEY (question_id, language)
);
CREATE TABLE licence_questions (
    licence TEXT NOT NULL REFERENCES licences(id), question_id INTEGER NOT NULL REFERENCES questions(id),
    chapter_id INTEGER NOT NULL REFERENCES chapters(id), group_id INTEGER NOT NULL REFERENCES groups(id),
    position INTEGER NOT NULL,
    PRIMARY KEY (licence, question_id)
);
CREATE TABLE words (
    id INTEGER PRIMARY KEY, lemma TEXT NOT NULL, kind TEXT NOT NULL,
    pos TEXT NOT NULL, level TEXT,
    example_it TEXT NOT NULL, fold TEXT NOT NULL
);
CREATE TABLE word_texts (
    word_id INTEGER NOT NULL REFERENCES words(id), language TEXT NOT NULL REFERENCES languages(code),
    gloss TEXT NOT NULL, note TEXT NOT NULL, example TEXT NOT NULL,
    PRIMARY KEY (word_id, language)
);
CREATE TABLE licence_words (
    licence TEXT NOT NULL REFERENCES licences(id), word_id INTEGER NOT NULL REFERENCES words(id),
    rank INTEGER NOT NULL, question_count INTEGER NOT NULL, true_count INTEGER NOT NULL,
    chapter_spread INTEGER NOT NULL,
    PRIMARY KEY (licence, word_id), UNIQUE (licence, rank)
);
CREATE TABLE word_forms (form TEXT NOT NULL, word_id INTEGER NOT NULL REFERENCES words(id), PRIMARY KEY (form, word_id));
CREATE TABLE word_questions (
    word_id INTEGER NOT NULL REFERENCES words(id), question_id INTEGER NOT NULL REFERENCES questions(id),
    PRIMARY KEY (word_id, question_id)
);
CREATE TABLE chapter_words (
    chapter_id INTEGER NOT NULL REFERENCES chapters(id), word_id INTEGER NOT NULL REFERENCES words(id),
    question_count INTEGER NOT NULL, score REAL NOT NULL,
    PRIMARY KEY (chapter_id, word_id)
);
CREATE TABLE facts (
    id TEXT PRIMARY KEY, deck TEXT NOT NULL, position INTEGER NOT NULL,
    topic_it TEXT NOT NULL, text_it TEXT NOT NULL,
    value TEXT NOT NULL, note TEXT NOT NULL
);
CREATE TABLE fact_texts (
    fact_id TEXT NOT NULL REFERENCES facts(id), language TEXT NOT NULL REFERENCES languages(code),
    topic TEXT NOT NULL, text TEXT NOT NULL,
    PRIMARY KEY (fact_id, language)
);
CREATE TABLE licence_facts (
    licence TEXT NOT NULL REFERENCES licences(id), fact_id TEXT NOT NULL REFERENCES facts(id),
    chapter_id INTEGER REFERENCES chapters(id),
    PRIMARY KEY (licence, fact_id)
);
CREATE TABLE fact_questions (
    fact_id TEXT NOT NULL REFERENCES facts(id), question_id INTEGER NOT NULL REFERENCES questions(id),
    PRIMARY KEY (fact_id, question_id)
);
CREATE INDEX idx_licence_questions_chapter ON licence_questions(chapter_id, position);
CREATE INDEX idx_licence_questions_group ON licence_questions(group_id);
CREATE INDEX idx_licence_questions_question ON licence_questions(question_id);
CREATE INDEX idx_chapters_licence ON chapters(licence, position);
CREATE INDEX idx_groups_chapter ON groups(chapter_id, position);
CREATE INDEX idx_groups_licence_image ON groups(licence, image);
CREATE INDEX idx_licence_words_rank ON licence_words(licence, rank);
CREATE INDEX idx_word_forms_word ON word_forms(word_id);
CREATE INDEX idx_word_questions_question ON word_questions(question_id);
CREATE INDEX idx_chapter_words_score ON chapter_words(chapter_id, score DESC);
CREATE INDEX idx_licence_facts_chapter ON licence_facts(chapter_id);
CREATE INDEX idx_fact_questions_question ON fact_questions(question_id);
CREATE INDEX idx_question_texts_language ON question_texts(language);
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiz", type=Path, default=ROOT / "data/app/quiz.db")
    parser.add_argument("--banks", type=Path, default=ROOT / "data/app/banks.db")
    parser.add_argument("--metadata", type=Path, default=ROOT / "data/app/word_study_metadata.json")
    parser.add_argument("--curated", type=Path, default=ROOT / "data/app/curated_study.json")
    parser.add_argument("--topics", type=Path, default=ROOT / "data/app/fact_topics.json")
    parser.add_argument("--glossary", type=Path, default=ROOT / "data/app/word_glossary.json")
    parser.add_argument("--meanings-zh", type=Path, default=ROOT / "data/app/word_meanings_zh.json")
    parser.add_argument("--examples-zh", type=Path, default=ROOT / "data/app/word_examples_zh.json")
    parser.add_argument("--texts-es", type=Path, default=ROOT / "data/app/word_texts_es.json")
    parser.add_argument("--explanations-es", type=Path, default=ROOT / "data/app/explanations_es.json")
    parser.add_argument("--facts-es", type=Path, default=ROOT / "data/app/facts_es.json")
    parser.add_argument("--word-ids", type=Path, default=ROOT / "data/app/word_ids.json")
    parser.add_argument("--output", type=Path, default=ROOT / "Rotonda/Resources/patente.db")
    args = parser.parse_args()

    # A rejected content update must leave the last usable bundle intact.
    destination = args.output
    with tempfile.TemporaryDirectory(prefix="rotonda-content-", dir=destination.parent) as folder:
        args.output = Path(folder) / "patente.db"
        build(args)
        args.output.replace(destination)


def bank_chapter_titles(banks: sqlite3.Connection, bank: str):
    """(Italian title, {language: title}) for a bank's chapters, in order."""
    titles = defaultdict(dict)
    for pos, lang, title in banks.execute("SELECT position, language, title FROM chapter_texts WHERE bank = ?", (bank,)):
        titles[pos][lang] = title
    return [(it, titles[pos]) for pos, it in banks.execute("SELECT position, title_it FROM chapters WHERE bank = ? ORDER BY position", (bank,))]


def load_licences(src: sqlite3.Connection, banks: sqlite3.Connection):
    """Each licence's chapters, groups and question membership, with app-wide ids."""
    licences = []
    for ordinal, spec in enumerate(LICENCES):
        bank = spec["bank"]
        kind = banks.execute("SELECT exam_kind FROM banks WHERE id = ?", (bank,)).fetchone()
        if kind is None:
            raise ValueError(f"Bank {bank} is missing from data/app/banks.db")
        exam_questions, minutes, max_errors = spec["exam"]
        lic = {"id": spec["id"], "bank": bank, "kind": kind[0], "position": ordinal + 1,
               "exam": (exam_questions, minutes * 60, max_errors),
               "chapters": [], "groups": {}, "members": [], "part": {}}
        if bank == "ab":
            # The A/B app bundle keeps its own chapter order, groups and the 86 statements that
            # the current PDF no longer prints but earlier editions did.
            # Spanish (and any later language) comes from the official A/B bank's same chapter.
            official = {it.replace("’", "'"): titles for it, titles in bank_chapter_titles(banks, "ab")}
            lic["chapters"] = [(cid, pos, it, {**official.get(it.replace("’", "'"), {}), "en": en, "zh-Hans": zh}) for cid, pos, it, en, zh in
                               src.execute("SELECT id, position, title_it, title_en, title_zh FROM chapters ORDER BY position")]
            lic["groups"] = {gid: (chapter, image) for gid, chapter, image in
                             src.execute("SELECT id, chapter_id, image FROM question_groups")}
            lic["members"] = src.execute("""
                SELECT q.id, g.chapter_id, q.group_id FROM questions q JOIN question_groups g ON g.id = q.group_id
                ORDER BY g.chapter_id, q.group_id, q.id
            """).fetchall()
        else:
            # Bank chapter -> licence chapter id. Superiori and revisione banks repeat a topic once
            # per exam combination ("(1 3)", "(5 6)"); a licence shows each topic once.
            chapter_id, by_title = {}, {}
            for (pos, it), titles in zip(banks.execute("SELECT position, title_it FROM chapters WHERE bank = ? ORDER BY position", (bank,)).fetchall(),
                                         [t for _, t in bank_chapter_titles(banks, bank)]):
                if "code" in spec:
                    codes = chapter_codes(it)
                    if codes and spec["code"] not in codes:
                        continue
                if any(it.startswith(prefix) for prefix in spec.get("exclude", ())):
                    continue
                tipologia = TIPOLOGIA.match(it)
                if tipologia:
                    number = int(tipologia.group(1))
                    if "tipologie" in spec and number not in spec["tipologie"]:
                        continue
                    it, titles = CQC_TITLES[number][0], dict(zip(("en", "zh-Hans", "es-419"), CQC_TITLES[number][1:]))
                    if "parts" in spec:
                        lic["part"][ordinal * 100 + pos] = "common" if number in CQC_COMMON else "special"
                it, titles = without_codes(it), {lang: without_codes(t) for lang, t in titles.items()}
                if it in by_title:
                    chapter_id[pos] = by_title[it]
                    continue
                cid = chapter_id[pos] = by_title[it] = ordinal * 100 + pos
                lic["chapters"].append((cid, len(lic["chapters"]) + 1, it, titles))
            # A group shows the picture of its first illustrated statement (SQLite takes the bare
            # column from the MIN row).
            first_image = {group: image for group, image, _ in banks.execute("""
                SELECT bq.group_id, q.image, MIN(q.id) FROM bank_questions bq JOIN questions q ON q.id = bq.question_id
                WHERE bq.bank = ? AND q.image IS NOT NULL GROUP BY bq.group_id
            """, (bank,))}
            for official, chapter in banks.execute("SELECT id, chapter FROM groups WHERE bank = ?", (bank,)):
                if chapter in chapter_id:
                    lic["groups"][ordinal * 100000 + official] = (chapter_id[chapter], first_image.get(official))
            rows = banks.execute("""
                SELECT bq.question_id, g.chapter, bq.group_id FROM bank_questions bq
                JOIN groups g ON g.bank = bq.bank AND g.id = bq.group_id
                WHERE bq.bank = ? ORDER BY g.chapter, bq.group_id, bq.question_id
            """, (bank,)).fetchall()
            members = [(qid, chapter_id[chapter], ordinal * 100000 + group) for qid, chapter, group in rows if chapter in chapter_id]
            order = {cid: pos for cid, pos, *_ in lic["chapters"]}
            lic["members"] = sorted(members, key=lambda m: (order[m[1]], m[2], m[0]))
        lic["chapter_of"] = {qid: chapter for qid, chapter, _ in lic["members"]}

        # How many mock-exam questions each chapter supplies: in proportion to its share of the
        # bank, or of its part of the exam (CQC: 40 common, 30 specialist).
        counts = Counter(lic["chapter_of"].values())
        parts = spec.get("parts") or {"all": exam_questions}
        part_of = lambda cid: lic["part"].get(cid, "all") if "parts" in spec else "all"
        part_total = Counter()
        for cid, count in counts.items():
            part_total[part_of(cid)] += count
        lic["quota"] = {cid: parts[part_of(cid)] * count / part_total[part_of(cid)] for cid, count in counts.items()}
        licences.append(lic)
    return licences


def build(args: argparse.Namespace) -> None:
    src = sqlite3.connect(f"file:{args.quiz}?mode=ro", uri=True)
    banks = sqlite3.connect(f"file:{args.banks}?mode=ro", uri=True)
    metadata = json.loads(args.metadata.read_text())
    curated = json.loads(args.curated.read_text())
    meanings_zh = json.loads(args.meanings_zh.read_text())["meanings"]
    examples_zh = json.loads(args.examples_zh.read_text())["examples"]
    texts_es = json.loads(args.texts_es.read_text()) if args.texts_es.exists() else {}
    meanings_es, notes_es, examples_es = (texts_es.get(k, {}) for k in ("meanings", "notes", "examples"))
    explanations_es = (json.loads(args.explanations_es.read_text())["explanations"]
                       if args.explanations_es.exists() else {})
    facts_es = json.loads(args.facts_es.read_text())["facts"] if args.facts_es.exists() else {}
    topics = json.loads(args.topics.read_text())["topics"]
    entries, lexicon = metadata["entries"], metadata["lexicon"]
    glossary = {k: v for k, v in json.loads(args.glossary.read_text()).items() if not k.startswith("_")}

    out = sqlite3.connect(args.output)
    out.executescript(SCHEMA)

    # Questions, once each ------------------------------------------------------------
    # The A/B bundle's rows win: they carry explanations and reviewed translations. Every
    # other licence reuses them for the statements it shares with A/B.
    # Translations are rows per language: data/app/banks.db declares the languages (en, zh-Hans,
    # es-419…), and the A/B bundle's English and Chinese text and explanations take precedence.
    languages = [code for (code,) in banks.execute("SELECT code FROM languages ORDER BY position")]
    out.executemany("INSERT INTO languages VALUES (?,?,0,0,0,0)", [(code, i) for i, code in enumerate(languages, start=1)])
    official_texts = defaultdict(dict)
    for qid, lang, text in banks.execute("SELECT question_id, language, text FROM question_texts"):
        official_texts[qid][lang] = text
    corrected_texts = defaultdict(set)
    for qid, lang in banks.execute("SELECT question_id, language FROM question_texts WHERE review_status='corrected'"):
        corrected_texts[qid].add(lang)
    questions = {}  # id -> (italian, answer, image, italian explanation, {language: (text, explanation)})
    for qid, it, en, zh, answer, image, x_it, x_en, x_zh in src.execute("""
        SELECT id, text_it, text_en, text_zh, answer, image, explanation_it, explanation_en, explanation_zh
        FROM questions ORDER BY id"""):
        texts = {lang: (text, "") for lang, text in official_texts.get(qid, {}).items()}
        texts.update({"en": (en, x_en), "zh-Hans": (zh, x_zh)})
        if "es-419" in texts:
            texts["es-419"] = (texts["es-419"][0], explanations_es.get(str(qid), "").strip())
        for language in corrected_texts[qid]:
            texts[language] = (official_texts[qid][language], texts[language][1])
        questions[qid] = (it, answer, image, x_it, texts)
    for qid, it, answer, image in banks.execute("SELECT id, text_it, answer, image FROM questions ORDER BY id"):
        if qid in questions:
            if questions[qid][1] != answer:
                raise ValueError(f"Question {qid} has a different answer in data/app/banks.db")
            continue
        questions[qid] = (it, answer, image, "", {lang: (text, "") for lang, text in official_texts[qid].items()})
    # Staged packs may be incomplete while localization runs. Publish complete sets.
    extra_explanations = defaultdict(dict)
    for qid, language, value in banks.execute("SELECT question_id, language, text FROM question_explanations"):
        extra_explanations[qid][language] = value
    for qid, values in extra_explanations.items():
        it, answer, image, x_it, texts = questions[qid]
        if x_it:  # Preserve the established A/B explanations and application overlays.
            continue
        missing = {'it', *languages} - values.keys()
        if missing:
            continue  # Keep intermediate text in data; publish after all languages exist.
        questions[qid] = (it, answer, image, values['it'],
                          {lang: (text, values[lang]) for lang, (text, _) in texts.items()})
    out.executemany("INSERT INTO questions VALUES (?,?,?,?,?,?)",
                    [(qid, it, answer, image, x_it, fold(it)) for qid, (it, answer, image, x_it, _) in sorted(questions.items())])
    out.executemany("INSERT INTO question_texts VALUES (?,?,?,?,?)", [
        (qid, lang, text, explanation, "" if fold(text) == text.lower() else fold(text))
        for qid, (*_, texts) in sorted(questions.items()) for lang, (text, explanation) in sorted(texts.items()) if text.strip()])
    text_of = {qid: q[0] for qid, q in questions.items()}
    answer_of = {qid: q[1] for qid, q in questions.items()}

    # Licences: chapters, groups, membership ----------------------------------------------
    licences = load_licences(src, banks)
    for lic in licences:
        position = Counter()
        for qid, chapter, group in lic["members"]:
            position[chapter] += 1
            out.execute("INSERT INTO licence_questions VALUES (?,?,?,?,?)", (lic["id"], qid, chapter, group, position[chapter]))
        group_counts = Counter(group for _, _, group in lic["members"])
        group_position = Counter()
        image_groups = defaultdict(set)
        for gid in sorted(group_counts, key=lambda g: (lic["groups"][g][0], g)):
            chapter, image = lic["groups"][gid]
            group_position[chapter] += 1
            if image:
                image_groups[chapter].add(image)
            out.execute("INSERT INTO groups VALUES (?,?,?,?,?,?)",
                        (gid, lic["id"], chapter, image, group_counts[gid], group_position[chapter]))
        for cid, pos, it, titles in lic["chapters"]:
            out.execute("INSERT INTO chapters VALUES (?,?,?,?,?,?,?,?)",
                        (cid, lic["id"], pos, it, short_title(it), position[cid], len(image_groups[cid]),
                         round(lic["quota"].get(cid, 0), 4)))
            out.executemany("INSERT INTO chapter_texts VALUES (?,?,?,?)",
                            [(cid, lang, title, short_title(title)) for lang, title in sorted(titles.items()) if title.strip()])

    # Words ----------------------------------------------------------------------------
    # Vocabulary comes from the A/B bank, whose every word has a reviewed Chinese meaning.
    # Other licences link their statements to those words; forms only they use stay plain text.
    ab_questions = {qid for qid, _, _ in licences[0]["members"]}
    words = {}  # key -> record
    form_to_keys = defaultdict(set)

    def word(key, lemma, **fields):
        if key not in words:
            words[key] = {"lemma": lemma, "kind": "general", "pos": "", "level": None, "gloss_en": "",
                          "gloss_zh": "", "note_en": "", "note_zh": "", "example_it": "", "example_en": "",
                          "questions": set(), "forms": set()}
        words[key].update(fields)
        return words[key]

    unresolved = []
    for form, meta in entries.items():
        if meta["isStopWord"] or glossary.get(form) == "skip":
            continue
        sources = [s for s in meta.get("sourceWords") or [] if s in lexicon]
        if sources:
            for lemma in sources:
                lex = lexicon[lemma]
                word(lemma, lemma, pos=lex["partOfSpeech"], level=lex["level"],
                     gloss_en=lex["english"].replace(";", " / "),
                     example_it=lex["exampleItalian"], example_en=lex["exampleEnglish"])
                form_to_keys[form].add(lemma)
        elif len(form) > 1:
            unresolved.append((form, meta))

    # Unclassified inflections (veicoli, vietata…) fold into a known base form when a
    # simple Italian ending rule finds one; otherwise they stay their own word. A form whose
    # likeliest base is a stop word (posti → posto, sola → solo) is a stop word too.
    stop_words = {form for form, meta in entries.items() if meta["isStopWord"]}

    def plausible(form, base):
        # Participles and gerunds come from the verb-ending rules. Otherwise plurals swap the
        # last vowel for -i (or -a for -e); switching gender is for -o adjectives only. That
        # keeps verbs off look-alike nouns: indica is not indice, passa is not passo.
        pos = lexicon[base]["partOfSpeech"] if base in lexicon else ""
        if pos == "verb":
            return True
        if form[-1] == "i" or (form[-1], base[-1]) == ("e", "a"):
            return True
        return pos == "adjective" and base[-1] == "o"

    # Driving words the lexicon lacks (motocicli, anabbaglianti…) take their meaning and base
    # form from the curated glossary: plurals and verb forms fold into one word.
    for form, meta in unresolved:
        entry = glossary.get(form)
        if not entry:
            continue
        lemma = entry["lemma"]
        if lemma in stop_words:
            continue
        key = lemma if lemma in words else "form:" + lemma
        gloss = glossary.get(lemma) if isinstance(glossary.get(lemma), dict) else entry
        w = word(key, lemma)
        w["level"] = w["level"] or meta.get("level")
        w["gloss_en"] = w["gloss_en"] or gloss["en"]
        w["gloss_zh"] = w["gloss_zh"] or gloss["zh"]
        form_to_keys[form].add(key)
    unresolved = [(form, meta) for form, meta in unresolved if form not in glossary]

    for form, meta in unresolved:
        base, stop = None, False
        for candidate in base_candidates(form):
            stop = candidate in stop_words
            if stop or (candidate in words and plausible(form, candidate)):
                base = None if stop else candidate
                break
        if stop:
            continue
        key = base or "form:" + form
        if not base:
            word(key, form, level=meta.get("level"))
        form_to_keys[form].add(key)

    phrases = {}
    for kind, items in (("exam", curated["examLanguage"]), ("road", curated["roadWords"])):
        for item in items:
            text = item["it"]
            # non, deve, può, sempre… are everywhere in the bank because they are everywhere in
            # Italian; a learner gains nothing from a card for them.
            if all(t in stop_words for t in tokens(text)):
                continue
            key = text if text in words else ("form:" + text if "form:" + text in words else text)
            existing = words.get(key, {})
            word(key, text, kind=kind, gloss_en=item["en"], gloss_zh=item["zh"],
                 note_en=item["note_en"], note_zh=item["note_zh"],
                 example_it=existing.get("example_it") or item["example"].split(" = ")[0],
                 example_en=existing.get("example_en") or (item["example"].split(" = ")[1] if " = " in item["example"] else ""))
            if len(tokens(text)) > 1:
                phrases[key] = " " + " ".join(tokens(text)) + " "
            else:
                form_to_keys[text].add(key)

    # Forms that only other licences use join an A/B word by the same ending rules; they never
    # create a word of their own, since it would have no reviewed meaning.
    known_forms = set(entries) | set(form_to_keys)
    for qid in sorted(questions.keys() - ab_questions):
        for t in tokens(text_of[qid]):
            if t in known_forms or len(t) < 3:
                continue
            known_forms.add(t)
            if t in words:
                form_to_keys[t].add(t)
                continue
            for candidate in base_candidates(t):
                if candidate in stop_words:
                    break
                if candidate in words and plausible(t, candidate):
                    form_to_keys[t].add(candidate)
                    break

    for qid, text in text_of.items():
        toks = tokens(text)
        for t in set(toks):
            for key in form_to_keys.get(t, ()):
                words[key]["questions"].add(qid)
                words[key]["forms"].add(t)
        joined = " " + " ".join(toks) + " "
        for key, phrase in phrases.items():
            if phrase in joined:
                words[key]["questions"].add(qid)
                words[key]["forms"].add(phrase.strip())

    # A word earns its card from the A/B bank; other licences reuse the same cards.
    words = {k: w for k, w in words.items() if w["questions"] & ab_questions}
    # Preserve curated meanings; fill lexicon gaps from the reviewed offline overlay.
    for w in words.values():
        if not w["gloss_zh"].strip():
            w["gloss_zh"] = meanings_zh.get(w["lemma"], "").strip()
    missing_zh = [w["lemma"] for w in words.values() if not re.search(r"[㐀-鿿]", w["gloss_zh"])]
    if missing_zh:
        raise ValueError(f"Missing Chinese word meanings ({len(missing_zh)}): {', '.join(sorted(missing_zh))}")
    # Every example carries its Chinese translation, so a Chinese learner never sees English.
    missing_examples = sorted({w["example_it"] for w in words.values() if w["example_it"] and not examples_zh.get(w["example_it"], "").strip()})
    if missing_examples:
        raise ValueError(f"Missing Chinese example translations ({len(missing_examples)}): {' | '.join(missing_examples[:20])}")

    def importance(w, qids, chapter_of, chapter_count):
        spread = len({chapter_of[q] for q in qids})
        boost = 1.6 if w["kind"] == "exam" else (1.2 if w["kind"] == "road" else 1.0)
        return math.log1p(len(qids)) * (1 + spread / chapter_count) * LEVEL_WEIGHT.get(w["level"], 0.9) * boost

    # A word keeps its id across rebuilds (study progress is stored per id); new words get
    # fresh ids in A/B importance order.
    stable = json.loads(args.word_ids.read_text()) if args.word_ids.exists() else {}
    ab = licences[0]
    ab_order = sorted(words.items(), key=lambda kv: (-importance(kv[1], kv[1]["questions"] & ab_questions, ab["chapter_of"], len(ab["chapters"])), kv[1]["lemma"]))
    ids = {}
    for key, w in ab_order:
        if w["lemma"] not in stable:
            stable[w["lemma"]] = max(stable.values(), default=0) + 1
        wid = ids[key] = stable[w["lemma"]]
        out.execute("INSERT INTO words VALUES (?,?,?,?,?,?,?)",
                    (wid, w["lemma"], w["kind"], w["pos"], w["level"], w["example_it"], fold(w["lemma"])))
        # Bundled meanings in English, Chinese and Spanish; a language without one translates
        # on device. Alternative meanings are separated by slashes.
        out.executemany("INSERT INTO word_texts VALUES (?,?,?,?,?)", [
            (wid, "en", w["gloss_en"], w["note_en"], w["example_en"]),
            (wid, "zh-Hans", w["gloss_zh"], w["note_zh"], examples_zh.get(w["example_it"], "").strip() if w["example_it"] else ""),
            (wid, "es-419", meanings_es.get(w["lemma"], "").strip(), notes_es.get(w["lemma"], "").strip(),
             examples_es.get(w["example_it"], "").strip() if w["example_it"] else ""),
        ])
        for form in w["forms"] | {w["lemma"]}:
            out.execute("INSERT OR IGNORE INTO word_forms VALUES (?,?)", (form, wid))
        out.executemany("INSERT INTO word_questions VALUES (?,?)", [(wid, q) for q in sorted(w["questions"])])
    args.word_ids.write_text("{\n" + ",\n".join(f"  {json.dumps(k, ensure_ascii=False)}: {v}"
                             for k, v in sorted(stable.items(), key=lambda kv: kv[1])) + "\n}\n")

    # Also register every known form (even if it never appears) so taps on any form resolve.
    for form, keys in form_to_keys.items():
        for key in keys:
            if key in ids:
                out.execute("INSERT OR IGNORE INTO word_forms VALUES (?,?)", (form, ids[key]))

    # Per licence: word ranking, key words per chapter and vocabulary coverage.
    for lic in licences:
        chapter_of = lic["chapter_of"]
        members = set(chapter_of)
        chapter_count = len(lic["chapters"])
        ranked = []
        for key, w in words.items():
            qids = w["questions"] & members
            if qids:
                ranked.append((-importance(w, qids, chapter_of, chapter_count), w["lemma"], key, qids))
        ranked.sort()
        rank_of = {}
        for rank, (_, _, key, qids) in enumerate(ranked, start=1):
            rank_of[key] = rank
            spread = len({chapter_of[q] for q in qids})
            out.execute("INSERT INTO licence_words VALUES (?,?,?,?,?,?)",
                        (lic["id"], ids[key], rank, len(qids), sum(answer_of[q] for q in qids), spread))
            w = words[key]
            idf = math.log(1 + chapter_count / spread)
            for chapter, count in Counter(chapter_of[q] for q in qids).items():
                score = count * idf * LEVEL_WEIGHT.get(w["level"], 0.9) * (1.3 if w["kind"] != "general" else 1.0)
                out.execute("INSERT INTO chapter_words VALUES (?,?,?,?)", (chapter, ids[key], count, score))
        # Coverage of question text by the ranked list (content tokens only).
        token_words = Counter()
        for q in members:
            for t in tokens(text_of[q]):
                ranks = [rank_of[k] for k in form_to_keys.get(t, ()) if k in rank_of]
                if ranks:
                    token_words[min(ranks)] += 1
        total_tokens = max(sum(token_words.values()), 1)
        lic["coverage"] = [round(100 * sum(c for r, c in token_words.items() if r <= n) / total_tokens, 1)
                           for n in (100, 250, 500, 1000, 2000)]
        lic["word_count"] = len(ranked)

    # Facts ----------------------------------------------------------------------------
    fact_sources = defaultdict(list)
    for fid, qid in src.execute("SELECT fact_id, question_id FROM study_fact_sources ORDER BY question_id"):
        if qid in questions:
            fact_sources[fid].append(qid)
    def spanish_fact(fid):
        es = facts_es.get(fid)
        return [(fid, "es-419", es["topic"].strip(), es["text"].strip())] if es else []

    fact_ids = []
    fact_chapters = {}  # (licence, fact) -> statements that decide the fact's chapter
    for fid, deck, pos, topic, en, zh, it, value, note in src.execute(
            "SELECT id, deck, position, topic, fact_en, fact_zh, fact_it, value, COALESCE(note,'') FROM study_facts ORDER BY deck, position"):
        extra = topics.get(fid, {})
        out.execute("INSERT INTO facts VALUES (?,?,?,?,?,?,?)",
                    (fid, deck, pos, topic if "en" in extra else "", it, extra.get("value", value), note))
        out.executemany("INSERT INTO fact_texts VALUES (?,?,?,?)",
                        [(fid, "en", extra.get("en", topic), en), (fid, "zh-Hans", extra.get("zh", ""), zh)]
                        + spanish_fact(fid))
        fact_ids.append(fid)

    for pos, item in enumerate(curated["contrasts"]):
        fid = f"contrasts:{pos}"
        phrase_tokens = [tokens(part) for part in item["it"].split("/")]
        matched = {qid for qid in questions
                   if sum(1 for p in phrase_tokens if p and " " + " ".join(p) + " " in " " + " ".join(tokens(text_of[qid])) + " ") >= 2}
        # Up to 60 examples per licence in book order, so every licence gets its own; the
        # chapter follows all of them.
        chosen = set()
        for lic in licences:
            in_licence = [qid for qid, _, _ in lic["members"] if qid in matched]
            chosen |= set(in_licence[:60])
            fact_chapters[(lic["id"], fid)] = in_licence
        fact_sources[fid] = sorted(chosen)
        out.execute("INSERT INTO facts VALUES (?,?,?,?,?,?,?)", (fid, "contrasts", pos, item["it"], "", "", ""))
        out.executemany("INSERT INTO fact_texts VALUES (?,?,?,?)",
                        [(fid, "en", item["en"], item["text_en"]), (fid, "zh-Hans", item["zh"], item["text_zh"])]
                        + spanish_fact(fid))
        fact_ids.append(fid)

    for fid in fact_ids:
        out.executemany("INSERT INTO fact_questions VALUES (?,?)", [(fid, q) for q in fact_sources[fid]])
    for lic in licences:
        lic["fact_count"] = 0
        for fid in fact_ids:
            linked = fact_chapters.get((lic["id"], fid)) or [q for q in fact_sources[fid] if q in lic["chapter_of"]]
            # A/B keeps every curated fact; other licences get the facts their statements test.
            if not linked and lic["id"] != "ab":
                continue
            chapter = Counter(lic["chapter_of"][q] for q in linked).most_common(1)
            out.execute("INSERT INTO licence_facts VALUES (?,?,?)", (lic["id"], fid, chapter[0][0] if chapter else None))
            lic["fact_count"] += 1

    for lic in licences:
        out.execute("INSERT INTO licences VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (lic["id"], lic["position"], lic["bank"], lic["kind"], len(lic["members"]), len(lic["chapters"]),
                     lic["word_count"], lic["fact_count"], *lic["exam"], *lic["coverage"]))

    # What each helper language has bundled, so the app can tell what it translates on device.
    out.execute("""UPDATE languages SET
        question_count = (SELECT COUNT(*) FROM question_texts t WHERE t.language = code),
        explanation_count = (SELECT COUNT(*) FROM question_texts t WHERE t.language = code AND t.explanation <> ''),
        word_count = (SELECT COUNT(*) FROM word_texts t WHERE t.language = code AND t.gloss <> ''),
        fact_count = (SELECT COUNT(*) FROM fact_texts t WHERE t.language = code AND t.text <> '')""")
    legacy = dict(src.execute("SELECT key, value FROM content_manifest").fetchall())
    official = dict(banks.execute("SELECT key, value FROM meta").fetchall())
    meta = {
        "schema_version": "6",
        "content_version": f"{legacy.get('content_version', '')}+{official.get('content_version', '')}",
        "source_hash": legacy.get("content_hash", ""),
        "banks_hash": official.get("content_hash", ""),
        "question_count": str(len(questions)),
        "word_count": str(len(words)),
        "fact_count": str(len(fact_ids)),
    }
    out.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
    out.commit()
    problems = out.execute("PRAGMA foreign_key_check").fetchall()
    if problems:
        raise ValueError(f"Foreign key problems: {problems[:10]}")
    # Planner statistics: without them SQLite scans licence tables before the selective joins.
    out.execute("ANALYZE")
    # stat1 row counts are enough; stat4 samples rows by rowid, which varies between builds.
    if out.execute("SELECT 1 FROM sqlite_master WHERE name = 'sqlite_stat4'").fetchone():
        out.execute("DELETE FROM sqlite_stat4")
    out.commit()
    out.execute("VACUUM")
    out.close()
    summary = {lic["id"]: {"questions": len(lic["members"]), "words": lic["word_count"], "facts": lic["fact_count"],
                           "coverage_500": lic["coverage"][2]} for lic in licences}
    print(json.dumps({**meta, "licences": summary}, indent=2))


if __name__ == "__main__":
    main()
