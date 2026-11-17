"""Source-only fixtures for current agent and provider tests."""

from pathlib import Path

from pydantic_ai.messages import ModelResponse, ToolCallPart
from pydantic_ai.models.function import FunctionModel

from agents.document_state import fixture_report
from agents.models import SessionConfig, ToolResult


def config_for(tmp_path):
    """Create independent local session directories without observations or credentials."""
    for name in ("work", "audit", "input"):
        (tmp_path / name).mkdir(parents=True)
    return SessionConfig("opaque", 20, 8, "FWER", .05 / 3, "gpt-6.1-sol",
                         tmp_path / "input", tmp_path / "work", tmp_path / "audit", Path.cwd(), {},
                         {"max_r_executions": 12, "max_contract_repairs": 2, "tool_calls_limit": 32},
                         {"request_limit": 16, "max_output_tokens": 8192})


class FakeRunner:
    """Capture exploration and provide a data-free inspection response."""

    def __init__(self):
        """Start a session-owned call log."""
        self.modes = []

    def execute(self, mode, code=""):
        """Record a source-only exploration request."""
        self.modes.append(mode)
        return ToolResult(status="ok", stdout="fixture")

    def inspect(self):
        """Return an empty declared family without applying an analysis."""
        self.modes.append("inspect")
        return {"status": "ok", "payload": []}


def seed_artifacts(workspace):
    """Write formatting-valid fixtures for model-contract tests."""
    (workspace / "analysis.R").write_text("fixture")
    (workspace / "report.md").write_text(fixture_report())


def submission_model():
    """Return the typed final submission without external model requests."""
    def respond(messages, info):
        return ModelResponse(parts=[ToolCallPart("finalize_design",
            {"script_file": "analysis.R", "report_file": "report.md"}, "fixture-final")])
    return FunctionModel(respond)
