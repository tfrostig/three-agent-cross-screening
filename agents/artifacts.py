"""Bounded data-only artifact writes, integrity checks, and final freezing.

Only analysis.R, hypotheses.csv, and report.md are writable through the tool.
No artifact is evaluated by this module; successful source checks authorize
freezing only the exact bytes whose hashes were recorded."""

import hashlib
import json
import shutil
from pathlib import Path

from agents.models import ARTIFACT_NAMES, DesignManifest


def artifact_path(workspace: Path, name: str) -> Path:
    """Resolve one of the three permitted regular workspace artifacts.

    Args:
        workspace: Session-specific mutable work directory.
        name: analysis.R, hypotheses.csv, or report.md only.

    Returns:
        Safe local Path; a missing destination is permitted before its first write.

    Raises:
        ValueError: The name, path containment, link, or file type is unsafe.
    """
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
    """Write a bounded UTF-8 artifact without executing its contents.

    Args:
        workspace: Session-specific artifact directory.
        name: One allowlisted artifact basename.
        content: Text no larger than 256 KiB when UTF-8 encoded.

    Raises:
        ValueError: The artifact is oversized or its path is unsafe.
    """
    if len(content.encode("utf-8")) > 262144:
        raise ValueError("Artifact exceeds 256 KiB")
    path = artifact_path(workspace, name)
    path.write_text(content, encoding="utf-8")


def artifact_hashes(workspace: Path) -> dict[str, str]:
    """Hash the three bounded regular artifacts as raw bytes.

    Args:
        workspace: Directory containing all three required artifact files.

    Returns:
        Mapping from artifact basename to SHA-256 digest.

    Raises:
        ValueError: An artifact is missing, linked, unsafe, or larger than 256 KiB.
    """
    hashes = {}
    for name in sorted(ARTIFACT_NAMES):
        path = artifact_path(workspace, name)
        if not path.is_file() or path.stat().st_size > 262144:
            raise ValueError(f"Missing or oversized artifact: {name}")
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def freeze_design(workspace: Path, destination: Path, manifest: DesignManifest,
                  checked_hashes: dict[str, str]) -> dict:
    """Publish checked artifacts exactly once and make their copies read-only.

    Args:
        workspace: Mutable directory that passed the latest check.
        destination: New sibling frozen directory; an existing directory is refused.
        manifest: Validated structured scientific description from final output.
        checked_hashes: Digests saved after a successful current-artifact check.

    Returns:
        Manifest/hash record also written to frozen.json; source bytes are copied.

    Raises:
        ValueError: Bytes changed after checking or the frozen destination exists.
    """
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
