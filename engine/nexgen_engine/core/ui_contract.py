"""The minimal plugin UI contract (docs/UI_UX_CONCEPT.md §7).

Each phase declares its *default* interaction surface and its task class — defaults, not rigid
modes (a phase may start as REVIEW, become PROSE when nothing works, then DIRECT once a
direction is chosen). The host renders these natively; the router maps the task class to a
model floor. Core phases carry engine defaults; packs override or extend via
``EngineRegistry.register_ui_contract``.
"""

from __future__ import annotations

from typing import Any

from nexgen_engine.core.router import TASK_CLASSES

SURFACES: tuple[str, ...] = ("choice", "prose", "review")

# Engine defaults for the core phases: what kind of interaction the phase's artifact wants by
# default, and how much compute its work deserves (router task class).
CORE_CONTRACT: dict[str, dict[str, str]] = {
    "project_init": {"surface": "choice", "task_class": "assembly"},
    "brief": {"surface": "prose", "task_class": "interpretation"},
    "production_design": {"surface": "review", "task_class": "planning"},
    "treatment": {"surface": "prose", "task_class": "interpretation"},
    "storyboard": {"surface": "review", "task_class": "planning"},
    "bible": {"surface": "review", "task_class": "planning"},
    "shotlist": {"surface": "review", "task_class": "planning"},
    "sanity": {"surface": "review", "task_class": "classification"},
    "frames": {"surface": "review", "task_class": "review"},
    "render": {"surface": "choice", "task_class": "assembly"},
}


def validate_entry(phase: str, entry: dict[str, str]) -> dict[str, str]:
    surface = entry.get("surface", "")
    task_class = entry.get("task_class", "")
    if surface not in SURFACES:
        raise ValueError(f"phase {phase!r}: surface must be one of {', '.join(SURFACES)}")
    if task_class not in TASK_CLASSES:
        raise ValueError(
            f"phase {phase!r}: task_class must be one of {', '.join(sorted(TASK_CLASSES))}"
        )
    return {"surface": surface, "task_class": task_class}


def full_contract() -> dict[str, Any]:
    """Core defaults overlaid with the installed packs' declarations."""
    from nexgen_engine.pack import discover_packs

    contract = {phase: dict(entry) for phase, entry in CORE_CONTRACT.items()}
    contract.update(discover_packs().engine.ui_contracts)
    return {"surfaces": list(SURFACES), "phases": contract}
