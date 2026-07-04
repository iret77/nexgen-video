"""Ledger → prompt composition + locked-directive compliance lint (Phase C3)."""

from types import SimpleNamespace

from nexgen_engine.ledger.schema import Attribute, Ledger
from nexgen_engine.render.prompt.builder import PromptPayload, build_for_nano_banana
from nexgen_engine.render.prompt.compliance_linter import lint_locked_directives
from nexgen_engine.render.prompt.ledger_directives import directives_for_shot


def _ledger() -> Ledger:
    led = Ledger()
    led.objects = {
        "film": {"palette": Attribute(tag="Muted teal-and-rust palette")},
        "look": {"grain": Attribute(tag="Heavy 16mm grain", locked=True)},
        "character:mara": {
            "wardrobe": Attribute(
                tag="Red jacket",
                directive="Mara wears her faded red canvas jacket",
                locked=True,
            )
        },
        "shot:s001": {"pace": Attribute(tag="Slow, deliberate movement")},
        "prop:dagger": {"state": Attribute(tag="The dagger stays sheathed")},
    }
    return led


def _shot(**overrides):
    base = dict(id="s001", character_refs=["mara"], location_ref=None, prop_refs=["dagger"])
    base.update(overrides)
    return SimpleNamespace(**base)


def test_collects_broad_to_specific_and_marks_locked():
    result = directives_for_shot(_ledger(), _shot())
    assert result.directives == [
        "Muted teal-and-rust palette",
        "Heavy 16mm grain",
        "Mara wears her faded red canvas jacket",
        "The dagger stays sheathed",
        "Slow, deliberate movement",
    ]
    assert result.locked == [
        "Heavy 16mm grain",
        "Mara wears her faded red canvas jacket",
    ]


def test_unknown_refs_contribute_nothing():
    result = directives_for_shot(_ledger(), _shot(id="s999", character_refs=["ghost"], prop_refs=[]))
    assert result.directives == ["Muted teal-and-rust palette", "Heavy 16mm grain"]


def test_builders_carry_directives_and_lint_passes():
    result = directives_for_shot(_ledger(), _shot())
    payload = PromptPayload(subject="Mara stands at the rooftop edge", directives=result.directives)
    prompt = build_for_nano_banana(payload)
    assert "faded red canvas jacket" in prompt
    assert "16mm grain" in prompt
    assert lint_locked_directives(prompt, result.locked) == []


def test_lint_flags_missing_locked_directive_as_error():
    prompt = build_for_nano_banana(PromptPayload(subject="Mara stands at the rooftop edge"))
    findings = lint_locked_directives(prompt, ["Mara wears her faded red canvas jacket"])
    assert len(findings) == 1
    assert findings[0].severity == "error"
    assert findings[0].code == "LOCKED_DIRECTIVE_MISSING"
