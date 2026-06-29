"""Storyboard-Schema v1.

Pro Section eine Step-Sequenz. Jeder Step hat einen Funktions-Tag,
eine Subject-Beschreibung mit Vektor (für Frame-Zero), eine Camera-
Anker-Beschreibung (Distanz / Winkel / Move), und einen optionalen
Location-View-Bedarf, aus dem die Bible-Phase die Location-Sheets
ableitet.

Storyboard ist explizit grob — keine fünf-Komponenten-visual_prompts,
keine Bible-IDs (die existieren noch nicht final). Es ist die
Brücke zwischen Treatment (Story) und Shotlist (technische Umsetzung).
"""

from __future__ import annotations

import re
from enum import Enum
from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SCHEMA_VERSION = "storyboard/v1"
STEP_ID_RE = re.compile(r"^[a-z0-9_]+\.\d{2}$")
"""Step-ID-Konvention: ``<section_id>.<NN>``, z.B. ``verse1.03`` oder
``chorus2.07``. So bleibt die Sequenz lesbar und im UI sortierbar."""


class StepFunction(str, Enum):
    STORY = "story"
    MOOD_INSERT = "mood-insert"
    PERFORMANCE = "performance"
    CUTAWAY = "cutaway"
    STRUCTURAL_ANCHOR = "structural-anchor"
    TRANSITION = "transition"


class Step(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    """Section-relative ID, z.B. ``verse1.03``. Pflicht."""

    function: StepFunction
    """Funktion im Musikvideo-Kontext. Bestimmt den Pflicht-Mix der Section."""

    subject: str
    """Wer macht WAS, in welcher Anfangspose, in welche Bewegungsrichtung —
    der Frame-Zero-Inhalt für später. Bsp.: 'Alex steht im Schultor,
    linkes Bein vor, Blick zum Hof, im Begriff einzutreten'."""

    camera: str
    """Anfangs-Framing UND Move. 'low-angle ~1.5 m, ~3 m Distanz, statisch
    für 2 s, dann langsame 1 m Rückfahrt'."""

    setting_hint: str = ""
    """Welche Location ist gemeint, welche Perspektive grob. Wird in
    der Bible-Phase zum konkreten ``Location.sheets``-Key. Bsp.:
    'Schulhof, vom Tor aus betrachtet'."""

    location_view_request: str = ""
    """Vorschlag für den Sheet-View-Key, den die Bible für diese Location
    zur Verfügung stellen soll. Bsp.: ``entrance``, ``wide.morning``,
    ``detail.chalkboard``. Leerwert = noch nicht entschieden."""

    character_view_request: dict[str, str] = Field(default_factory=dict)
    """Pro Character-Hinweis welche Sheet-View bevorzugt wird. Keys
    sind die Character-Namen aus dem Treatment (noch keine bible-IDs);
    der Bible-Agent mappt das beim Persistieren auf die finalen IDs.
    Bsp.: ``{"alex": "side"}``."""

    prop_request: list[str] = Field(default_factory=list)
    """Welche Props sind in diesem Step relevant — Bible muss sie
    vorhalten. Klartext, der Bible-Agent leitet daraus IDs ab."""

    # ---- v0.7+: raeumlich-kompositorische Felder, 1:1 in shotlist mappen
    framing: str = ""
    """Bildausschnitt: WIDE/FULL/MS/MCU/CU/ECU/OTS/POV/INSERT/AERIAL.
    Wird vom Shotlist-Agent direkt nach Shot.framing uebernommen
    (PFLICHT ab v0.7). Leerwert = noch nicht entschieden, Sanity
    warnt dann beim Shotlist-Build."""

    visible_zones: list[str] = Field(default_factory=list)
    """Zone-IDs aus Bible.Location.zones, die der Step zeigt. Pflicht
    fuer WIDE/FULL/MS/OTS/POV/AERIAL (siehe Framing-Risk-Matrix).
    Wird 1:1 nach Shot.visible_zones uebernommen."""

    zone_introduces: list[str] = Field(default_factory=list)
    """Optional: Zonen, die der Step erstmals etabliert. Beim Frame-
    Approve aktualisiert Bible.Location.zones (Status -> dirty)."""

    camera_setup: dict[str, str] = Field(default_factory=dict)
    """Kamera-Triplet (height/angle/lens_hint). Als dict statt
    Pydantic-Submodel, damit der Storyboard-Agent kompakt schreiben
    kann; Shotlist-Agent baut daraus CameraSetup beim Mapping.
    Erlaubte Keys: height, angle, lens_hint, note. Werte siehe
    Shotlist-Schema {CameraHeight,CameraAngle,LensHint}.
    PFLICHT ab v0.8."""

    character_blocking: list[dict[str, str]] = Field(default_factory=list)
    """Pro Figur Position/Pose/Gaze/Set-Bezug. Liste von dicts mit
    Keys: character_ref, position, pose, gaze, relation_to_set
    (letzteres optional). PFLICHT ab v0.8 bei >=2 Figuren pro Step."""

    notes: str = ""

    @field_validator("id")
    @classmethod
    def _id_format(cls, v: str) -> str:
        if not STEP_ID_RE.match(v):
            raise ValueError(
                f"Step-ID {v!r} muss dem Muster '<section>.<NN>' folgen"
            )
        return v

    @field_validator("subject", "camera")
    @classmethod
    def _nonempty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("Pflichtfeld darf nicht leer sein")
        return v


class Section(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    """Section-Slug aus dem Treatment / der Analysis, z.B. ``verse1``."""

    label: str = ""
    """Lesbarer Name für die UI. ``Verse 1`` etc."""

    time_start: float = 0.0
    time_end: float = 0.0
    """Sekunden im Song. Aus analysis.interpretation.section_labels
    übernommen — der Storyboard-Agent füllt das beim Schreiben aus."""

    energy: str = ""
    """Grobe Energy-Stufe: low / mid / high / drop. Treatment-bezogen,
    nicht numerisch."""

    function: str = ""
    """Section-Funktion: aufbau / refrain / kontrast / aufloesung etc."""

    pattern_override: str | None = None
    """Director-Pattern-ID, das **fuer diese Section** verwendet wird —
    ueberschreibt brief.director_pattern (v0.13.0).

    Anwendungsfall: Intro nach Shinkai-Ballad-Sprache, Chorus nach
    Trigger-Action-Energy. Storyboard-Agent setzt das pro Section
    bewusst; bleibt das Feld leer, gilt das projekt-weite Pattern
    aus dem Brief. PATTERN_DRIFT-Sanity rechnet Section-spezifisch
    (Pro-Section-Override hat Vorrang vor Brief-Default)."""

    steps: list[Step] = Field(default_factory=list)

    @field_validator("steps")
    @classmethod
    def _steps_have_section_prefix(cls, v: list[Step]) -> list[Step]:
        # Ensure step IDs all share the same section prefix.
        if not v:
            return v
        prefix = v[0].id.split(".", 1)[0]
        for s in v:
            if s.id.split(".", 1)[0] != prefix:
                raise ValueError(
                    f"Step-IDs in einer Section müssen denselben Prefix tragen, "
                    f"erwartet {prefix!r}, war {s.id!r}"
                )
        return v


class StoryboardMeta(BaseModel):
    model_config = ConfigDict(extra="forbid")

    project: str
    version: int = Field(ge=1)
    generated: str
    origin: str = "agent_proposal"
    generator: str = "storyboard-agent@v0.5"
    summary_oneline: str = ""
    notes: str | None = None


class Storyboard(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_: str = Field(alias="schema", default=SCHEMA_VERSION)
    meta: StoryboardMeta
    sections: list[Section] = Field(default_factory=list)

    @field_validator("schema_")
    @classmethod
    def _schema_const(cls, v: str) -> str:
        if v != SCHEMA_VERSION:
            raise ValueError(
                f"schema muss {SCHEMA_VERSION!r} sein, war {v!r}"
            )
        return v

    @model_validator(mode="after")
    def _step_ids_unique(self) -> "Storyboard":
        seen: set[str] = set()
        for section in self.sections:
            for step in section.steps:
                if step.id in seen:
                    raise ValueError(f"doppelte Step-ID {step.id!r}")
                seen.add(step.id)
        return self

    def all_steps(self) -> list[Step]:
        out: list[Step] = []
        for s in self.sections:
            out.extend(s.steps)
        return out

    def location_view_demand(self) -> dict[str, set[str]]:
        """Aggregat: welche Location braucht welche Sheet-Views?

        Heuristik: Aus ``setting_hint`` wird die Location-ID grob
        abgeleitet (Tokens vor dem ersten Komma, lowercase, underscore).
        ``location_view_request`` ergibt den View-Key. Leerwerte werden
        ignoriert. Der Bible-Agent verwendet das als Generierungs-Plan.
        """
        out: dict[str, set[str]] = {}
        for step in self.all_steps():
            view = (step.location_view_request or "").strip()
            if not view:
                continue
            hint = (step.setting_hint or "").strip()
            if not hint:
                continue
            head = hint.split(",", 1)[0].strip().lower()
            head = re.sub(r"[^a-z0-9]+", "_", head).strip("_")
            if not head:
                continue
            out.setdefault(head, set()).add(view)
        return out


# ---------------------------------------------------------------------- IO


def _dir(project_dir: Path) -> Path:
    p = project_dir / "storyboard"
    p.mkdir(exist_ok=True)
    return p


def next_version(project_dir: Path) -> int:
    d = _dir(project_dir)
    nums = []
    for path in d.glob("v*.yaml"):
        m = re.match(r"^v(\d+)\.yaml$", path.name)
        if m:
            nums.append(int(m.group(1)))
    return (max(nums) + 1) if nums else 1


def save(project_dir: Path, storyboard: Storyboard, *, write_current: bool = True) -> Path:
    d = _dir(project_dir)
    n = storyboard.meta.version
    path = d / f"v{n}.yaml"
    payload = storyboard.model_dump(by_alias=True, exclude_none=True, mode="json")
    text = yaml.safe_dump(payload, sort_keys=False, allow_unicode=True)
    path.write_text(text, encoding="utf-8")
    if write_current:
        (d / "current.yaml").write_text(text, encoding="utf-8")
    return path


def load(project_dir: Path, *, version: int | str = "current") -> Storyboard | None:
    d = _dir(project_dir)
    if version == "current":
        path = d / "current.yaml"
    elif isinstance(version, int):
        path = d / f"v{version}.yaml"
    else:
        path = d / f"{version}.yaml"
    if not path.exists():
        return None
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return Storyboard.model_validate(data)
