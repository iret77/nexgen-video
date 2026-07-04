"""Model router + UI contract (Phase D)."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from nexgen_engine.core import router, ui_contract
from nexgen_engine.core import layout as layout_mod
from nexgen_engine.core.modes import Mode
from nexgen_engine.pack import EngineRegistry


def _run(*args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(
        p
        for p in (str(Path(__file__).resolve().parent.parent), env.get("PYTHONPATH", ""))
        if p
    )
    return subprocess.run(
        [sys.executable, "-m", "nexgen_engine.read", *args],
        capture_output=True, text=True, env=env,
    )


def test_floors_are_deliberate_not_uniform():
    assert router.resolve("distill") == {
        "task_class": "distill", "tier": "fast",
        "model": router.DEFAULT_MANIFEST["fast"], "effort": "low", "escalated": False,
    }
    assert router.resolve("interpretation")["tier"] == "deep"
    assert router.resolve("interpretation")["effort"] == "high"


def test_escalation_is_one_step_and_bounded_at_deep():
    assert router.resolve("distill", escalate=True)["tier"] == "medium"
    deep = router.resolve("planning", escalate=True)
    assert deep["tier"] == "deep"
    assert deep["escalated"] is False  # already at the ceiling — nothing to escalate to


def test_unknown_task_class_raises():
    with pytest.raises(ValueError, match="unknown task class"):
        router.resolve("vibes")


def test_project_manifest_overrides_known_tiers_only(tmp_path: Path):
    data_root = layout_mod.init_project(tmp_path / "p", "demo", mode=Mode.SECTION)
    (data_root / router.MANIFEST_FILENAME).write_text(
        "fast: my-tiny-model\nbogus: nope\n", encoding="utf-8"
    )
    resolved = router.manifest(data_root)
    assert resolved["fast"] == "my-tiny-model"
    assert resolved["medium"] == router.DEFAULT_MANIFEST["medium"]
    assert "bogus" not in resolved


def test_registry_validates_contract_entries():
    registry = EngineRegistry()
    registry.register_ui_contract("analysis", surface="choice", task_class="classification")
    assert registry.ui_contracts["analysis"] == {"surface": "choice", "task_class": "classification"}
    with pytest.raises(ValueError, match="surface"):
        registry.register_ui_contract("x", surface="wizard", task_class="distill")
    with pytest.raises(ValueError, match="task_class"):
        registry.register_ui_contract("x", surface="prose", task_class="vibes")


def test_core_contract_covers_every_core_phase():
    from nexgen_engine.core.gates import CORE_PHASES

    assert set(ui_contract.CORE_CONTRACT) == set(CORE_PHASES)
    for phase, entry in ui_contract.CORE_CONTRACT.items():
        ui_contract.validate_entry(phase, entry)


def test_read_cli_router_and_contract_need_no_project():
    proc = _run("router")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert data["tiers"]["deep"] == router.DEFAULT_MANIFEST["deep"]
    assert data["task_classes"]["distill"]["effort"] == "low"

    proc = _run("contract")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert data["phases"]["brief"] == {"surface": "prose", "task_class": "interpretation"}
    # The installed musicvideo pack contributes its analysis phase.
    assert data["phases"].get("analysis", {}).get("surface") in (None, "choice")
