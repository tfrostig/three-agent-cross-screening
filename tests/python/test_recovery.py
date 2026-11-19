"""Timeout recovery preserves isolation, messages, artifacts and consumed budgets."""

import asyncio
import dataclasses
import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from pydantic_ai.messages import (ModelRequest, ModelResponse, ToolCallPart, ToolReturnPart,
                                  UserPromptPart, ModelMessagesTypeAdapter)
from pydantic_ai.models.function import FunctionModel

from agents.document import task
from agents.document_state import fixture_report
from agents.recovery import execute_recovery, prepare, read_state
from tests.python.helpers import FakeRunner, config_for


def previous_timeout(tmp_path):
    """Construct a source-only history ending immediately before a timed-out request."""
    config = dataclasses.replace(config_for(tmp_path), sandbox={"image": "fixture-runtime"})
    prompt = (Path.cwd() / "prompts/system.txt").read_text()
    history = [ModelRequest(parts=[UserPromptPart(task(config))]),
               ModelResponse(parts=[ToolCallPart("run_r", {"code": "source-only"}, "old-call")]),
               ModelRequest(parts=[ToolReturnPart("run_r", {"status": "ok"}, "old-call")])]
    (config.audit_dir / "messages.json").write_bytes(ModelMessagesTypeAdapter.dump_json(history))
    (config.audit_dir / "prompts.json").write_text(json.dumps({"instructions": prompt, "user": task(config)}))
    (config.audit_dir / "session.json").write_text(json.dumps({"status": "failed", "error": "Request timed out.", "duration_seconds": 10}))
    (config.audit_dir / "api-attempts.json").write_text(json.dumps({"attempts": 5}))
    exploration = config.audit_dir / "exploration"
    exploration.mkdir()
    (exploration / "execution-001.R").write_text("source-only")
    (config.audit_dir / "execution-001-result.json").write_text('{"status":"ok"}')
    for name in ("exposed.rds", "unexposed.rds"):
        (config.input_dir / name).write_bytes(b"same-source")
    (tmp_path / "session-config.json").write_text(json.dumps(dataclasses.asdict(config), default=str))
    return config


def destination(tmp_path, original):
    """Prepare another source's paths with byte-identical observations."""
    config = dataclasses.replace(config_for(tmp_path), sandbox={"image": "fixture-runtime"})
    for name in ("exposed.rds", "unexposed.rds"):
        (config.input_dir / name).write_bytes((original.input_dir / name).read_bytes())
    return config


def test_state_keeps_consumed_budgets_and_rejects_changed_prompt(tmp_path):
    """A continuation gets remaining attempts, never a fresh conversation budget."""
    original = previous_timeout(tmp_path / "original")
    state = read_state(original.workspace.parent, original)
    assert (state.attempts, state.r_calls, state.sequence, state.usage.tool_calls) == (5, 1, 1, 1)
    record = original.audit_dir / "prompts.json"
    record.write_text('{"instructions":"changed", "user":"changed"}')
    with pytest.raises(ValueError, match="differ"):
        read_state(original.workspace.parent, original)


def test_exhausted_attempts_cannot_restart(tmp_path):
    """Even a timeout cannot bypass the original physical-attempt limit."""
    config = previous_timeout(tmp_path / "original")
    (config.audit_dir / "api-attempts.json").write_text('{"attempts":16}')
    with pytest.raises(ValueError, match="exhausted"):
        read_state(config.workspace.parent, config)


def test_workspace_links_are_rejected_before_copying(tmp_path):
    """A hostile workspace link cannot copy host-private data into the new source."""
    original = previous_timeout(tmp_path / "original")
    config = destination(tmp_path / "continuation", original)
    private = tmp_path / "private-canary"
    private.write_text("synthetic-canary")
    (original.workspace / "linked").symlink_to(private)
    state = read_state(original.workspace.parent, config)
    with pytest.raises(ValueError, match="Linked source files"):
        prepare(config, original.workspace.parent, state)
    assert not list(config.workspace.iterdir())
    assert not list(config.audit_dir.iterdir())


def test_continuation_uses_old_history_without_another_user_prompt(tmp_path, monkeypatch):
    """Finish a saved source using a mock model and retain the untouched old failure."""
    original = previous_timeout(tmp_path / "original")
    config = destination(tmp_path / "continuation", original)
    transport = SimpleNamespace(attempts=0)
    captured = []
    calls = [("write_artifact_file", {"path": "analysis.R", "content": "fixture"}),
             ("write_artifact_file", {"path": "report.md", "content": fixture_report()}),
             ("finalize_design", {"script_file": "analysis.R", "report_file": "report.md"})]

    def respond(messages, info):
        captured.append(messages)
        transport.attempts += 1
        name, arguments = calls[len(captured)-1]
        return ModelResponse(parts=[ToolCallPart(name, arguments, f"new-{len(captured)}")])

    class Client:
        async def close(self):
            """Release mock resources."""

    async def resources(*args, **kwargs):
        return FunctionModel(respond), Client(), transport

    monkeypatch.setenv("OPENAI_API_KEY", "synthetic-canary")
    monkeypatch.setattr("agents.recovery.live_resources", resources)
    monkeypatch.setattr("agents.recovery.DocumentRunner", lambda config: FakeRunner())
    asyncio.run(execute_recovery(config, original.workspace.parent))
    assert sum(isinstance(p, UserPromptPart) for m in captured[0] for p in m.parts) == 1
    assert captured[0][1].parts[0].tool_call_id == "old-call"
    record = json.loads((config.audit_dir / "session.json").read_text())
    assert (record["physical_api_attempts"], record["new_api_attempts"]) == (8, 3)
    assert json.loads((original.audit_dir / "session.json").read_text())["status"] == "failed"
    assert (config.workspace.parent / "frozen/complete.json").exists()
    with pytest.raises(ValueError, match="observations changed"):
        other = destination(tmp_path / "changed", original)
        (other.input_dir / "exposed.rds").write_bytes(b"different")
        asyncio.run(execute_recovery(other, original.workspace.parent))
