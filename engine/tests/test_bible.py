from pathlib import Path

from nexgen_engine import mcp_server
from nexgen_engine.bible import schema as bible_schema
from nexgen_engine.core import layout as layout_mod
from nexgen_engine.core.modes import Mode


def test_bible_schema_version():
    assert bible_schema.BIBLE_SCHEMA_VERSION == "bible/v5"


def test_bible_absent_is_none(tmp_path: Path):
    data_root = layout_mod.init_project(tmp_path / "p", "demo", mode=Mode.BEAT)
    assert bible_schema.load(data_root) is None
    assert mcp_server.bible(str(data_root)) is None
