"""Current-session isolation, private environments and exported-key boundaries."""

import asyncio

import pytest

from agents.document import Submission, build
from agents.models import AgentDependencies
from agents.runner import clean_environment
from agents.runtime import live_resources, run_with_audit
from tests.python.helpers import FakeRunner, config_for, seed_artifacts, submission_model


def test_separate_sessions_never_reuse_histories(tmp_path, monkeypatch):
    """Run two current agents and verify that only their own markers occur."""
    monkeypatch.setattr("pydantic_ai.models.ALLOW_MODEL_REQUESTS", False)
    histories = []
    for name in ("agent-a", "agent-b"):
        config = config_for(tmp_path / name)
        seed_artifacts(config.workspace)
        deps = AgentDependencies(config, FakeRunner())
        agent = build(submission_model(), "shared-scientific-instructions")
        result = asyncio.run(run_with_audit(agent, f"private-marker-{name}", deps))
        assert isinstance(result.output, Submission)
        assert deps.runner.modes == ["inspect"]
        assert deps.checked_hashes
        histories.append(result.all_messages_json().decode())
        assert name in (config.audit_dir / "messages.json").read_text()
    assert "private-marker-agent-b" not in histories[0]
    assert "private-marker-agent-a" not in histories[1]


def test_subprocess_environment_does_not_inherit_credentials(tmp_path, monkeypatch):
    """The R bridge inherits only explicitly allowed environment entries."""
    monkeypatch.setenv("OPENAI_API_KEY", "synthetic-canary")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "synthetic-canary")
    environment = clean_environment(tmp_path, tmp_path / "home")
    assert "OPENAI_API_KEY" not in environment
    assert "AWS_SECRET_ACCESS_KEY" not in environment


def test_live_resources_requires_key_without_reading_credential_files(tmp_path, monkeypatch):
    """An absent exported key fails before any provider or credential-file access."""
    config = config_for(tmp_path)
    monkeypatch.setattr("pathlib.Path.read_text", lambda *args, **kwargs: pytest.fail("Unexpected file access"))
    with pytest.raises(ValueError, match="Export OPENAI_API_KEY"):
        asyncio.run(live_resources(config, exported_key=""))
