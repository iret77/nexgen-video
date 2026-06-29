"""Identity-Anchor-Auswahl für Multi-Shot-Character-Konsistenz.

Pattern (Recherche Mai 2026, OpsMatters "Anchor-and-Extend",
WaveSpeed Character-Consistency): der **erste Char-Shot pro Section**
mit einem bestimmten Character wird als Identity-Anchor markiert. Sein
generierter Frame wird bei allen folgenden Shots derselben Section mit
demselben Character oben auf den Ref-Stack gelegt — das stabilisiert
Gesichts-Proportionen, Outfit-Details, charakteristische Merkmale über
die ganze Section.

Verantwortlich: Frame-Phase nutzt `pick_identity_anchors()`, bevor sie
pro Shot den Reference-Planner ruft. Der Anchor-Pfad wird zusätzlich
auf die Refs gepackt (vor dem Cap-Cut) und im Manifest als
`identity_anchor_shot` notiert.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from nexgen_engine.shotlist.schema import Shot, Shotlist


@dataclass
class AnchorMap:
    """Mapping shot_id → (anchor_shot_id, character_id) für jeden Shot,
    der einen impliziten Identity-Anchor erbt.

    Shots, die SELBST der Anchor sind, tauchen in der Map auf mit
    `anchor_shot_id == shot.id`. Folge-Shots haben dann einen früheren
    Anchor referenziert.
    """
    # shot_id → list of (anchor_shot_id, character_id)
    anchors_per_shot: dict[str, list[tuple[str, str]]] = field(default_factory=dict)

    def for_shot(self, shot_id: str) -> list[tuple[str, str]]:
        return self.anchors_per_shot.get(shot_id, [])


def pick_identity_anchors(shotlist: Shotlist) -> AnchorMap:
    """Pro (Section, Character) den ersten Shot als Anchor markieren.

    Folge-Shots derselben Section mit demselben Character bekommen den
    Anchor-Shot referenziert. Section-Wechsel resetiert die Anchor-Map —
    Identitäts-Drift über Sections hinweg ist erwünscht (das ist ja oft
    ein bewusster Cut).

    Returns:
        AnchorMap mit Mapping pro Shot.
    """
    sorted_shots = sorted(shotlist.shots, key=lambda s: s.time_start)
    # Pro Section: Character-ID → Anchor-Shot-ID
    anchors_in_section: dict[str | None, dict[str, str]] = {}
    result = AnchorMap()

    for shot in sorted_shots:
        sec = shot.section
        if sec not in anchors_in_section:
            anchors_in_section[sec] = {}
        char_map = anchors_in_section[sec]

        entries: list[tuple[str, str]] = []
        for cid in shot.character_refs:
            if cid in char_map:
                # Existierender Anchor → referenzieren
                entries.append((char_map[cid], cid))
            else:
                # Dieser Shot wird selbst Anchor für diesen Char in dieser Section
                char_map[cid] = shot.id
                entries.append((shot.id, cid))
        if entries:
            result.anchors_per_shot[shot.id] = entries

    return result


def is_anchor_for(map_: AnchorMap, shot_id: str, character_id: str) -> bool:
    """True, wenn `shot_id` selbst der Anchor für `character_id` ist
    (also kein früherer Anchor referenziert wird).
    """
    entries = map_.for_shot(shot_id)
    for anchor_shot_id, cid in entries:
        if cid == character_id and anchor_shot_id == shot_id:
            return True
    return False


def inherited_anchor_shots(map_: AnchorMap, shot_id: str) -> list[str]:
    """Liste von Anchor-Shot-IDs, die `shot_id` als impliziten Ref erbt
    (also alle, wo der Anchor ein FRÜHERER Shot ist, nicht dieser selbst).
    """
    entries = map_.for_shot(shot_id)
    return [
        anchor_shot_id
        for anchor_shot_id, _cid in entries
        if anchor_shot_id != shot_id
    ]
