-- Optional query accelerators; correctness relies only on table constraints.
CREATE INDEX idx_questions_bank_group ON questions(bank_id,group_id);
CREATE INDEX idx_questions_text ON questions(text_id);
CREATE INDEX idx_translations_language ON translations(language,text_id);
