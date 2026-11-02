"""Bounded, data-only handling of agent artifacts."""

import hashlib
import json
import shutil
from pathlib import Path

from agents.models import ARTIFACT_NAMES, DesignManifest


def artifact_path(workspace: Path, name: str) -> Path:
    """Resolve an approved regular artifact inside its workspace."""
    if name not in ARTIFACT_NAMES:
        raise ValueError("Only analysis.R, hypotheses.csv, and report.md are permitted")
    candidate = workspace / name
    if candidate.is_symlink():
        raise ValueError("Linked artifacts are forbidden")
    if candidate.resolve().parent != workspace.resolve():
        raise ValueError("Artifact escaped its workspace")
    if candidate.exists() and not candidate.is_file():
        raise ValueError("Artifact must be a regular file")
    return candidate


def write_artifact(workspace: Path, name: str, content: str) -> None:
    """Write a bounded UTF-8 artifact."""
    if len(content.encode("utf-8")) > 262144:
        raise ValueError("Artifact exceeds 256 KiB")
    path = artifact_path(workspace, name)
    path.write_text(content, encoding="utf-8")


def artifact_hashes(workspace: Path) -> dict[str, str]:
    """Hash bounded regular files without interpreting their contents."""
    hashes = {}
    for name in sorted(ARTIFACT_NAMES):
        path = artifact_path(workspace, name)
        if not path.is_file() or path.stat().st_size > 262144:
            raise ValueError(f"Missing or oversized artifact: {name}")
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def freeze_design(workspace: Path, destination: Path, manifest: DesignManifest,
                  checked_hashes: dict[str, str]) -> dict:
    """Publish validated artifacts after a successful agent run."""
    hashes = artifact_hashes(workspace)
    if hashes != checked_hashes:
        raise ValueError("Artifacts changed after their successful contract check")
    if destination.exists():
        raise ValueError("Refusing to overwrite an existing frozen design")
    destination.mkdir(parents=True)
    for name in sorted(ARTIFACT_NAMES):
        shutil.copyfile(artifact_path(workspace, name), destination / name)
        (destination / name).chmod(0o444)
    record = {"manifest": manifest.model_dump(), "hashes": hashes}
    (destination / "frozen.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    (destination / "frozen.json").chmod(0o444)
    return record
