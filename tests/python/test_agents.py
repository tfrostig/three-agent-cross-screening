import asyncio
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from pydantic_ai import UsageLimits
from pydantic_ai.models import ALLOW_MODEL_REQUESTS

from agents.artifacts import artifact_hashes, artifact_path, freeze_design, write_artifact
from agents.factory import build_agent
from agents.models import AgentDependencies, DesignManifest, SessionConfig, ToolResult
from agents.offline import offline_model
from agents.runner import clean_environment
from agents.session import run_with_audit


def config_for(tmp_path):
    work = tmp_path / "work"
    work.mkdir()
    return SessionConfig("opaque", 20, 8, "FWER", .05 / 3, "gpt-6.1-sol",
                         tmp_path / "input", work, tmp_path / "audit", Path.cwd(), {},
                         {"max_r_executions": 12, "max_contract_repairs": 2}, {})


class FakeRunner:
    def __init__(self):
        self.modes = []

    def execute(self, mode, code=""):
        self.modes.append(mode)
        return ToolResult(status="ok", stdout="fixture")


def manifest():
    return DesignManifest(script_file="analysis.R", hypotheses_file="hypotheses.csv",
                          report_file="report.md", test_summary="test", multiplicity_summary="holm",
                          assumptions=[], limitations=[])


def seed_artifacts(workspace):
    for name in ("analysis.R", "hypotheses.csv", "report.md"):
        write_artifact(workspace, name, "fixture")


def test_fresh_pydantic_runs_use_only_their_own_dependencies(tmp_path, monkeypatch):
    monkeypatch.setattr("pydantic_ai.models.ALLOW_MODEL_REQUESTS", False)
    config = config_for(tmp_path)
    seed_artifacts(config.workspace)
    runner = FakeRunner()
    deps = AgentDependencies(config, runner)
    agent = build_agent(offline_model(), "system", "instructions")
    result = asyncio.run(agent.run("only-own-data", deps=deps, message_history=[],
                                   usage_limits=UsageLimits(request_limit=4)))
    assert isinstance(result.output, DesignManifest)
    assert runner.modes == ["explore", "check"]
    assert deps.r_executions == 1
    assert b"only-own-data" in result.all_messages_json()
    assert deps.checked_hashes == artifact_hashes(config.workspace)


def test_artifact_paths_and_freezing_reject_escape_and_mutation(tmp_path):
    work = tmp_path / "work"
    work.mkdir()
    with pytest.raises(ValueError):
        artifact_path(work, "../private/truth.rds")
    outside = tmp_path / "canary"
    outside.write_text("private")
    (work / "analysis.R").symlink_to(outside)
    with pytest.raises(ValueError):
        artifact_path(work, "analysis.R")
    (work / "analysis.R").unlink()
    seed_artifacts(work)
    hashes = artifact_hashes(work)
    write_artifact(work, "analysis.R", "changed")
    with pytest.raises(ValueError, match="changed"):
        freeze_design(work, tmp_path / "frozen", manifest(), hashes)


def test_subprocess_environment_does_not_inherit_credentials(tmp_path, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "synthetic-canary")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "synthetic-canary")
    environment = clean_environment(tmp_path, tmp_path / "home")
    assert "OPENAI_API_KEY" not in environment
    assert "AWS_SECRET_ACCESS_KEY" not in environment


def test_manifest_has_fixed_paths_and_forbids_extra_fields():
    raw = manifest().model_dump()
    raw["script_file"] = "../truth"
    with pytest.raises(ValidationError):
        DesignManifest.model_validate(raw)
    raw = manifest().model_dump() | {"target_data": "/private/truth"}
    with pytest.raises(ValidationError):
        DesignManifest.model_validate(raw)


def test_separate_sessions_never_reuse_histories(tmp_path, monkeypatch):
    monkeypatch.setattr("pydantic_ai.models.ALLOW_MODEL_REQUESTS", False)
    histories = []
    for name in ("agent-a", "agent-b"):
        root = tmp_path / name
        root.mkdir()
        config = config_for(root)
        seed_artifacts(config.workspace)
        runner = FakeRunner()
        deps = AgentDependencies(config, runner)
        agent = build_agent(offline_model(), "shared-system", "shared-instructions")
        result = asyncio.run(agent.run(f"private-marker-{name}", deps=deps, message_history=[]))
        histories.append(result.all_messages_json().decode())
    assert "private-marker-agent-b" not in histories[0]
    assert "private-marker-agent-a" not in histories[1]


def test_iterated_runs_persist_messages_for_audit(tmp_path, monkeypatch):
    monkeypatch.setattr("pydantic_ai.models.ALLOW_MODEL_REQUESTS", False)
    config = config_for(tmp_path)
    config.openai.update(request_limit=16, max_output_tokens=8192)
    config.limits["tool_calls_limit"] = 32
    config.audit_dir.mkdir()
    seed_artifacts(config.workspace)
    deps = AgentDependencies(config, FakeRunner())
    agent = build_agent(offline_model(), "system", "instructions")
    result = asyncio.run(run_with_audit(agent, "audit-marker", deps))
    assert isinstance(result.output, DesignManifest)
    messages = (config.audit_dir / "messages.json").read_text()
    assert "audit-marker" in messages
    assert "finalize_design" in messages
