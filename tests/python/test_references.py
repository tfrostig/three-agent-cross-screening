import asyncio
import hashlib
import json
from pathlib import Path

import pytest

from agents.factory import build_agent
from agents.models import AgentDependencies
from agents.offline import offline_model
from agents.prompts import load_prompts, user_prompt
from agents.references import ReferenceLibrary
from agents.session import run_with_audit
from tests.python.test_agents import FakeRunner, config_for, seed_artifacts


def reference_pack(root, marker="reference-marker"):
    root.mkdir(parents=True)
    brief = "Shared methods brief; no observations."
    (root / "brief.md").write_text(brief)
    (root / "card.md").write_text(marker)
    catalog = {"version": 1, "brief_file": "brief.md", "files": {
        "brief.md": hashlib.sha256(brief.encode()).hexdigest(),
        "card.md": hashlib.sha256(marker.encode()).hexdigest()}, "references": {
            "two-team": {"title": "Two-team methods", "citation": "Fixture citation",
                         "source_file": "fixture.pdf", "sections": {
                             "overview": {"file": "card.md", "pages": "1", "kind": "summary"}}}}}
    (root / "catalog.json").write_text(json.dumps(catalog))
    return root


def test_reference_lookup_uses_ids_not_paths(tmp_path):
    library = ReferenceLibrary.load(reference_pack(tmp_path / "pack"))
    for reference_id, section in [("../private", "overview"), ("two-team", "../private"),
                                  ("/etc/passwd", "overview")]:
        with pytest.raises(ValueError, match="Unknown reference"):
            library.read(reference_id, section)
    result = library.read("two-team")
    assert result.status == "ok"
    assert "reference-marker" in result.stdout
    assert "Fixture citation" in result.stdout and "PDF pages: 1" in result.stdout


def test_reference_hashes_and_session_snapshots(tmp_path):
    root = reference_pack(tmp_path / "pack", "initial")
    first = ReferenceLibrary.load(root)
    (root / "card.md").write_text("changed")
    assert "initial" in first.read("two-team").stdout
    with pytest.raises(ValueError, match="changed since"):
        ReferenceLibrary.load(root)
    other = ReferenceLibrary.load(reference_pack(tmp_path / "other", "second-session"))
    assert "second-session" not in first.read("two-team").stdout
    assert first.digest != other.digest
    with pytest.raises(ValueError, match="session manifest"):
        ReferenceLibrary.load(tmp_path / "other", expected_digest=first.digest)


def test_reference_symlinks_and_oversized_sections_are_rejected(tmp_path):
    root = reference_pack(tmp_path / "pack")
    (tmp_path / "private.txt").write_text("synthetic-truth-canary")
    (root / "card.md").unlink()
    (root / "card.md").symlink_to(tmp_path / "private.txt")
    with pytest.raises(ValueError, match="escaped|Linked"):
        ReferenceLibrary.load(root)
    oversized = reference_pack(tmp_path / "oversized", "a" * 6145)
    with pytest.raises(ValueError, match="size limit"):
        ReferenceLibrary.load(oversized)


def test_catalog_cannot_approve_a_file_outside_the_pack(tmp_path):
    root = reference_pack(tmp_path / "pack")
    catalog_path = root / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    catalog["files"]["../private.txt"] = "not-a-hash"
    catalog_path.write_text(json.dumps(catalog))
    with pytest.raises(ValueError, match="Invalid reference filename"):
        ReferenceLibrary.load(root)


def test_offline_tool_loop_reads_references_without_using_r_budget(tmp_path, monkeypatch):
    monkeypatch.setattr("pydantic_ai.models.ALLOW_MODEL_REQUESTS", False)
    config = config_for(tmp_path)
    config.openai.update(request_limit=16, max_output_tokens=8192)
    config.limits["tool_calls_limit"] = 32
    config.audit_dir.mkdir()
    seed_artifacts(config.workspace)
    references = ReferenceLibrary.load(reference_pack(tmp_path / "pack"))
    runner = FakeRunner()
    deps = AgentDependencies(config, runner, references=references)
    system, instructions = load_prompts(Path.cwd(), references)
    assert "reference-marker" not in instructions
    assert "Shared methods brief" in instructions
    agent = build_agent(offline_model(with_references=True), system, instructions)
    asyncio.run(run_with_audit(agent, user_prompt(config), deps))
    assert runner.modes == ["explore", "check"] and deps.r_executions == 1
    messages = (config.audit_dir / "messages.json").read_text()
    assert "read_reference" in messages and "reference-marker" in messages
    assert "synthetic-truth-canary" not in messages


def test_production_pack_has_only_sanitized_proposal_access():
    references = ReferenceLibrary.load(Path("references/agent-pack"))
    assert set(references.catalog["references"]["proposal"]["sections"]) == {"overview"}
    for reference_id, entry in references.catalog["references"].items():
        for section in entry["sections"]:
            assert len(references.read(reference_id, section).stdout.encode()) <= 8192
    assert 800 <= len(references.contents["brief.md"].split()) <= 1200
