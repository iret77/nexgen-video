"""Generic gate -> artifact-formatter dispatch.

The engine MCP's `show_artifact` tool needs to turn any gate name into the
Markdown its artifact formatter produces, without the caller knowing which
formatter belongs to which gate. The mapping below is the single, format-neutral
place that knows it. A gate with no formatter (e.g. `project_init`, `sanity`) or
no artifact written yet returns a plain "nothing yet" string rather than raising.

Pack-contributed gates whose formatter already lives in core (`analysis`) map
here too; a pack does not need to re-register a formatter.
"""

from __future__ import annotations

from pathlib import Path
from typing import Callable

from nexgen_engine.show import formatters

#: gate name -> formatter taking the project data root, returning Markdown.
_GATE_FORMATTERS: dict[str, Callable[[Path], str]] = {
    "brief": formatters.show_brief,
    "production_design": formatters.show_production_design,
    "treatment": formatters.show_treatment,
    "storyboard": formatters.show_storyboard,
    "bible": formatters.show_bible,
    "shotlist": formatters.show_shotlist,
    "analysis": formatters.show_analysis,
    "render": formatters.show_renders,
}


def show_gate_artifact(project_dir: Path, gate: str) -> str:
    """Markdown for *gate*'s artifact, or a clear "nothing yet" string.

    Never raises for a missing artifact or an unknown gate: a gate without a
    formatter returns a note; a formatter that can't find its artifact (some
    raise `FileNotFoundError`, others return their own placeholder) is normalized
    to a "nothing yet" string so the MCP tool stays safe to call at any phase.
    """
    formatter = _GATE_FORMATTERS.get(gate)
    if formatter is None:
        return f"_Gate `{gate}` has no display artifact._"
    try:
        return formatter(project_dir)
    except FileNotFoundError:
        return f"_Nothing for gate `{gate}` yet._"
