"""Sanity-Audit-Datenmodelle: Finding + SanityReport.

Aus audit.py extrahiert, damit Submodule unter `sanity/checks/` Finding
importieren koennen, ohne den Audit-Orchestrator selbst laden zu muessen
(vermeidet zirkulaere Imports beim Submodul-Refactor v0.10).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

Level = Literal["info", "warn", "error"]


@dataclass
class Finding:
    level: Level
    code: str
    shot_id: str | None
    message: str


@dataclass
class SanityReport:
    project: str
    findings: list[Finding] = field(default_factory=list)

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.level == "error"]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.level == "warn"]

    @property
    def is_clean(self) -> bool:
        return not self.errors
