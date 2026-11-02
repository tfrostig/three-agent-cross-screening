"""Typed agent interfaces."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Literal

from pydantic import BaseModel, ConfigDict, Field

if TYPE_CHECKING:
    from agents.references import ReferenceLibrary


class DesignManifest(BaseModel):
    """Scientific description of a frozen R analysis."""

    model_config = ConfigDict(extra="forbid", strict=True)
    script_file: Literal["analysis.R"]
    hypotheses_file: Literal["hypotheses.csv"]
    report_file: Literal["report.md"]
    test_summary: str = Field(min_length=1)
    multiplicity_summary: str = Field(min_length=1)
    assumptions: list[str]
    limitations: list[str]


class ToolResult(BaseModel):
    """Bounded result of a container execution or contract check."""

    status: Literal["ok", "failed"]
    stdout: str = ""
    stderr: str = ""
    error: str | None = None
    truncated: bool = False


@dataclass(frozen=True)
class SessionConfig:
    session_id: str
    m: int
    n: int
    criterion: str
    alpha: float
    model: str
    input_dir: Path
    workspace: Path
    audit_dir: Path
    project_root: Path
    sandbox: dict
    limits: dict
    openai: dict
    reference_pack: Path | None = None
    reference_digest: str | None = None


@dataclass
class AgentDependencies:
    config: SessionConfig
    runner: object
    r_executions: int = 0
    repairs: int = 0
    checked_hashes: dict[str, str] = field(default_factory=dict)
    references: ReferenceLibrary | None = None


ARTIFACT_NAMES = frozenset({"analysis.R", "hypotheses.csv", "report.md"})
