"""MCP lifecycle action-tools — they wire existing engine machinery, no new logic.

These exercise the helper functions (the `@mcp.tool` wrappers are 1-line passthroughs
to them). The musicvideo pack is installed in the test env, so `init_project` must
merge its dirs (audio/lyrics/analysis) onto the core scaffold.
"""

from pathlib import Path

from nexgen_engine import mcp_server
from nexgen_engine.core import gates as gates_mod
from nexgen_engine.core.layout import CORE_SUBDIRS


def test_init_project_scaffolds_core_plus_pack(tmp_path: Path):
    home = tmp_path / "proj"
    result = mcp_server.init_project(str(home), "demo", mode="beat", budget_eur=80.0)

    assert result["project"] == "demo"
    assert result["created"] is True
    data_root = Path(result["data_root"])
    assert data_root.name == "_studio"
    assert data_root.is_dir()

    for sub in CORE_SUBDIRS:
        assert (data_root / sub).is_dir(), f"missing core dir {sub}"
    for pack_dir in ("audio", "lyrics", "analysis"):  # musicvideo pack contribution
        assert (data_root / pack_dir).is_dir(), f"missing pack dir {pack_dir}"

    assert (data_root / "project.yaml").exists()
    assert (data_root / "gates.yaml").exists()


def test_approve_gate_then_load_shows_approved(tmp_path: Path):
    data_root = Path(
        mcp_server.init_project(str(tmp_path / "p"), "demo")["data_root"]
    )

    out = mcp_server.approve_gate(str(data_root), "brief", notes="looks good")
    assert out["phase"] == "brief"
    assert out["approved"] is True
    assert out["notes"] == "looks good"
    assert out["approved_at"] is not None

    assert gates_mod.load(data_root).get("brief").approved is True


def test_rewind_resets_target_and_following(tmp_path: Path):
    data_root = Path(
        mcp_server.init_project(str(tmp_path / "p"), "demo")["data_root"]
    )
    for phase in ("treatment", "bible", "shotlist", "render"):
        gates_mod.approve(data_root, phase)

    out = mcp_server.rewind(str(data_root), "bible")
    reset = out["reset_phases"]
    assert reset[0] == "bible"
    assert "shotlist" in reset and "render" in reset

    g = gates_mod.load(data_root)
    assert g.get("treatment").approved is True   # before target → kept
    assert g.get("bible").approved is False       # target → reset
    assert g.get("render").approved is False       # following → reset


def test_rewind_orders_pack_phase(tmp_path: Path):
    # `analysis` (pack phase) must sit in the merged ordered list so rewinding to
    # it (or before it) is well-defined and doesn't raise "unknown gate".
    data_root = Path(
        mcp_server.init_project(str(tmp_path / "p"), "demo")["data_root"]
    )
    out = mcp_server.rewind(str(data_root), "analysis")
    assert "analysis" in out["reset_phases"]


def test_estimate_cost_on_fresh_project(tmp_path: Path):
    data_root = Path(
        mcp_server.init_project(str(tmp_path / "p"), "demo", budget_eur=120.0)["data_root"]
    )
    out = mcp_server.estimate_cost(str(data_root))
    assert out["budget_eur"] == 120.0
    assert out["spent_eur"] == 0.0       # nothing rendered yet
    assert out["remaining_eur"] == 120.0
    assert out["over_budget"] is False


def test_show_artifact_nothing_yet(tmp_path: Path):
    data_root = Path(
        mcp_server.init_project(str(tmp_path / "p"), "demo")["data_root"]
    )
    # brief artifact not written → must not raise, must signal emptiness.
    brief = mcp_server.show_artifact(str(data_root), "brief")
    assert brief["gate"] == "brief"
    assert "yet" in brief["markdown"].lower() or "fehlt" in brief["markdown"].lower() \
        or "keine" in brief["markdown"].lower()

    # a gate with no display artifact also returns a string, never raises.
    none_gate = mcp_server.show_artifact(str(data_root), "project_init")
    assert isinstance(none_gate["markdown"], str)
    assert none_gate["markdown"]
