from nexgen_engine.sanity.models import Finding, SanityReport


def test_empty_report_is_clean():
    assert SanityReport(project="p").is_clean is True


def test_report_partitions_by_level():
    r = SanityReport(
        project="p",
        findings=[
            Finding(level="error", code="E1", shot_id="s1", message="bad"),
            Finding(level="warn", code="W1", shot_id=None, message="meh"),
            Finding(level="info", code="I1", shot_id=None, message="fyi"),
        ],
    )
    assert len(r.errors) == 1
    assert len(r.warnings) == 1
    assert r.is_clean is False
