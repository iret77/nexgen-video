import nexgen_engine.core.modes as core_modes
from nexgen_engine.render import identity_anchor
from nexgen_engine.shotlist import schema


def test_identity_anchor_module_imports():
    assert identity_anchor is not None


def test_no_musicvideo_references():
    import inspect

    source = inspect.getsource(identity_anchor)
    assert "musicvideo" not in source


def test_exposes_public_api():
    assert hasattr(identity_anchor, "pick_identity_anchors")
    assert hasattr(identity_anchor, "is_anchor_for")
    assert hasattr(identity_anchor, "inherited_anchor_shots")
    assert hasattr(identity_anchor, "AnchorMap")


def _shot(shot_id: str, section: str, t: float, chars: list[str]) -> schema.Shot:
    return schema.Shot(
        id=shot_id,
        section=section,
        time_start=t,
        time_end=t + 2.0,
        duration_s=2.0,
        type=schema.ShotType.PERFORMANCE,
        description="d",
        visual_prompt="p",
        mood="m",
        character_refs=chars,
    )


def _shotlist(shots: list[schema.Shot]) -> schema.Shotlist:
    song = schema.Song(
        title="t",
        audio_path="a.wav",
        analysis_path="an.json",
        bpm=120.0,
        duration_s=100.0,
    )
    return schema.Shotlist(
        schema=schema.SCHEMA_VERSION,
        mode=core_modes.Mode.SECTION,
        project="proj",
        song=song,
        generated="2026-01-01",
        generator="test",
        shots=shots,
    )


def test_first_shot_per_section_character_is_anchor():
    sl = _shotlist([
        _shot("s001", "verse", 0.0, ["alex"]),
        _shot("s002", "verse", 2.0, ["alex"]),
        _shot("s003", "chorus", 4.0, ["alex"]),
    ])
    amap = identity_anchor.pick_identity_anchors(sl)

    # s001 is its own anchor for alex in verse.
    assert identity_anchor.is_anchor_for(amap, "s001", "alex")
    # s002 inherits s001 (same section, same character).
    assert identity_anchor.inherited_anchor_shots(amap, "s002") == ["s001"]
    assert not identity_anchor.is_anchor_for(amap, "s002", "alex")
    # Section change resets — s003 becomes its own anchor again.
    assert identity_anchor.is_anchor_for(amap, "s003", "alex")
    assert identity_anchor.inherited_anchor_shots(amap, "s003") == []
