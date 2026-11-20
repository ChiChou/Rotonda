-- Optional multi-bank application bundle. See docs/multibank-schema.md.
PRAGMA foreign_keys=ON;
PRAGMA user_version=5;
CREATE TABLE exam_banks (
 id TEXT PRIMARY KEY, title_it TEXT NOT NULL,
 exam_kind TEXT NOT NULL CHECK(exam_kind IN ('conseguimento','revisione')),
 language TEXT NOT NULL CHECK(language='it'), legacy INTEGER NOT NULL CHECK(legacy IN (0,1))
);
CREATE TABLE source_documents (
 bank_id TEXT PRIMARY KEY REFERENCES exam_banks(id), url TEXT NOT NULL,
 pdf_path TEXT NOT NULL, sha256 TEXT NOT NULL, retrieved_on TEXT NOT NULL,
 listing_url TEXT NOT NULL, listing_updated_on TEXT, page_count INTEGER NOT NULL
);
CREATE TABLE content_texts (id TEXT PRIMARY KEY, text_it TEXT NOT NULL);
CREATE TABLE translations (
 text_id TEXT NOT NULL REFERENCES content_texts(id),
 language TEXT NOT NULL CHECK(language IN ('en','zh-Hans','es-419')),
 text TEXT NOT NULL CHECK(length(trim(text))>0), origin TEXT NOT NULL,
 review_status TEXT NOT NULL CHECK(review_status IN ('existing','draft','reviewed')),
 PRIMARY KEY(text_id,language)
);
CREATE TABLE chapters (
 id TEXT PRIMARY KEY, bank_id TEXT NOT NULL REFERENCES exam_banks(id),
 position INTEGER NOT NULL CHECK(position>=1), title_it TEXT NOT NULL,
 text_id TEXT NOT NULL REFERENCES content_texts(id),
 UNIQUE(bank_id,position), UNIQUE(bank_id,id)
);
CREATE TABLE question_groups (
 id TEXT PRIMARY KEY, bank_id TEXT NOT NULL REFERENCES exam_banks(id),
 official_id INTEGER NOT NULL CHECK(official_id>0), chapter_id TEXT NOT NULL,
 source_page INTEGER NOT NULL CHECK(source_page>=1),
 UNIQUE(bank_id,official_id), UNIQUE(bank_id,id),
 CHECK(id=bank_id || ':group:' || official_id),
 FOREIGN KEY(bank_id,chapter_id) REFERENCES chapters(bank_id,id)
);
CREATE TABLE questions (
 id TEXT PRIMARY KEY, bank_id TEXT NOT NULL REFERENCES exam_banks(id),
 official_number INTEGER NOT NULL CHECK(official_number>0), group_id TEXT NOT NULL,
 text_it TEXT NOT NULL CHECK(length(trim(text_it))>0),
 text_id TEXT NOT NULL REFERENCES content_texts(id),
 answer INTEGER NOT NULL CHECK(answer IN (0,1)),
 source_page INTEGER NOT NULL CHECK(source_page>=1),
 UNIQUE(bank_id,official_number),
 CHECK(id=bank_id || ':' || official_number),
 FOREIGN KEY(bank_id,group_id) REFERENCES question_groups(bank_id,id)
);
CREATE TABLE question_explanations (
 question_id TEXT NOT NULL REFERENCES questions(id), language TEXT NOT NULL,
 text TEXT NOT NULL CHECK(length(trim(text))>0),
 PRIMARY KEY(question_id,language)
);
CREATE TABLE assets (
 id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL,
 media_type TEXT NOT NULL
);
CREATE TABLE question_assets (
 question_id TEXT NOT NULL REFERENCES questions(id), asset_id TEXT NOT NULL REFERENCES assets(id),
 source_page INTEGER NOT NULL CHECK(source_page>=1), x0 REAL NOT NULL, top REAL NOT NULL, x1 REAL NOT NULL, bottom REAL NOT NULL,
 PRIMARY KEY(question_id,asset_id,source_page,top),
 CHECK(x1>x0 AND bottom>top)
);
CREATE TABLE content_manifest (key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE VIEW localized_questions AS
 SELECT q.*, en.text AS text_en, zh.text AS text_zh, es.text AS text_es,
 en.review_status AS en_review_status, zh.review_status AS zh_review_status, es.review_status AS es_review_status
 FROM questions q
 LEFT JOIN translations en ON en.text_id=q.text_id AND en.language='en'
 LEFT JOIN translations zh ON zh.text_id=q.text_id AND zh.language='zh-Hans'
 LEFT JOIN translations es ON es.text_id=q.text_id AND es.language='es-419';
CREATE VIEW translation_coverage AS
 SELECT q.bank_id, count(*) AS question_count,
 count(en.text) AS english_count, count(zh.text) AS chinese_count, count(es.text) AS spanish_count
 FROM questions q
 LEFT JOIN translations en ON en.text_id=q.text_id AND en.language='en'
 LEFT JOIN translations zh ON zh.text_id=q.text_id AND zh.language='zh-Hans'
 LEFT JOIN translations es ON es.text_id=q.text_id AND es.language='es-419'
 GROUP BY q.bank_id;
