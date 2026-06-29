from nexgen_engine.storyboard import schema


def test_storyboard_module_imports():
    assert schema is not None


def test_storyboard_schema_version():
    assert schema.SCHEMA_VERSION == "storyboard/v1"


def test_structural_anchor_replaces_refrain_anchor():
    assert hasattr(schema.StepFunction, "STRUCTURAL_ANCHOR")
    assert schema.StepFunction.STRUCTURAL_ANCHOR.value == "structural-anchor"
    assert not hasattr(schema.StepFunction, "REFRAIN_ANCHOR")


def test_no_musicvideo_references():
    import inspect

    source = inspect.getsource(schema)
    assert "musicvideo" not in source


def test_storyboard_round_trip():
    step = schema.Step(
        id="verse1.01",
        function=schema.StepFunction.STRUCTURAL_ANCHOR,
        subject="Alex steht im Schultor",
        camera="low-angle ~1.5 m",
    )
    section = schema.Section(id="verse1", steps=[step])
    sb = schema.Storyboard(
        meta=schema.StoryboardMeta(
            project="proj",
            version=1,
            generated="2026-01-01",
        ),
        sections=[section],
    )
    dumped = sb.model_dump(by_alias=True, exclude_none=True, mode="json")
    again = schema.Storyboard.model_validate(dumped)
    assert again.sections[0].steps[0].id == "verse1.01"
    assert again.sections[0].steps[0].function is schema.StepFunction.STRUCTURAL_ANCHOR
    assert again.schema_ == "storyboard/v1"
