"""Read-only inventory of generated frame candidates for the host UI.

Reports exactly what is on disk under ``<data-root>/frames/``: one entry per
shot directory with its candidate images (sorted by name) and, when present, a
best-effort passthrough of the shot's ``_frame_audit.yaml``. No approval state
is invented — the engine records none today; selection happens through the
agent workflow.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from nexgen_engine.core import paths

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
AUDIT_FILENAME = "_frame_audit.yaml"


def inventory(project_dir: str) -> dict[str, Any]:
    """Frame candidates per shot, with paths relative to the project home
    (what the host resolves against)."""
    data_root = paths.data_root_of(Path(project_dir))
    if data_root is None:
        raise ValueError(f"no project at {project_dir}")
    home = paths.project_home(data_root)
    frames_dir = data_root / "frames"

    shots: list[dict[str, Any]] = []
    if frames_dir.is_dir():
        for shot_dir in sorted(p for p in frames_dir.iterdir() if p.is_dir()):
            images = sorted(
                f
                for f in shot_dir.iterdir()
                if f.is_file() and f.suffix.lower() in IMAGE_SUFFIXES
            )
            audit = _load_audit(shot_dir / AUDIT_FILENAME)
            if not images and audit is None:
                continue
            shots.append(
                {
                    "shot_id": shot_dir.name,
                    "frames": [
                        {"name": f.name, "path": str(f.relative_to(home))}
                        for f in images
                    ],
                    "audit": audit,
                }
            )

    return {
        "project": paths.project_name(data_root) or home.name,
        "shots": shots,
    }


def _load_audit(path: Path) -> dict[str, Any] | None:
    """Best-effort: a malformed or non-mapping audit file is treated as absent."""
    if not path.is_file():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    return data if isinstance(data, dict) else None
