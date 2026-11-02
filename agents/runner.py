"""Delegate R execution to the trusted container wrapper."""

import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

from agents.models import SessionConfig, ToolResult


def clean_environment(project_root: Path, home: Path) -> dict[str, str]:
    """Construct an environment without API keys or inherited credentials."""
    allowed = {"PATH", "LANG", "TMPDIR", "R_HOME", "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE"}
    environment = {key: value for key, value in os.environ.items() if key in allowed}
    environment.update(HOME=str(home), CROSS_SCREENING_ROOT=str(project_root))
    return environment


def save_exploration_code(request_file: Path, code: str) -> None:
    """Save submitted R source outside the agent-visible workspace.

    Args:
        request_file: Controller-owned audit request path.
        code: Exact R source submitted through the exploration tool.
    """
    directory = request_file.parent / "exploration"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{request_file.stem}.R").write_bytes(code.encode("utf-8"))


class RRunner:
    """Execute only the fixed trusted wrapper with session-bound paths."""

    def __init__(self, config: SessionConfig):
        self.config = config
        self.calls = 0

    def execute(self, mode: str, code: str = "") -> ToolResult:
        """Run a container and return a bounded typed result."""
        self.calls += 1
        config = self.config
        config.audit_dir.mkdir(parents=True, exist_ok=True)
        request = {"mode": mode, "code": code, "input_dir": str(config.input_dir),
                   "workspace": str(config.workspace), "alpha": config.alpha,
                   "execution_seed": secrets.randbelow(2147483646) + 1,
                   "sandbox": config.sandbox}
        request_file = config.audit_dir / f"execution-{self.calls:03d}.json"
        output_file = config.audit_dir / f"execution-{self.calls:03d}-result.json"
        request_file.write_text(json.dumps(request), encoding="utf-8")
        if mode == "explore":
            save_exploration_code(request_file, code)
        command = ["Rscript", "--vanilla", str(config.project_root / "scripts/agent_tool.R"),
                   str(request_file), str(output_file)]
        with tempfile.TemporaryDirectory(prefix="agent-wrapper-") as home:
            result = subprocess.run(command, shell=False, capture_output=True, text=True,
                                    cwd=config.project_root, timeout=config.sandbox["timeout_seconds"] + 30,
                                    env=clean_environment(config.project_root, Path(home)))
        if not output_file.exists():
            return ToolResult(status="failed", error="R execution wrapper failed",
                              stderr=result.stderr[-4096:])
        raw = json.loads(output_file.read_text(encoding="utf-8"))
        fields = {name: raw[name] for name in ToolResult.model_fields if name in raw}
        return ToolResult.model_validate(fields)
