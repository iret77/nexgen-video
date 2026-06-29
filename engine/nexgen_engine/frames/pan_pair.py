"""Pan-/Trucking-Pair-Generator: Start + End-Frame aus einem groesseren
Master via deterministischem Crop.

Hintergrund: Bei pan/trucking braucht das Video-Modell sowohl Start als
auch End. Wenn beide separat per Image-Generation entstehen, driften
Welt und Objekte zwangslaeufig — Start hat 3 Gebaeude, End nur 2, Modell
muss das morphen, Slop.

Sauberer Pfad: ein Master-Frame generieren, der die Welt ueber den
ganzen Bewegungs-Bereich zeigt. Start/End sind dann deterministische
Crops aus dem Master, mit konstantem Aspect-Ratio des Render-Ziels.
100% Welt-Konsistenz, kein Modell-Drift.

Anwendungsfaelle:
- Horizontal-Pan (links→rechts oder umgekehrt)
- Vertikal-Tilt (oben→unten oder umgekehrt)
- Lateraler Track (parallel zum Subject)

NICHT geeignet:
- Push/Pull/Zoom (Welt-Skala aendert sich, Crop reicht nicht)
- Orbit/Crane (Perspektivwechsel)
- Rotations (Welt-Ansicht aendert sich)

Reine Geometrie (`plan_pan_pair`) haengt nur von der stdlib ab. Der
Pixel-Schnitt (`generate_pan_pair`) laedt Pillow erst beim Aufruf, damit
das Geometrie-Modul ohne Bild-IO-Dependency importierbar bleibt.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal


Direction = Literal["right", "left", "up", "down"]


@dataclass(frozen=True)
class PanPairPlan:
    """Crop-Geometrie fuer das Frame-Paar."""
    master_size: tuple[int, int]
    target_size: tuple[int, int]
    start_box: tuple[int, int, int, int]   # (left, top, right, bottom)
    end_box: tuple[int, int, int, int]
    direction: Direction
    travel_px: int


def _parse_aspect(s: str) -> float:
    if ":" not in s:
        raise ValueError(f"Aspect muss 'W:H' sein, war {s!r}")
    w_str, h_str = s.split(":", 1)
    w, h = float(w_str), float(h_str)
    if w <= 0 or h <= 0:
        raise ValueError(f"Aspect-Werte muessen > 0 sein: {s!r}")
    return w / h


def plan_pan_pair(
    master_size: tuple[int, int],
    target_aspect: str,
    direction: Direction,
    *,
    travel_pct: float = 80.0,
) -> PanPairPlan:
    """Berechnet die zwei Crop-Boxen ohne tatsaechlich zu schneiden.

    Args:
        master_size: (width, height) des Master-Bildes.
        target_aspect: 'W:H' fuer Start/End-Frame (Render-Aspect).
        direction: 'right'/'left' fuer horizontalen Pan, 'up'/'down' fuer Tilt.
        travel_pct: Wie viel Prozent der Differenz zwischen Master und
            Target-Crop genutzt werden. 100% = Start am einen Rand,
            End am anderen Rand (maximaler Pan). 80% = etwas Reserve
            an beiden Raendern (Default — Video-Modell muss nicht
            auf den letzten Pixel synchronisieren).

    Returns:
        PanPairPlan mit beiden Crop-Boxen.
    """
    if not 0.0 < travel_pct <= 100.0:
        raise ValueError(f"travel_pct muss in (0, 100] sein, war {travel_pct}")
    mw, mh = master_size
    if mw <= 0 or mh <= 0:
        raise ValueError(f"Master-Size invalid: {master_size}")
    aspect = _parse_aspect(target_aspect)
    # Target-Box: maximal moegliche Aufloesung mit Ziel-Aspect, die
    # in den Master passt — abhaengig von Bewegungs-Richtung.
    if direction in ("right", "left"):
        # Horizontal: Target hat volle Master-Hoehe (oder darunter, je
        # nach Aspect). Crop-Box bewegt sich horizontal.
        target_h = mh
        target_w = int(round(target_h * aspect))
        if target_w > mw:
            # Master ist zu wenig breit fuer den geforderten Pan-Bereich
            raise ValueError(
                f"Master {mw}x{mh} ist zu schmal fuer Pan im Aspect {target_aspect}. "
                f"Mindestbreite: Target-Breite + Pan-Travel. "
                f"Hier waere Target-Breite {target_w}px > Master {mw}px."
            )
        max_travel = mw - target_w
        travel = int(round(max_travel * travel_pct / 100.0))
        if direction == "right":
            start_left = (max_travel - travel) // 2
            end_left = start_left + travel
        else:  # left
            end_left = (max_travel - travel) // 2
            start_left = end_left + travel
        start_box = (start_left, 0, start_left + target_w, target_h)
        end_box = (end_left, 0, end_left + target_w, target_h)
        return PanPairPlan(
            master_size=(mw, mh),
            target_size=(target_w, target_h),
            start_box=start_box,
            end_box=end_box,
            direction=direction,
            travel_px=travel,
        )
    # Vertikal: Target hat volle Master-Breite
    target_w = mw
    target_h = int(round(target_w / aspect))
    if target_h > mh:
        raise ValueError(
            f"Master {mw}x{mh} ist zu kurz fuer Tilt im Aspect {target_aspect}. "
            f"Target-Hoehe {target_h}px > Master {mh}px."
        )
    max_travel = mh - target_h
    travel = int(round(max_travel * travel_pct / 100.0))
    if direction == "down":
        start_top = (max_travel - travel) // 2
        end_top = start_top + travel
    else:  # up
        end_top = (max_travel - travel) // 2
        start_top = end_top + travel
    start_box = (0, start_top, target_w, start_top + target_h)
    end_box = (0, end_top, target_w, end_top + target_h)
    return PanPairPlan(
        master_size=(mw, mh),
        target_size=(target_w, target_h),
        start_box=start_box,
        end_box=end_box,
        direction=direction,
        travel_px=travel,
    )


def generate_pan_pair(
    master_path: Path,
    start_dest: Path,
    end_dest: Path,
    *,
    target_aspect: str,
    direction: Direction,
    travel_pct: float = 80.0,
) -> PanPairPlan:
    """Liest Master, schreibt Start und End als deterministische Crops.

    Returns die Plan-Geometrie, damit der Aufrufer sie ins Manifest
    schreiben oder loggen kann.
    """
    from PIL import Image
    if not master_path.exists():
        raise FileNotFoundError(f"Master fehlt: {master_path}")
    img = Image.open(master_path)
    plan = plan_pan_pair(
        master_size=img.size,
        target_aspect=target_aspect,
        direction=direction,
        travel_pct=travel_pct,
    )
    start_dest.parent.mkdir(parents=True, exist_ok=True)
    end_dest.parent.mkdir(parents=True, exist_ok=True)
    img.crop(plan.start_box).save(start_dest)
    img.crop(plan.end_box).save(end_dest)
    return plan
