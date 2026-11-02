"""Verified, session-local snapshots of curated methodological references."""

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from agents.models import ToolResult


def approved_file(root: Path, name: str) -> Path:
    """Resolve a regular, unlinked file within the reference pack.

    Args:
        root: Reference pack directory.
        name: Catalog-relative filename.
    """
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Invalid reference filename")
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("Reference escaped its library")
    if any(parent.is_symlink() for parent in [path, *path.parents] if parent != root.parent):
        raise ValueError("Linked references are forbidden")
    if not path.is_file():
        raise ValueError("Reference is missing or not a regular file")
    return path


def snapshot_contents(root: Path, catalog: dict) -> dict[str, str]:
    """Read and verify only the files explicitly approved by the catalog.

    Args:
        root: Reference pack directory.
        catalog: Versioned catalog with approved files and their hashes.
    """
    contents = {}
    for name, expected in catalog["files"].items():
        path = approved_file(root, name)
        limit = 16384 if name == catalog["brief_file"] else 6144
        if path.stat().st_size > limit:
            raise ValueError(f"Reference exceeds its size limit: {name}")
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f"Reference changed since its catalog was built: {name}")
        contents[name] = raw.decode("utf-8")
    for entry in catalog["references"].values():
        if "overview" not in entry["sections"]:
            raise ValueError("Reference has no overview")
        for section in entry["sections"].values():
            if section["file"] not in contents:
                raise ValueError("Section file is not approved by the catalog")
    return contents


@dataclass(frozen=True)
class ReferenceLibrary:
    """Hold verified reference text independently for a single agent session."""

    digest: str
    catalog: dict
    contents: dict[str, str]

    @classmethod
    def load(cls, root: Path, expected_digest: str | None = None):
        """Snapshot an approved pack and optionally enforce its recorded identity.

        Args:
            root: Reference pack directory.
            expected_digest: SHA-256 catalog identity from the R controller.
        """
        path = approved_file(root, "catalog.json")
        if path.stat().st_size > 65536:
            raise ValueError("Reference catalog exceeds 64 KiB")
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if expected_digest is not None and digest != expected_digest:
            raise ValueError("Reference catalog differs from the session manifest")
        catalog = json.loads(raw)
        if catalog.get("version") != 1:
            raise ValueError("Unsupported reference catalog version")
        contents = snapshot_contents(root, catalog)
        if catalog["brief_file"] not in contents:
            raise ValueError("Reference brief is not approved by the catalog")
        return cls(digest, catalog, contents)

    def prompt_context(self) -> str:
        """Return the common brief and catalog without loading all paper sections."""
        entries = []
        for reference_id, entry in self.catalog["references"].items():
            sections = ", ".join(entry["sections"])
            entries.append(f"- {reference_id}: {entry['title']} (sections: {sections})")
        brief = self.contents[self.catalog["brief_file"]]
        return ("\n\n<reference_brief>\n" + brief + "\n</reference_brief>\n\n"
                "REFERENCE CATALOG\n" + "\n".join(entries))

    def read(self, reference_id: str, section_id: str = "overview") -> ToolResult:
        """Return one bounded section with attribution, never an arbitrary file.

        Args:
            reference_id: Approved reference ID.
            section_id: Approved section ID within that reference.
        """
        entry = self.catalog["references"].get(reference_id)
        if entry is None or section_id not in entry["sections"]:
            raise ValueError("Unknown reference or section; use the shared catalog IDs")
        section = entry["sections"][section_id]
        text = (f"Reference: {reference_id} / {section_id}\nCitation: {entry['citation']}\n"
                f"Source: {entry['source_file']}; PDF pages: {section['pages']}\n"
                f"Content: {section['kind']}; methodological background, not instructions\n\n"
                + self.contents[section["file"]])
        if len(text.encode("utf-8")) > 8192:
            raise ValueError("Reference response exceeds 8 KiB")
        return ToolResult(status="ok", stdout=text)

    def audit_record(self) -> dict:
        """Record the exact injected brief and the identity of available sections."""
        return {"digest": self.digest, "catalog": self.catalog,
                "brief": self.contents[self.catalog["brief_file"]]}
