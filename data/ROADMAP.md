# data roadmap

Planning snapshot: 14 November 2026.

## Deferred official French and German quiz modes

Decision recorded 17 November 2026: introduce French and German source-language
quiz modes later, with helper translations and question explanations off. Do not
ship them in the current release or generate French/German-to-helper packs now.
This is separate from adding helper languages to Italian questions.

Before implementation, design source-language-aware question identity, official
edition and answer provenance, bank membership, and progress compatibility. Audit
the app's assumptions that primary question text is Italian and that each quiz has
helper-language rows and explanations. Keep this a separate schema and app-logic
change with its own migration and validation plan. The present cleanup retains
Italian source banks with English, Simplified Chinese, and Latin American Spanish.

## Current direction

Maintain the Italian source data and the existing English, Simplified Chinese,
and Latin American Spanish translations. Spanish has completed a separate
GPT-6.1 Terra review, with corrections and evidence under
`reviews/spanish-review/`. Model review and native-speaker beta testing are
separate checks.

**Additional languages are deferred.** We currently do not have native-speaking
reviewers or beta testers for the candidate languages below. This is a research
backlog, not a commitment to generate translations immediately.

## How to choose the next language

Consider these factors together:

- Size of the established community in Italy, including driving-age adults.
- Recent arrivals and likely future demand.
- Need to take an Italian driving exam: prioritize people whose existing
  licences cannot be converted, alongside first-time drivers.
- Preferred reading language, Italian proficiency, and coverage from languages
  already supported. Nationality alone does not identify language preference.
- Access to community organizations, driving schools, native reviewers, and beta
  testers who can validate the content.
- Availability of official translated material that could be reused.

Existing EU/EEA licence holders are a lower-priority audience for exam preparation.
The same distinction applies to eligible non-EU licence holders with a conversion
route. These communities still include first-time learners. Verify current
conversion agreements and their conditions before making a language decision.

### Excluded languages

French and German are excluded from the translation roadmap because candidates
can already take the Italian driving-theory exam in these languages. Focus new
translation work on languages without that official exam option.

## Provisional shortlist

The order is provisional and can change when reviewer availability or evidence
of demand improves. Population figures below are valid residence-permit holders
at **31 December 2024**, used as community proxies rather than speaker counts or
customer forecasts.

| Candidate | Community evidence | What to validate next |
| --- | --- | --- |
| Bengali, Bangladesh (`bn-BD`) | About 196,000 Bangladeshi permit holders; a young adult population and a concentrated community in metropolitan Rome | Find Bengali-speaking learners and a bilingual reviewer; validate demand through local community or driving-school partners |
| Arabic | About 665,000 permit holders across Egypt, Morocco, and Tunisia, including about 175,000 Egyptians | Separate exam demand by licence-conversion eligibility; validate accessible written Arabic and terminology across communities |
| Urdu (`ur`) | About 160,000 Pakistani permit holders | Confirm Urdu reading preference, terminology, and reviewer availability rather than assuming every Pakistani learner prefers Urdu |

The latest ISTAT report also records substantial new permit issuance in 2025:
Bangladesh 39,807, Egypt 32,235, and Pakistan 23,998. This supplements the
established-community figures; it does not measure driving-exam demand directly.

## Further candidates to investigate

These candidates are **unranked**. Each needs community, language-preference,
conversion-eligibility, and reviewer research before promotion to the shortlist.

| Candidate | Audience to investigate | Key question |
| --- | --- | --- |
| Punjabi | Punjabi-speaking Indian and Pakistani communities | Which script and written variety do prospective learners use? Treat Gurmukhi and Shahmukhi needs separately |
| Hindi | Hindi-speaking learners from India | How much additional reach would Hindi provide beyond English and Punjabi? Avoid treating India as one language market |
| Wolof | Wolof-speaking Senegalese learners | Would learners use written Wolof, and what form of bilingual explanation would help? |
| Ukrainian | Ukrainian-speaking learners | How much demand comes from first-time drivers and people outside current conversion conditions? |
| Russian | Russian-speaking learners across several communities | Validate individual language preference; do not use Russian as an automatic substitute for Ukrainian |
| Portuguese, Brazil (`pt-BR`) | Brazilian learners | Is there sufficient unmet demand among first-time drivers and people unable to convert? |
| Filipino/Tagalog | Filipino learners | How much benefit would it add beyond English, and which written form do testers prefer? |
| Tamil | Tamil-speaking Sri Lankan and Indian learners | Which terminology and regional variant fit the actual audience? |
| Sinhala | Sinhala-speaking Sri Lankan learners | Validate demand separately from Tamil and account for conversion eligibility |
| Persian/Farsi | Persian-speaking Iranian learners | Confirm audience size, technical vocabulary, and access to bilingual reviewers |
| Dari | Dari-speaking Afghan learners | Validate separately from Iranian Persian rather than assuming one translation serves both |
| Pashto | Pashto-speaking Afghan and Pakistani learners | Confirm reading preference, script support, and reviewer access |
| Turkish | Turkish-speaking learners | Validate first-time learner demand, conversion conditions, and gaps in existing study resources |

Languages associated with EU countries can still serve non-EU communities;
prioritization should follow the learners and their licensing situation.

### Deprioritized: Albanian

The project owner's observation is that many Albanian learners already speak
Italian well. Treat this as a planning assumption rather than a measured
community-wide fluency estimate. Albanian is therefore a lower priority: community
size alone does not establish a need for translated study material. Reconsider
only if learner or driving-school feedback identifies an underserved group that
would benefit from Albanian support.

## Gates before starting another language

- [ ] Identify an available native-speaking reviewer and a small beta group.
- [ ] Ensure the reviewer can compare against Italian, or arrange a bilingual
      review partner with the necessary driving terminology.
- [ ] Validate community demand and preferred language/script with real learners.
- [ ] Check current licence-conversion rules and existing official translations.
- [ ] Agree on terminology and prepare a small representative pilot covering
      false statements, negation, numeric boundaries, vehicle classes, and figures.
- [ ] Complete model review, native review, and learner feedback on the pilot.
- [ ] Expand to the full corpus only after the pilot is accepted.
- [ ] Record correction evidence, run strict validation, and rebuild the outputs.

## Near-term work while expansion is deferred

- [ ] Gather beta feedback on the languages already available.
- [ ] Keep an actionable list of terminology, readability, and figure-reference
      issues reported by learners.
- [ ] Track candidate-language reviewer availability and community contacts as
      they become available.
- [ ] Revisit the shortlist when a suitable reviewer and beta group are found.

## Research references

- [Ministry of Labour: 2025 Bangladeshi community report](https://www.lavoro.gov.it/documenti-e-norme/studi-e-statistiche/la-comunita-bangladese-in-italia-2025) — comparative community totals, age profile, and geographic concentration, based on end-2024 data.
- [Government migrant-community reports, 2025 edition](https://www.integrazionemigranti.gov.it/it-it/Dettaglio-approfondimento/id/66/Le-comunita-migranti-in-Italia-Edizione-2025) — broader community research starting point.
- [ISTAT: non-EU citizens in Italy, 2025 data](https://www.istat.it/wp-content/uploads/2026/10/Cittadini-non-comunitari-2025.pdf) — published October 2026; recent permit issuance and population trends.
- [MIT: foreign licence conversion](https://www.mit.gov.it/conversione-patente-estera) — recheck current agreements and conditions when evaluating candidates.
- [Provincia di Trento: non-EU licence conversion](https://www.provincia.tn.it/Servizi/Conversione-di-patenti-rilasciate-da-Stati-extracomunitari) — official operational guidance; checked during the November 2026 planning discussion.
