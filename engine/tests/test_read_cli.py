"""The read-only JSON CLI (`python -m nexgen_engine.read <kind> <project_dir>`).

Invoked via subprocess so the `if __name__ == "__main__"` wiring is exercised
exactly as the Swift host runs it — a missing `__main__` guard would silently
no-op, which these guard against. Every kind must print parseable JSON; nothing
may reach stdout as a traceback.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

from nexgen_engine.core import layout as layout_mod
from nexgen_engine.core.modes import Mode
from nexgen_engine.shotlist import schema as shotlist_schema

# Point the subprocess's `nexgen_engine` at THIS checkout's engine dir (the
# grandparent of this test file), not wherever an editable install's .pth
# points — so the just-added read.py is importable under any worktree.
_PKG_PARENT = str(Path(__file__).resolve().parent.parent)


def _run(*args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(
        p for p in (_PKG_PARENT, env.get("PYTHONPATH", "")) if p
    )
    return subprocess.run(
        [sys.executable, "-m", "nexgen_engine.read", *args],
        capture_output=True,
        text=True,
        env=env,
    )


def _project(tmp_path: Path) -> Path:
    return layout_mod.init_project(tmp_path / "p", "demo", mode=Mode.SECTION)


def _minimal_shotlist() -> shotlist_schema.Shotlist:
    shot = shotlist_schema.Shot(
        id="s001",
        section="verse",
        time_start=0.0,
        time_end=4.0,
        duration_s=4.0,
        type=shotlist_schema.ShotType.PERFORMANCE,
        description="d",
        visual_prompt="a dim hallway, single overhead light",
        mood="m",
    )
    song = shotlist_schema.Song(
        title="t",
        audio_path="a.wav",
        analysis_path="an.json",
        bpm=120.0,
        duration_s=4.0,
    )
    return shotlist_schema.Shotlist(
        schema=shotlist_schema.SCHEMA_VERSION,
        mode=Mode.SECTION,
        project="demo",
        song=song,
        generated="2026-01-01",
        generator="test",
        shots=[shot],
    )


def test_phases_returns_ordered_list_with_pack_analysis(tmp_path: Path):
    # `phases` needs no project_dir and must include the musicvideo pack's phase.
    proc = _run("phases")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert isinstance(data, list)
    assert data[0] == "project_init"
    assert "analysis" in data  # active-pack phase surfaces through the same fn


def test_state_returns_project_object(tmp_path: Path):
    data_root = _project(tmp_path)
    proc = _run("state", str(data_root))
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert isinstance(data, dict)
    assert data["project"] == "demo"
    assert data["mode"] == "section"
    assert any(p["phase"] == "bible" for p in data["phases"])


def test_bible_on_fresh_project_is_null(tmp_path: Path):
    data_root = _project(tmp_path)
    proc = _run("bible", str(data_root))
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout) is None


def test_shotlist_on_fresh_project_is_null(tmp_path: Path):
    data_root = _project(tmp_path)
    proc = _run("shotlist", str(data_root))
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout) is None


def test_shotlist_after_save_returns_object(tmp_path: Path):
    data_root = _project(tmp_path)
    shotlist_schema.save(data_root, _minimal_shotlist())
    proc = _run("shotlist", str(data_root))
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert isinstance(data, dict)
    assert data["project"] == "demo"
    assert data["shots"][0]["id"] == "s001"


def test_sanity_no_shotlist_is_error_dict_exit_zero(tmp_path: Path):
    # Missing data is not a crash: the underlying fn returns {"error":"no shotlist"}
    # and the CLI passes it through with exit 0 (it's a valid read result).
    data_root = _project(tmp_path)
    proc = _run("sanity", str(data_root))
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert data["error"] == "no shotlist"


def test_unknown_kind_is_error_and_nonzero(tmp_path: Path):
    proc = _run("bogus", str(tmp_path))
    assert proc.returncode != 0
    data = json.loads(proc.stdout)
    assert "error" in data
    assert "bogus" in data["error"]


def test_missing_project_dir_is_error_and_nonzero(tmp_path: Path):
    proc = _run("state")  # state requires a project_dir
    assert proc.returncode != 0
    data = json.loads(proc.stdout)
    assert "error" in data


def test_no_args_is_usage_error(tmp_path: Path):
    proc = _run()
    assert proc.returncode != 0
    data = json.loads(proc.stdout)
    assert "error" in data


def test_bad_project_dir_does_not_crash(tmp_path: Path):
    # A nonexistent project dir must surface as a JSON error, never a traceback.
    proc = _run("state", str(tmp_path / "does-not-exist"))
    assert proc.returncode != 0
    data = json.loads(proc.stdout)
    assert "error" in data
    assert "Traceback" not in proc.stdout


def test_frames_empty_project_returns_empty_shots(tmp_path: Path):
    data_root = _project(tmp_path)
    proc = _run("frames", str(data_root))
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert data["project"] == "demo"
    assert data["shots"] == []


def test_frames_lists_candidates_per_shot_sorted(tmp_path: Path):
    data_root = _project(tmp_path)
    shot = data_root / "frames" / "s001"
    shot.mkdir(parents=True, exist_ok=True)
    (shot / "b.png").write_bytes(b"png")
    (shot / "a.png").write_bytes(b"png")
    (shot / "notes.txt").write_text("not an image", encoding="utf-8")
    (shot / "_frame_audit.yaml").write_text("status: pass\n", encoding="utf-8")
    (data_root / "frames" / "empty_dir").mkdir(exist_ok=True)

    proc = _run("frames", str(data_root))
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert len(data["shots"]) == 1  # image-less dirs are skipped
    entry = data["shots"][0]
    assert entry["shot_id"] == "s001"
    assert [f["name"] for f in entry["frames"]] == ["a.png", "b.png"]
    # Paths are relative to the project home, so the host can resolve them.
    assert entry["frames"][0]["path"].endswith("frames/s001/a.png")
    assert entry["audit"] == {"status": "pass"}


def test_frames_malformed_audit_is_treated_as_absent(tmp_path: Path):
    data_root = _project(tmp_path)
    shot = data_root / "frames" / "s002"
    shot.mkdir(parents=True, exist_ok=True)
    (shot / "kf.png").write_bytes(b"png")
    (shot / "_frame_audit.yaml").write_text("[not: a: mapping", encoding="utf-8")

    proc = _run("frames", str(data_root))
    data = json.loads(proc.stdout)
    assert data["shots"][0]["audit"] is None
