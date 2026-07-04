"""Ledger → prompt composition (docs/UI_UX_CONCEPT.md §5).

Collects the Intent-Ledger directives that apply to one shot — the ``film`` and ``look``
singletons, the shot's Bible refs (characters/ensembles, location, props), and the shot's own
attributes, in that order (broad first, most specific last). The result feeds
``PromptPayload.directives``; the locked subset feeds the compliance lint, which verifies the
finished provider prompt actually carries every locked directive.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from nexgen_engine.ledger.schema import Ledger


@dataclass(slots=True)
class ShotDirectives:
    directives: list[str] = field(default_factory=list)
    locked: list[str] = field(default_factory=list)


def directives_for_shot(ledger: Ledger, shot) -> ShotDirectives:
    """`shot` is a Shot pydantic instance (needs `id`, `character_refs`, `location_ref`,
    `prop_refs`). Unknown/absent ledger objects contribute nothing; duplicates collapse."""
    keys: list[str] = ["film", "look"]
    for ref in getattr(shot, "character_refs", None) or []:
        # A character_ref may name a character or an ensemble — the ledger key differs.
        keys.append(f"character:{ref}")
        keys.append(f"ensemble:{ref}")
    location = getattr(shot, "location_ref", None)
    if location:
        keys.append(f"location:{location}")
    for ref in getattr(shot, "prop_refs", None) or []:
        keys.append(f"prop:{ref}")
    shot_id = getattr(shot, "id", None)
    if shot_id:
        keys.append(f"shot:{shot_id}")

    out = ShotDirectives()
    seen: set[str] = set()
    for key in keys:
        for attribute in (ledger.objects.get(key) or {}).values():
            directive = (attribute.directive or attribute.tag).strip()
            if not directive or directive.lower() in seen:
                continue
            seen.add(directive.lower())
            out.directives.append(directive)
            if attribute.locked:
                out.locked.append(directive)
    return out
