---
name: patente-explain
description: Generate canonical Italian driving quiz explanations, then translate frozen explanations into individual helper language packs.
---

Use [the staged contract](../../../data/docs/explanation-batches.md).
Italian authors read [the Italian prompt](../../../data/docs/prompts/explain-italian.md).
Explanation translators read [the localization prompt](../../../data/docs/prompts/translate-explanations.md).

Use staged_explanations.py with a lower-cost worker model (`--model`; see
data/scripts/worker_models.py), such as GPT-6.1 Terra or Claude Sonnet. Generate Italian
only before localization. Translate one helper language per separate task, using the
stored Italian explanation as authority; do not repeat factual research. Use that
bank’s actual Italian text, rather than another bank’s version of the same question.
Reuse existing canonical output and eligible old drafts. Preserve source/verdict/image
identity and Italian text hashes. Never overwrite a completed pack to fill other gaps.

Review is disabled by user request. New rows are generated_unreviewed; retain older
review records unchanged. Structural validation and provenance are still required.
No reviewer dispatch or automatic retries. Workers do not launch other workers.
