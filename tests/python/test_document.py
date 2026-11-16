"""Document protocol invariants without provider calls or credentials."""

import ast
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

from agents.document import Submission, hashes, task
from agents.document_state import fixture_report
from agents.document_preview import export

ROOT = Path(__file__).resolve().parents[2]


def test_scientific_prompt_is_locked():
    """Detect edits to the approved PDF text, including the BY instruction."""
    prompt = ROOT / "prompts/document-20261111.txt"
    record = json.loads(prompt.with_suffix(".provenance.json").read_text())
    assert hashlib.sha256(prompt.read_bytes()).hexdigest() == record["prompt_sha256"]
    assert "Do not use BY\n" not in prompt.read_text()
    assert "Do not use BY under any circumstances" in prompt.read_text()


def test_actual_model_interfaces(tmp_path):
    """Capture actual tool schemas and ensure no legacy instructions are injected."""
    destination = tmp_path / "preview.md"
    export(ROOT, destination)
    captured = json.loads(destination.read_text().split("```json\n")[1].split("\n```")[0])
    assert captured["instructions"] == (ROOT / "prompts/document-20261111.txt").read_text()
    assert {t["name"] for t in captured["tools"]} == {"run_r", "write_artifact_file"}
    assert captured["output"][0]["name"] == "finalize_design"
    assert set(Submission.model_fields) == {"script_file", "report_file"}


def test_metadata_and_artifact_boundaries(tmp_path):
    """Metadata contains only supplied dimensions and objective; links are rejected."""
    assert task(SimpleNamespace(m=20,n=30,criterion="FWER",alpha=.05/3)).splitlines() == [
        "Number of measurements: 20", "Exposed sample size: 30", "Unexposed sample size: 30",
        "Error criterion: FWER", "Family level: 0.016666666666666666"]
    (tmp_path / "analysis.R").write_text("x <- 1")
    (tmp_path / "report.md").symlink_to(tmp_path / "analysis.R")
    import pytest
    with pytest.raises(ValueError):
        hashes(tmp_path)


def test_submission_never_calls_analyze():
    """Submission validator invokes only data-free inspection."""
    module = ast.parse((ROOT / "agents/document.py").read_text())
    validator = next(n for n in ast.walk(module) if isinstance(n, ast.FunctionDef) and n.name == "validate")
    assert "inspect" in ast.unparse(validator)
    assert "analyze(" not in ast.unparse(validator)


def test_structural_repair_without_analysis_execution(tmp_path):
    """Finalization repairs structure without ever executing exploratory/target data."""
    from agents.document import build
    from agents.models import AgentDependencies
    from pydantic_ai.messages import ModelResponse, ToolCallPart
    from pydantic_ai.models.function import FunctionModel

    class Inspector:
        """Definition-only synthetic runner."""

        def inspect(self):
            """Return a structural failure once, then accept the repaired artifact."""
            if (tmp_path / "analysis.R").read_text() == "bad":
                return {"status": "failed", "error": "synthetic syntax error"}
            return {"status": "ok", "payload": []}

    calls = [("write_artifact_file", {"path":"analysis.R", "content":"bad"}),
             ("write_artifact_file", {"path":"report.md", "content":fixture_report()}),
             ("finalize_design", {"script_file":"analysis.R", "report_file":"report.md"}),
             ("write_artifact_file", {"path":"analysis.R", "content":"good"}),
             ("finalize_design", {"script_file":"analysis.R", "report_file":"report.md"})]
    turn = 0

    def respond(messages, info):
        nonlocal turn
        name, arguments = calls[turn]
        turn += 1
        return ModelResponse(parts=[ToolCallPart(name, arguments, str(turn))])

    deps = AgentDependencies(SimpleNamespace(workspace=tmp_path, limits={"max_contract_repairs":2}), Inspector())
    agent = build(FunctionModel(respond), (ROOT / "prompts/document-20261111.txt").read_text())
    result = agent.run_sync("metadata", deps=deps)
    assert result.output.script_file == "analysis.R"
    assert deps.repairs == 1
    assert turn == 5
