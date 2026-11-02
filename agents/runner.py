"""Bridge source-only R tools to the trusted Docker wrapper.

Every call records its request and seed, saves submitted exploration source,
and invokes only scripts/agent_tool.R under a credential-free environment.
The wrapper then stages allowlisted files into a fresh restricted container."""

import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

from agents.models import SessionConfig, ToolResult


def clean_environment(project_root: Path, home: Path) -> dict[str, str]:
    """Build the credential-free environment for the trusted R wrapper.

    Args:
        project_root: Host project root passed through CROSS_SCREENING_ROOT.
        home: Temporary wrapper home, replacing the user's inherited HOME.

    Returns:
        Explicit environment allowlist; OPENAI_API_KEY and other secrets are absent.
    """
    allowed = {"PATH", "LANG", "TMPDIR", "R_HOME", "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE"}
    environment = {key: value for key, value in os.environ.items() if key in allowed}
    environment.update(HOME=str(home), CROSS_SCREENING_ROOT=str(project_root))
    return environment


def save_exploration_code(request_file: Path, code: str) -> None:
    """Archive exact submitted R source before any container execution.

    Args:
        request_file: Controller-owned audit request path.
        code: Submitted exploration source, encoded as UTF-8 without alteration.

    Writes audit/exploration/<request-stem>.R, including calls that later fail.
    """
    directory = request_file.parent / "exploration"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{request_file.stem}.R").write_bytes(code.encode("utf-8"))


class RRunner:
    """Session-bound bridge to scripts/agent_tool.R and Docker execution.

    Attributes:
        config: Source-only SessionConfig.
        calls: Numbered audit sequence covering exploration and contract checks.

    Generated R never runs directly in this Python process or in a host R session.
    """

    def __init__(self, config: SessionConfig):
        """Bind wrapper paths and the audit sequence to one source session.

        Args:
            config: SessionConfig whose input/work/audit paths never change here.
        """
        self.config = config
        self.calls = 0

    def execute(self, mode: str, code: str = "") -> ToolResult:
        """Delegate one explore/check request to the trusted Docker wrapper.

        Args:
            mode: explore or check; target evaluation is controlled separately by R.
            code: R source for explore; ignored for artifact checking.

        Returns:
            Bounded ToolResult. Writes numbered request/result audits and records
            an independent execution seed; each call starts a fresh container.
        """
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
