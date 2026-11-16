"""Atomic artifacts, report structure and crash-safe usage records for document sessions."""

import hashlib
import json
import os
import re
import shutil
from pathlib import Path

SECTIONS = ("Exploration findings", "Hypothesis selection", "Final procedure", "Assumptions and limitations")


def atomic_json(path, value):
    """Publish a JSON record atomically.

    Args:
        path: Controller-owned destination.
        value: JSON-serializable payload, never credentials.
    """
    path = Path(path)
    temporary = path.with_name(path.name + ".partial")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def validate_markdown(path):
    """Check required nonempty report sections without grading scientific content.

    Args:
        path: Submitted report Markdown.
    """
    text = Path(path).read_text(encoding="utf-8")
    text = re.sub(r"(?ms)^(`{3,}|~{3,}).*?^\1\s*$", "", text)
    blocks = re.split(r"(?m)^#{1,6}\s+(.+?)\s*#*\s*$", text)
    found = {blocks[i].strip().casefold(): blocks[i+1].strip() for i in range(1, len(blocks)-1, 2)}
    missing = [name for name in SECTIONS if not found.get(name.casefold())]
    if missing:
        raise ValueError("report.md requires nonempty Markdown sections: " + ", ".join(missing))


def fixture_report():
    """Return an explicitly prewritten fixture satisfying the report format."""
    bodies = ("Executed a source-only dimensions/mean diagnostic; this fixture ignores it.",
              "All measurements and positive directions are prewritten, not selected by an agent.",
              "One-sided Welch with Holm or BH; outcome values equal directional values.",
              "Software fixture only; no autonomous method choice or evidence of agent performance.")
    return "# Offline fixture\n\n" + "\n\n".join(f"## {title}\n{body}" for title, body in zip(SECTIONS, bodies))


def freeze(config, checked, family, exploration, hash_function):
    """Publish a complete frozen directory with a commit marker using atomic rename.

    Args:
        config: Session paths, without simulation truth.
        checked: Accepted script/report hashes.
        family: Inspected hypothesis records.
        exploration: Recorded code and outputs as Markdown.
        hash_function: Bounded artifact hashing function.
    """
    if hash_function(config.workspace) != checked:
        raise RuntimeError("Artifacts changed before freezing")
    destination = config.workspace.parent / "frozen"
    staging = config.workspace.parent / "frozen.staging"
    staging.mkdir(exist_ok=False)
    for name in checked:
        shutil.copyfile(config.workspace / name, staging / name)
    (staging / "exploration.md").write_text(exploration, encoding="utf-8")
    digests = hash_function(staging)
    digests["exploration.md"] = hashlib.sha256((staging / "exploration.md").read_bytes()).hexdigest()
    atomic_json(staging / "frozen.json", {"protocol": "document-v2", "hashes": digests, "hypotheses": family})
    atomic_json(staging / "complete.json", {"frozen_sha256": hashlib.sha256((staging / "frozen.json").read_bytes()).hexdigest()})
    for path in staging.iterdir():
        path.chmod(0o444)
    if destination.exists():
        raise RuntimeError("Refusing to overwrite frozen artifacts")
    staging.rename(destination)


def usage_from_messages(config):
    """Retain known token usage on failures; unknown usage is never invented.

    Args:
        config: Session audit path.
    """
    path = config.audit_dir / "messages.json"
    if not path.exists():
        return None
    messages = json.loads(path.read_text())
    responses = [m for m in messages if m.get("kind") == "response"]
    return {key: sum(m.get("usage", {}).get(key, 0) or 0 for m in responses)
            for key in ("input_tokens", "output_tokens")}


def committed(config):
    """Verify a frozen commit before allowing any direct session invocation.

    Args:
        config: Source-only session paths.
    """
    root = config.workspace.parent / "frozen"
    marker = root / "complete.json"
    if not marker.exists():
        return False
    metadata = root / "frozen.json"
    expected = json.loads(marker.read_text())["frozen_sha256"]
    if hashlib.sha256(metadata.read_bytes()).hexdigest() != expected:
        raise RuntimeError("Frozen commit metadata changed")
    record = json.loads(metadata.read_text())
    for name, digest in record["hashes"].items():
        path = root / name
        if name not in {"analysis.R", "report.md", "exploration.md"} or path.is_symlink():
            raise RuntimeError("Invalid frozen artifact")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError("Frozen artifact changed")
    return True
