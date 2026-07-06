#!/usr/bin/env bash
# Regenerate the NexGenEngineTests fixture project and the Python-oracle goldens.
#
# The Python engine (engine/) is the authority: this script scaffolds an
# authentic fixture project with the engine's own schema `save` functions, then
# dumps each `python -m nexgen_engine.read <kind>` document as a golden JSON.
# The Swift parity tests replay these against the Swift port.
#
# Requires `uv` (https://docs.astral.sh/uv/). Idempotent: it wipes and rebuilds
# both the Fixtures and Goldens trees. Run from anywhere.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$REPO_ROOT/engine"
TESTS_DIR="$REPO_ROOT/Tests/NexGenEngineTests"
FIXTURE_HOME="$TESTS_DIR/Fixtures/basic-project"
GOLDENS_DIR="$TESTS_DIR/Goldens/basic-project"
DATA_ROOT="$FIXTURE_HOME/_studio"

# The engine's runtime deps (pyproject) plus the local engine itself. `uv run
# --no-project` keeps this independent of any ambient venv; `--with <path>`
# builds and installs the engine from source.
UV=(uv run --no-project
    --with pydantic
    --with pyyaml
    --with mcp
    --with "$ENGINE_DIR"
    python)

echo "==> Wiping fixture + goldens"
rm -rf "$FIXTURE_HOME" "$GOLDENS_DIR"
mkdir -p "$(dirname "$FIXTURE_HOME")" "$GOLDENS_DIR"

echo "==> Scaffolding fixture project via the Python engine"
"${UV[@]}" - "$FIXTURE_HOME" <<'PY'
import sys
from datetime import date
from pathlib import Path

from nexgen_engine.core import layout as layout_mod
from nexgen_engine.core.modes import Mode
from nexgen_engine.brief import schema as brief_schema
from nexgen_engine.brief.schema import (
    Brief, Mission, AspectRatio, ConceptType, VisualMedium, FigurePresence, LyricsIntegration,
)
from nexgen_engine.ledger import schema as ledger_schema

home = Path(sys.argv[1])
data_root = layout_mod.init_project(home, "basic-project", Mode.BEAT, budget_eur=50.0)

# Minimal, schema-valid Brief (LIVE_ACTION_REALISTIC needs no visual_medium_notes).
brief = Brief(
    project="basic-project",
    generated=date(2026, 1, 1).isoformat(),
    mission=Mission.DEMO,
    target_platform="web",
    aspect_ratio=AspectRatio.LANDSCAPE_16_9,
    project_mode="beat",
    concept_type=ConceptType.ABSTRACT,
    visual_medium=VisualMedium.LIVE_ACTION_REALISTIC,
    figures=FigurePresence.NONE,
    lyrics_integration=LyricsIntegration.IGNORED,
)
brief_schema.save(data_root, brief)

# A single locked ledger attribute exercises the ledger read.
ledger_schema.set_attribute(
    str(data_root), "look", None, "palette",
    tag="warm amber and teal",
    directive="warm amber/teal grade",
    source="director note",
    locked=True,
)

# Authentic shotlist (BEAT mode) saved via the engine's own schema, so the
# cost golden is computed against a real, schema-validated document. Shots are
# designed to exercise every BEAT/PHRASE branch of `render.costs.estimate`:
#   s001  FAL, 12s  -> truncated to model max (10s) @ Pro 1080p
#   s002  FAL,  3s  -> padded up to provider-min (5s) @ Pro 1080p
#   s003  FAL,  7s  -> in-range @ Pro 1080p
#   s004  RUNWAY, seedance-2.0 suggestion, 8s -> Bug-24 legacy fallback path
from nexgen_engine.shotlist import schema as shotlist_schema
from nexgen_engine.shotlist.schema import (
    Shotlist, Shot, Song, ShotType, ModelSuggestion, SceneVideoProvider,
)

song = Song(
    title="Fixture Song",
    artist="Fixture Artist",
    audio_path="inbox/song.wav",
    analysis_path="inbox/analysis.json",
    bpm=120.0,
    duration_s=30.0,
)

def _shot(idx, start, end, provider, *, suggestion=None):
    return Shot(
        id=f"s{idx:03d}",
        section="verse",
        time_start=start,
        time_end=end,
        duration_s=round(end - start, 3),
        type=ShotType.PERFORMANCE,
        description=f"shot {idx}",
        visual_prompt=f"visual {idx}",
        mood="calm",
        scene_video_provider=provider,
        model_suggestion=suggestion,
    )

shotlist = Shotlist(
    schema="shotlist/v3",
    mode=Mode.BEAT,
    project="basic-project",
    song=song,
    generated=date(2026, 1, 1).isoformat(),
    generator="regen-goldens",
    budget_eur=50.0,
    shots=[
        _shot(1, 0.0, 12.0, SceneVideoProvider.FAL),
        _shot(2, 12.0, 15.0, SceneVideoProvider.FAL),
        _shot(3, 15.0, 22.0, SceneVideoProvider.FAL),
        _shot(4, 22.0, 30.0, SceneVideoProvider.RUNWAY,
              suggestion=ModelSuggestion.SEEDANCE_2_0),
    ],
)
shotlist_schema.save(data_root, shotlist)

print(f"scaffolded {data_root}")
PY

echo "==> Emitting goldens"
# `state/brief/ledger` need the project dir; `phases/router/contract` are projectless.
for kind in state phases brief ledger contract router; do
  case "$kind" in
    phases|router|contract) arg="" ;;
    *)                       arg="$DATA_ROOT" ;;
  esac
  out="$GOLDENS_DIR/$kind.json"
  # Pretty-print so the goldens diff cleanly in review; the reader still emits
  # compact JSON, we just reformat here.
  "${UV[@]}" -m nexgen_engine.read "$kind" $arg | "${UV[@]}" -m json.tool > "$out"
  echo "  wrote $out"
done

echo "==> Emitting cost-estimate golden via the Python cost oracle"
# The engine keeps costs.yaml as a deployment-external file (it ships no
# default), so we hand `load_costs` a costs.yaml whose VALUES are identical to
# the Swift `CostsConfig.bundledDefault`. Both sides must price from the same
# numbers or the parity test is meaningless. Keep this YAML in lockstep with
# `Sources/NexGenEngine/Cost/LoadCosts.swift::bundledDefaultYAML`.
"${UV[@]}" - "$DATA_ROOT" "$GOLDENS_DIR/cost-estimate.json" <<'PY'
import json
import sys
import tempfile
from dataclasses import asdict
from pathlib import Path

from nexgen_engine.render.costs import load_costs, estimate
from nexgen_engine.shotlist import schema as shotlist_schema

data_root = Path(sys.argv[1])
out_path = Path(sys.argv[2])

COSTS_YAML = """
pricing:
  seedance2:
    eur_per_second: 0.10
    max_duration_s: 10.0
    default_ratio: "16:9"
  "fal:bytedance/seedance-2.0/pro":
    eur_per_second: 0.682
    max_duration_s: 10.0
    default_ratio: "16:9"
    min_duration_s: 5.0
    eur_per_second_by_resolution:
      720p: 0.3024
      1080p: 0.682
  "fal:bytedance/seedance-2.0/fast":
    eur_per_second: 0.2419
    max_duration_s: 10.0
    default_ratio: "16:9"
    min_duration_s: 5.0
    eur_per_second_by_resolution:
      720p: 0.2419
model_map:
  SEEDANCE_2_0: seedance2
defaults:
  preview: "fal:bytedance/seedance-2.0/fast"
  final: "fal:bytedance/seedance-2.0/pro"
overlap:
  pre_s: 1.5
  post_s: 1.5
polling:
  interval_s: 5
  timeout_s: 600
cost_guard:
  confirm_threshold_eur: 10.0
  project_wide_budget: true
"""

with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
    f.write(COSTS_YAML)
    costs_path = Path(f.name)

costs = load_costs(costs_path)
shotlist = shotlist_schema.load(data_root)
assert shotlist is not None, "fixture shotlist missing"

# Golden covers phase=final at the brief-default final_resolution (1080p).
est = estimate(shotlist, costs, "final", final_resolution="1080p")

payload = {
    "phase": est.phase,
    "mode": est.mode.value,
    "total_eur": est.total_eur,
    "budget_eur": est.budget_eur,
    "over_budget": est.over_budget,
    "shot_estimates": [asdict(se) for se in est.shot_estimates],
}
out_path.write_text(json.dumps(payload, indent=4, sort_keys=True) + "\n", encoding="utf-8")
print(f"  wrote {out_path}")
PY

echo "==> Done. Fixture: $FIXTURE_HOME  Goldens: $GOLDENS_DIR"
