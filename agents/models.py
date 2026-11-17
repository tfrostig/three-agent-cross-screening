"""Typed source-only session configuration and tool execution results."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

from pydantic import BaseModel

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
    """
    config: SessionConfig
    runner: object
    r_executions: int = 0
    repairs: int = 0
    checked_hashes: dict[str, str] = field(default_factory=dict)
