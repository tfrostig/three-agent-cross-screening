"""Crash-safe publication and report structure without live model calls."""

import json
from types import SimpleNamespace

import pytest

from agents.document import hashes
from agents.document_state import atomic_json, fixture_report, freeze, validate_markdown


def test_report_sections_require_actual_content(tmp_path):
    """Missing and empty sections cannot pass as a complete agent explanation."""
    path = tmp_path / "report.md"
    path.write_text(fixture_report())
    validate_markdown(path)
    path.write_text("## Exploration findings\n## Hypothesis selection\ntext")
    with pytest.raises(ValueError, match="nonempty Markdown sections"):
        validate_markdown(path)


def test_freeze_is_atomic_and_refuses_overwrite(tmp_path):
    """Only the committed directory is visible as frozen; no script is executed."""
    workspace = tmp_path / "work"
    workspace.mkdir()
    (workspace / "analysis.R").write_text('stop("must not execute")')
    (workspace / "report.md").write_text(fixture_report())
    config = SimpleNamespace(workspace=workspace)
    before = hashes(workspace)
    freeze(config, before, [], "recorded R calls", hashes)
    assert (tmp_path / "frozen/complete.json").is_file()
    assert not (tmp_path / "frozen.staging").exists()
    assert json.loads((tmp_path / "frozen/frozen.json").read_text())["hashes"]["analysis.R"] == before["analysis.R"]
    with pytest.raises(RuntimeError, match="overwrite"):
        freeze(config, before, [], "recorded R calls", hashes)
    assert (tmp_path / "frozen.staging").exists()
    assert (tmp_path / "frozen/analysis.R").read_text() == 'stop("must not execute")'


def test_atomic_journal_ignores_partial_file(tmp_path):
    """A leftover partial update does not replace the prior committed state."""
    path = tmp_path / "state.json"
    atomic_json(path, {"attempts": 1})
    path.with_name("state.json.partial").write_text('{"attempts":')
    assert json.loads(path.read_text()) == {"attempts": 1}
    atomic_json(path, {"attempts": 2})
    assert json.loads(path.read_text()) == {"attempts": 2}


def test_committed_source_detects_tampering(tmp_path):
    """Direct source invocations can skip a valid commit without model calls."""
    from agents.document_state import committed
    workspace = tmp_path / "work"
    workspace.mkdir()
    (workspace / "analysis.R").write_text("x <- 1")
    (workspace / "report.md").write_text(fixture_report())
    config = SimpleNamespace(workspace=workspace)
    assert not committed(config)
    freeze(config, hashes(workspace), [], "R source", hashes)
    assert committed(config)
    path = tmp_path / "frozen/analysis.R"
    path.chmod(0o644)
    path.write_text("changed")
    with pytest.raises(RuntimeError, match="changed"):
        committed(config)
