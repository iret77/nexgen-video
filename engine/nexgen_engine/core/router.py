"""Deliberate compute (docs/UI_UX_CONCEPT.md §6): which model and how much thinking a task gets
is assigned by **task class** — never left to a single default and never guessed per call.

- A **fixed floor** per task class covers the common case: low effort for clear, direct,
  deterministic work (high effort makes it *worse*), high effort for planning/interpretation.
- **Escalation** is reactive and bounded: exactly one tier up, only on a concrete gate failure
  (lint error, schema violation, user reject). No meta-classifier, no de-escalation.
- **Tiers, not model ids**: ``fast``/``medium``/``deep`` resolve through a manifest that names
  the *latest* model of each family. New model generations are adopted by editing the manifest
  (``models.yaml`` in the project data root overrides the shipped defaults) — never by a code
  change.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from nexgen_engine.core import paths

TIERS: tuple[str, ...] = ("fast", "medium", "deep")

DEFAULT_MANIFEST: dict[str, str] = {
    "fast": "claude-haiku-4-5",
    "medium": "claude-sonnet-5",
    "deep": "claude-opus-4-8",
}

TASK_CLASSES: dict[str, dict[str, str]] = {
    "distill": {"tier": "fast", "effort": "low"},
    "classification": {"tier": "fast", "effort": "low"},
    "assembly": {"tier": "medium", "effort": "low"},
    "review": {"tier": "medium", "effort": "low"},
    "planning": {"tier": "deep", "effort": "high"},
    "interpretation": {"tier": "deep", "effort": "high"},
}

MANIFEST_FILENAME = "models.yaml"


def manifest(project_dir: str | Path | None = None) -> dict[str, str]:
    """Shipped defaults, overlaid with the project's ``models.yaml`` (known tiers only)."""
    resolved = dict(DEFAULT_MANIFEST)
    if project_dir:
        data_root = paths.data_root_of(Path(project_dir))
        if data_root is not None:
            path = data_root / MANIFEST_FILENAME
            if path.is_file():
                try:
                    data = yaml.safe_load(path.read_text(encoding="utf-8"))
                except Exception:
                    data = None
                if isinstance(data, dict):
                    for tier in TIERS:
                        value = data.get(tier)
                        if isinstance(value, str) and value.strip():
                            resolved[tier] = value.strip()
    return resolved


def resolve(
    task_class: str,
    escalate: bool = False,
    project_dir: str | Path | None = None,
) -> dict[str, Any]:
    """Floor for the task class; with ``escalate`` exactly one tier up (bounded at deep)."""
    floor = TASK_CLASSES.get(task_class)
    if floor is None:
        raise ValueError(
            f"unknown task class {task_class!r}; expected one of {', '.join(sorted(TASK_CLASSES))}"
        )
    tier = floor["tier"]
    escalated = False
    if escalate:
        index = TIERS.index(tier)
        if index + 1 < len(TIERS):
            tier = TIERS[index + 1]
            escalated = True
    return {
        "task_class": task_class,
        "tier": tier,
        "model": manifest(project_dir)[tier],
        "effort": floor["effort"],
        "escalated": escalated,
    }


def describe(project_dir: str | Path | None = None) -> dict[str, Any]:
    """The full routing table for the host UI / read CLI."""
    return {"tiers": manifest(project_dir), "task_classes": TASK_CLASSES}
