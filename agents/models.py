"""Typed host/session and artifact contracts.

DesignManifest is the strict model-visible output schema; its class description
is intentionally preserved. SessionConfig contains source paths but no truth.
See docs/agent-api.md for the complete tool and artifact field contracts."""

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
    """Immutable host-side configuration for one source session.

    Attributes:
        session_id: Opaque session identifier, with no sibling information.
        m: Measurement count.
        n: Observations per exposed/control arm.
        criterion: FWER or FDR.
        alpha: Already allocated target-family level; do not divide it again.
        model: Explicit provider model ID.
        input_dir: Directory containing this source's exposed/unexposed RDS files.
        workspace: Mutable source-only artifact and persistent-file directory.
        audit_dir: Controller-owned logs, outside agent-visible mounts.
        project_root: Trusted host code root; never mounted into agent containers.
        sandbox: Image, CPU, memory, and execution timeout configuration.
        limits: R-call, tool-call, repair, and output budgets.
        openai: Provider request, retry, timeout, and output-token limits.
        reference_pack: Optional trusted curated-library path.
        reference_digest: Optional expected catalog SHA-256.
    """
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
    """Mutable state allocated afresh for each PydanticAI session.

    Attributes:
        config: Immutable source-session configuration.
        runner: Session-bound RRunner.
        r_executions: Exploration-call budget consumed so far.
        repairs: Failed contract/finalization checks counted against the repair cap.
        checked_hashes: Artifact digests from the latest successful check; cleared
            after a tool write or failed check.
        references: Verified session-local methodological reference snapshot.
    """
    config: SessionConfig
    runner: object
    r_executions: int = 0
    repairs: int = 0
    checked_hashes: dict[str, str] = field(default_factory=dict)
    references: ReferenceLibrary | None = None


ARTIFACT_NAMES = frozenset({"analysis.R", "hypotheses.csv", "report.md"})
