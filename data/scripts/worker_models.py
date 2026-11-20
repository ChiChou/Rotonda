"""Lower-cost worker models for content tasks.

Extraction, translation, explanation and review tasks are bounded and source-bound, so
they run on a cheaper model rather than a frontier one. Any listed model may author or
review; provenance records the model that actually ran. Add a model here to allow it.
Choose one per run with --model or PATENTE_WORKER_MODEL.
"""
import os

# Model ID -> command-line runtime that executes it.
BACKENDS = {
    'gpt-6.1-terra': 'codex',
    'claude-sonnet-5-5': 'claude',
    'claude-haiku-5-5': 'claude',
}
DEFAULT = os.environ.get('PATENTE_WORKER_MODEL', 'gpt-6.1-terra')
if DEFAULT not in BACKENDS:
    raise ValueError(f'PATENTE_WORKER_MODEL must be one of {sorted(BACKENDS)}')


def is_worker(model):
    return model in BACKENDS


def is_correction(origin):
    """Origins of independently reviewed source corrections, e.g. 'gpt-6.1-terra:correction'."""
    model, _, kind = (origin or '').rpartition(':')
    return kind == 'correction' and is_worker(model)
