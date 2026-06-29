"""Single-Frame-Crop aus einem Bible-Master.

Schwester von `pan_pair`: dort wandert die Crop-Box vom Master-Start
zum Master-End fuer Pan/Tilt. Hier bleibt sie statisch — fuer
Establishing-Shots mit gleichem Framing, die der Bible-Master schon
in voller Wide-Geometrie zeigt.

Wann nutzen (statt eines neuen Image-Renders):
- Reine Location-Establishing-Shots ohne Subject im Vordergrund.
- Bible hat einen Wide-Master, der die Welt in Ziel-Aspect oder
  breiter zeigt.
- Stil-Konsistenz zwischen Frames ist kritisch (Hanna-Barbera-Flat,
  Anime-Look). Crop = pixel-identische Stil-Vererbung vom Master.
- Schutz gegen Modell-Halluzination: ein neuer Image-Render kann fuer
  einen leeren Establishing-Shot voellig vom flachen Bible-Master
  abweichen. Crop ist dagegen immun — was im Master ist, ist auch im
  Frame.

Wann NICHT nutzen:
- Subject ist Hauptmotiv (Charakter im Vordergrund).
- Shot zeigt eine Zone der Location, die im Master nicht etabliert
  ist (Detail-Shot eines Innenraums, der im Wide nicht sichtbar war).
- Brief.aspect ist mehr als 30% breiter als der Master — dann wuerden
  zu viele Pixel hochskaliert.

Reine Geometrie (`plan_crop`) haengt nur von der stdlib ab. Der
Pixel-Schnitt (`generate_crop`) laedt Pillow erst beim Aufruf, damit
das Geometrie-Modul ohne Bild-IO-Dependency importierbar bleibt.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal


Anchor = Literal["center", "left", "right", "top", "bottom"]


@dataclass(frozen=True)
class CropPlan:
    master_size: tuple[int, int]
    target_size: tuple[int, int]
    box: tuple[int, int, int, int]   # (left, top, right, bottom)
    anchor: Anchor


def _parse_aspect(s: str) -> float:
    if ":" not in s:
        raise ValueError(f"Aspect muss 'W:H' sein, war {s!r}")
    w_str, h_str = s.split(":", 1)
    w, h = float(w_str), float(h_str)
    if w <= 0 or h <= 0:
        raise ValueError(f"Aspect-Werte muessen > 0 sein: {s!r}")
    return w / h


def plan_crop(
    master_size: tuple[int, int],
    target_aspect: str,
    anchor: Anchor = "center",
) -> CropPlan:
    """Berechnet die statische Crop-Box im Ziel-Aspect.

    Strategie: groesste Box, die in den Master passt UND das Ziel-
    Aspect hat. Position richtet sich nach `anchor`.
    """
    mw, mh = master_size
    if mw <= 0 or mh <= 0:
        raise ValueError(f"Master-Size invalid: {master_size}")
    aspect = _parse_aspect(target_aspect)
    master_aspect = mw / mh

    if abs(master_aspect - aspect) < 1e-3:
        # Master hat schon das Ziel-Aspect — full take.
        return CropPlan(
            master_size=(mw, mh),
            target_size=(mw, mh),
            box=(0, 0, mw, mh),
            anchor=anchor,
        )

    if master_aspect > aspect:
        # Master ist breiter — Hoehe voll, Breite anpassen.
        target_h = mh
        target_w = int(round(target_h * aspect))
        delta = mw - target_w
        if anchor == "left":
            left = 0
        elif anchor == "right":
            left = delta
        else:  # center / top / bottom (top/bottom irrelevant horizontal)
            left = delta // 2
        return CropPlan(
            master_size=(mw, mh),
            target_size=(target_w, target_h),
            box=(left, 0, left + target_w, target_h),
            anchor=anchor,
        )

    # Master ist schmaler — Breite voll, Hoehe anpassen.
    target_w = mw
    target_h = int(round(target_w / aspect))
    delta = mh - target_h
    if anchor == "top":
        top = 0
    elif anchor == "bottom":
        top = delta
    else:
        top = delta // 2
    return CropPlan(
        master_size=(mw, mh),
        target_size=(target_w, target_h),
        box=(0, top, target_w, top + target_h),
        anchor=anchor,
    )


def generate_crop(
    master_path: Path,
    dest: Path,
    *,
    target_aspect: str,
    anchor: Anchor = "center",
) -> CropPlan:
    """Liest Master, schreibt deterministischen Crop nach dest."""
    from PIL import Image
    if not master_path.exists():
        raise FileNotFoundError(f"Master fehlt: {master_path}")
    img = Image.open(master_path)
    plan = plan_crop(img.size, target_aspect=target_aspect, anchor=anchor)
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.crop(plan.box).save(dest, format="PNG")
    return plan
