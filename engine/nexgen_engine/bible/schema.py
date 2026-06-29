"""Bible v4: Characters + Ensembles + Props + Locations + Look.

Kritische Konsistenzreferenz. Jede Entity (Character, Ensemble, Prop,
Location), die in der Shotlist referenziert wird, MUSS mindestens einen
Bild-Anker haben — entweder unter `reference_images` (User-Upload,
kuratiert aus import/) oder unter `sheets` (durch sheet-CLI generiert).

Schema-Historie:
- v2 → v3: `LookGuide.style`, `Character.sheets`, `Ensemble`-Klasse,
  Anker-Pflicht.
- v3 → v4: `Location.sheets` und `Location.view_purpose` (Multi-View
  pro Location, abgeleitet aus dem Storyboard-Bedarf), `Prop.sheets`
  für Variants (offen/geschlossen, sauber/dreckig).
- v4 → v5: `Location.zones` (Welt-Bereiche mit clean/dirty/undefined-
  Status für Zone-Tracking) und `Location.proportion_anchor_shot`
  (verbindlicher Skala-Anker pro Location).
"""

from __future__ import annotations

from enum import Enum
from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

BIBLE_SCHEMA_VERSION = "bible/v5"


class ZoneStatus(str, Enum):
    """Status eines Welt-Bereichs einer Location.

    Hintergrund: Wenn ein Image-/Video-Modell einen Bereich der Location
    zeigt, der nicht durch ein Bible-Asset kanonisiert ist, erfindet
    es ihn frei (Texturen, Architektur, Beleuchtung). Sobald ein anderer
    Shot denselben Bereich aus einer anderen Perspektive zeigt, bricht
    die Konsistenz. Zone-Tracking macht diese Bereiche explizit:

    - `clean`: durch ein Bible-Asset (sheet, reference_image) kanonisch
      definiert — beliebig oft wiederverwendbar.
    - `dirty`: bereits durch einen Render frei erfunden — nie wieder zeigen,
      oder als Reference des etablierenden Shots reinziehen.
    - `undefined`: noch nicht etabliert — einmalig nutzbar, danach
      `dirty` markieren (oder Bible-Asset nachziehen).
    - `safe`: systematisch konsistent ohne Architektur-Details (SKY,
      GROUND/SAND/SNOW, MONOCHROME-BG) — risk-frei wiederverwendbar.
    """
    CLEAN = "clean"
    DIRTY = "dirty"
    UNDEFINED = "undefined"
    SAFE = "safe"


class Zone(BaseModel):
    """Ein benannter Welt-Bereich einer Location.

    Granularität: ein Bereich, der dramaturgisch separat adressierbar ist
    — Gebäudefassade, Hauptwand, Decke, linker Eingang, Aussichtspunkt
    Wüste. Nicht so fein, dass für jedes Möbelstück eine eigene Zone
    entsteht. Naming-Konvention: kurze IDs (`A`, `B`, `left_window`,
    `back_wall`), keine Pflicht zum schema-festen Vokabular — Granularität
    und Naming pro Projekt.
    """
    model_config = ConfigDict(extra="forbid")

    id: str
    description: str
    status: ZoneStatus
    bible_assets: list[str] = Field(default_factory=list)
    """Pfade zu Bible-Sheets / reference_images, die diese Zone
    kanonisieren. Pflicht für `clean`. Leer für `dirty`/`undefined`/`safe`."""
    established_by_shot: str | None = None
    """Bei `dirty`: ID des Shots, der die Zone frei generiert hat. Sein
    approved Frame kann als Reference für Folgeshots dieser Zone dienen."""

    @field_validator("id")
    @classmethod
    def _id_slug(cls, v: str) -> str:
        if not v:
            raise ValueError("zone.id darf nicht leer sein")
        # Zonen-IDs dürfen kurze Buchstaben sein (A, B, C) oder snake_case.
        return v


class _IdBase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    visual_prompt: str
    """Kompakter Beschreibungs-Satz, der in Shot-Prompts eingesetzt wird.
    Beispiel Character: 'Lehrerin Ende 30, kurze braune Haare, runde Brille,
    weicher Strickpullover, Notizbuch in der Hand.'
    """
    attributes: dict[str, str] = Field(default_factory=dict)
    """Strukturierte Konsistenz-Attribute. Keys frei (z.B. age, hair, eyes,
    outfit, accessories). Werte kurze Strings."""

    hard_recognition_trait: str = ""
    """Ein **konkretes, hartes Erkennungs-Merkmal**, das in jedem Shot-Prompt
    als Identity-Lock dient. Bei Characters/Ensembles: silberner Ohrring links,
    Tattoo am rechten Handgelenk, charakteristische Brille mit gelbem Rahmen,
    Mütze in Rot. Bei Locations/Props: erkennbares Einzeldetail
    (zerkratzte Tür, Lampe mit grünem Schirm). Frame-Builder hängt das in
    den Identity-Lock-Block jedes Prompts. Empfohlen, aber nicht Pflicht —
    bei Live-Action ohne stilisierte Marker leer lassen."""

    @field_validator("id")
    @classmethod
    def _id_slug(cls, v: str) -> str:
        if not v or not v.replace("_", "").isalnum():
            raise ValueError(f"id {v!r} muss alnum/underscore sein")
        return v

    @field_validator("visual_prompt")
    @classmethod
    def _visual_prompt_nonempty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("visual_prompt darf nicht leer sein")
        return v


class Character(_IdBase):
    reference_images: list[str] = Field(
        default_factory=list,
        description="User-Upload-Refs, kuratiert aus import/ → bible/refs/<id>/. "
                    "Pfade relativ zu projects/<name>/.",
    )
    sheets: dict[str, str] = Field(
        default_factory=dict,
        description="Generierte Character-Sheets vom sheet-agent. Keys: "
                    "'front' | 'side' | 'back' | 'expression_<tag>'. "
                    "Werte sind Pfade relativ zu projects/<name>/.",
    )

    @field_validator("sheets")
    @classmethod
    def _sheet_keys_known(cls, v: dict[str, str]) -> dict[str, str]:
        for key in v:
            if key in {"front", "side", "back"}:
                continue
            if key.startswith("expression_"):
                continue
            raise ValueError(
                f"sheet-key {key!r} unbekannt. Erlaubt: front/side/back/expression_<tag>"
            )
        return v

    def has_anchor(self) -> bool:
        return bool(self.reference_images) or bool(self.sheets)


class Ensemble(_IdBase):
    """Gruppe von Personen mit gemeinsamem Auftritt — Schulklasse, Band,
    Crowd. Statt n Pseudo-Characters anzulegen, wird die Gruppe als eine
    Entity beschrieben mit member_count und Diversity-Hinweis.
    """
    member_count: int = Field(gt=0)
    members_description: str = ""
    """Diversity-Hinweis: 'gemischtes Geschlecht 8-14 Jahre, verschiedene
    Hauttöne, alle in legerer Schulkleidung'. Wird in Shot-Prompts genutzt."""
    reference_images: list[str] = Field(default_factory=list)
    sheets: dict[str, str] = Field(default_factory=dict)
    """Bei Ensembles üblich: 'group_wide.png', 'group_close.png' usw.
    Verwende `expression_<tag>` für Stimmungs-Varianten der Gruppe."""

    @field_validator("sheets")
    @classmethod
    def _sheet_keys_ensemble(cls, v: dict[str, str]) -> dict[str, str]:
        # Bei Ensembles sind die Sheet-Keys frei, aber `expression_*` bleibt valide
        return v

    def has_anchor(self) -> bool:
        return bool(self.reference_images) or bool(self.sheets)


class Prop(_IdBase):
    reference_images: list[str] = Field(default_factory=list)
    """Requisit (Instrument, Kleidungsstück, Fahrzeug, Objekt)."""
    sheets: dict[str, str] = Field(default_factory=dict)
    """Optionale generierte Prop-Sheets. Free-form Keys, z.B. `closed`,
    `open`, `worn`, `clean`, `dirty`. Werte sind Pfade relativ zu
    `projects/<name>/`."""

    def has_anchor(self) -> bool:
        return bool(self.reference_images) or bool(self.sheets)


class Location(_IdBase):
    reference_images: list[str] = Field(default_factory=list)
    """Optionale User-Upload-Refs der Location, kuratiert in
    `bible/refs/<id>/`. Können null sein — dann muss `sheets` nicht-leer
    sein."""

    sheets: dict[str, str] = Field(default_factory=dict)
    """Generierte Location-Sheets. Free-form Keys, vom Storyboard-Bedarf
    abgeleitet. Beispiele:

    - `wide`, `alt_angle`, `detail` — Standard-Trio
    - `entrance`, `back_gate`, `corridor` — bestimmte Eingänge / Wege
    - `wide.morning`, `wide.afternoon`, `wide.night` — Lighting-Variants
    - `detail.chalkboard`, `detail.bench` — Mikro-Continuity-Anker

    Werte sind Pfade relativ zu `projects/<name>/`."""

    view_purpose: dict[str, str] = Field(default_factory=dict)
    """Optionale Beschreibung pro Sheet-Key — was zeigt diese View, in
    welcher Story-Funktion. Frame-Builder nutzt das für den
    'Image N: <view> – <purpose>'-Hint im Multi-Ref-Prompt.

    Keys müssen mit `sheets` (oder `reference_images`-Index) übereinstimmen.
    """

    floorplan: str = ""
    """DEPRECATED in v0.5 — empirische Tests (Mai 2026) zeigten, dass
    Image-Modelle Floorplans als Geometrie-Anker nicht zuverlässig
    interpretieren. Feld bleibt aus Backward-Kompatibilität. Verwende
    stattdessen `scene3d` (siehe unten)."""

    zones: list[Zone] = Field(default_factory=list)
    """Zone-Inventur dieser Location (siehe `Zone`-Klasse). Treatment- und
    Storyboard-Phase pflegen das aktiv; Frame-Phase liest es zum Sanity-
    Check `DIRTY_ZONE_VISIBLE` und `ZONE_UNCOVERED`. Leer = kein Zone-
    Tracking für diese Location (Legacy / einfache Projekte).
    """

    proportion_anchor_shot: str | None = None
    """Optional: ID eines approved Shots dieser Location, der die
    Figur-zu-Set-Skala verbindlich festlegt. Reference-Planner injiziert
    den approved Start-Frame dieses Shots als ERSTE Reference in jeden
    weiteren Shot derselben Location — verhindert Proportions-Drift
    (Figur in Shot A so groß wie Tafel, in Shot B so groß wie Stuhl).
    Wenn None: kein Skala-Anker, Reference-Planner ranks unverändert.
    """

    scene3d: dict[str, str] = Field(default_factory=dict)
    """Optional: Metadaten zur Scene3D-Generation (Marble + Re-Style)
    für Multi-POV-Locations. Free-form Keys, typisch:

    - `panorama`:        Pfad zum Marble-Panorama (Clay-Stil)
    - `mesh`:            Pfad zum GLB-Kollider-Mesh
    - `thumbnail`:       Pfad zum Marble-Thumbnail
    - `splat_500k`:      Pfad zum 500k-Auflösungs-Splat (oder andere)
    - `clay_wide`:       Pfad zum stil-neutralisierten Wide (Pre-Pass)
    - `marble_world_id`: World-ID aus der Marble-API (für Reproduktion)
    - `marble_url`:      Web-Viewer-Link der Marble-Welt

    Die finalen Bible-Sheets nach Re-Style landen in `sheets` wie bei
    klassisch generierten Sheets — `scene3d` enthält nur die Build-
    Artefakte / Reproduzierbarkeits-Metadaten. CLI:
    `python -m musicvideo.bible.scene3d`.
    """

    def has_anchor(self) -> bool:
        return bool(self.reference_images) or bool(self.sheets)


class LookGuide(BaseModel):
    model_config = ConfigDict(extra="forbid")

    style: str = ""
    """Hauptstil-Vokabular (Pflicht wenn brief.visual_medium != live_action_realistic).
    Wird vom bible-agent aus brief.visual_medium_notes vorgefüllt.
    Beispiel: '2D Anime im Stil von Studio Ghibli / Makoto Shinkai —
    weiche Lichtstimmung, detaillierte Hintergründe, cel-shaded figures'."""
    palette: str = ""  # z.B. "warm desaturated, amber/teal"
    lighting: str = ""  # "low-key, single key light"
    lens: str = ""  # "35mm, shallow depth of field"
    film_stock: str = ""  # "Kodak Portra 400 inspired" / "digital"
    grain: str = ""  # "none" | "light" | "heavy"
    motion_style: str = ""  # "static, occasional slow dolly"
    additional: str = ""  # Freitext für alles Weitere
    lighting_anchor: str = ""
    """Optionaler Pfad zu einem einzelnen Anchor-Frame, der die
    Gesamt-Lichtsetzung des Projekts festhält (relativ zu
    `projects/<name>/`, z.B. `production_design/lighting_anchor.png`).
    Wird in Production Design generiert und in der Frame-Phase als
    Stil-Reference an Image-Modelle übergeben, damit alle Frames
    dieselbe Color-Grade / Lichtstimmung erben."""


class Bible(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_: str = Field(alias="schema", default=BIBLE_SCHEMA_VERSION)
    project: str
    generated: str
    generator: str
    look: LookGuide = Field(default_factory=LookGuide)
    characters: list[Character] = Field(default_factory=list)
    ensembles: list[Ensemble] = Field(default_factory=list)
    props: list[Prop] = Field(default_factory=list)
    locations: list[Location] = Field(default_factory=list)
    notes: str | None = None

    @field_validator("schema_")
    @classmethod
    def _schema_const(cls, v: str) -> str:
        # v4 wird tolerant gelesen — neu hinzugekommene Felder
        # (Location.zones, Location.proportion_anchor_shot) sind optional.
        # v4-Bibles laden also weiter; beim nächsten Save schreibt der
        # Validator v5 hin.
        if v not in {BIBLE_SCHEMA_VERSION, "bible/v4"}:
            raise ValueError(
                f"schema {v!r} unbekannt. Erlaubt: {BIBLE_SCHEMA_VERSION}, bible/v4 (legacy)"
            )
        return v

    @model_validator(mode="after")
    def _ids_unique_globally(self) -> "Bible":
        all_ids = (
            [c.id for c in self.characters]
            + [e.id for e in self.ensembles]
            + [p.id for p in self.props]
            + [loc.id for loc in self.locations]
        )
        if len(set(all_ids)) != len(all_ids):
            raise ValueError(f"Bible-IDs müssen global eindeutig sein: {all_ids}")
        return self

    @model_validator(mode="after")
    def _every_visual_entity_has_anchor(self) -> "Bible":
        """Jede Entity, die im Bild auftaucht (Character, Ensemble, Location),
        braucht mindestens ein Bild — Upload-Ref oder generiertes Sheet.
        Ohne Anker driften alle Renders auseinander.

        Props sind weicher: viele Props sind text-beschreibbar. Aber ein
        Prop, der mehrfach im Video vorkommt und Konsistenz braucht,
        sollte einen Anker haben — Warnung, nicht Hard-Fail.
        """
        missing: list[str] = []
        for c in self.characters:
            if not c.has_anchor():
                missing.append(f"character {c.id!r}")
        for e in self.ensembles:
            if not e.has_anchor():
                missing.append(f"ensemble {e.id!r}")
        for loc in self.locations:
            if not loc.has_anchor():
                missing.append(f"location {loc.id!r}")
        if missing:
            raise ValueError(
                "Bible-Coverage: jede Person und jeder Schauplatz braucht "
                "mindestens einen Bild-Anker (reference_images oder sheets). "
                "Ohne Anker: " + ", ".join(missing)
            )
        return self

    def lookup_id(self, ref: str) -> Character | Ensemble | Prop | Location | None:
        for c in self.characters:
            if c.id == ref:
                return c
        for e in self.ensembles:
            if e.id == ref:
                return e
        for p in self.props:
            if p.id == ref:
                return p
        for loc in self.locations:
            if loc.id == ref:
                return loc
        return None


def load(project_dir: Path) -> Bible | None:
    """Lade bible.yaml falls vorhanden, sonst None."""
    path = project_dir / "bible" / "bible.yaml"
    if not path.exists():
        return None
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return Bible.model_validate(data)


def save(project_dir: Path, bible: Bible) -> Path:
    path = project_dir / "bible" / "bible.yaml"
    path.parent.mkdir(exist_ok=True)
    path.write_text(
        yaml.safe_dump(
            bible.model_dump(by_alias=True, exclude_none=True, mode="json"),
            sort_keys=False,
            allow_unicode=True,
        ),
        encoding="utf-8",
    )
    return path
