import os

import pytest

from agents.credentials import parse_key, read_api_key
from agents.runner import clean_environment


def test_exported_key_takes_precedence_without_opening_file(tmp_path, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "synthetic-exported")
    (tmp_path / ".env").mkdir()
    assert read_api_key(tmp_path) == "synthetic-exported"


def test_private_file_loading_does_not_export_any_values(tmp_path, monkeypatch, capsys):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    (tmp_path / ".env").write_text('# private\nOTHER_SECRET=ignored\nexport OPENAI_API_KEY="synthetic#key" # comment\n')
    assert read_api_key(tmp_path) == "synthetic#key"
    assert "OPENAI_API_KEY" not in os.environ
    assert "OTHER_SECRET" not in os.environ
    assert capsys.readouterr().out == ""
    assert "OPENAI_API_KEY" not in clean_environment(tmp_path, tmp_path)


def test_parser_never_executes_or_expands_shell_expressions(tmp_path):
    assert parse_key("'$(echo synthetic-secret)' # comment") == "$(echo synthetic-secret)"
    assert parse_key("'$HOME'") == "$HOME"
    for value in ("", "''", '"unterminated', "two tokens"):
        with pytest.raises(ValueError):
            parse_key(value)


def test_parser_errors_do_not_include_secret_values():
    with pytest.raises(ValueError) as caught:
        parse_key('"synthetic-do-not-display')
    assert "synthetic-do-not-display" not in str(caught.value)
