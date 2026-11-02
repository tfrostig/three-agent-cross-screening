"""Verify and snapshot curated methods references independently per session.

Only catalog-approved payloads are readable. The common brief is injected into
shared instructions; optional sections are retrieved by ID with citations and
size limits. This interface cannot read original PDFs or arbitrary host paths."""

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from agents.models import ToolResult


def approved_file(root: Path, name: str) -> Path:
    """Resolve one catalog-relative regular file inside the reference pack.

    Args:
        root: Trusted reference-pack directory.
        name: Approved relative filename, without absolute paths or traversal.

    Returns:
        Existing regular Path after containment and link checks.

    Raises:
        ValueError: The reference is missing, linked, or outside the library.
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
    """Read only catalog-approved payloads and verify their byte hashes.

    Args:
        root: Reference-pack directory.
        catalog: Versioned catalog containing payload digests and allowed sections.

    Returns:
        UTF-8 text mapping owned by this session; at most 16 KiB for the brief
        and 6 KiB per other payload. Rejects stale or unapproved content.
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
    """Session-local verified snapshot of approved methodological context.

    Attributes:
        digest: SHA-256 of the original catalog bytes.
        catalog: Allowed references, section locators, citations, and payload hashes.
        contents: Verified UTF-8 payloads, loaded once for this session.

    Frozen dataclass fields prevent reassignment; nested dictionaries are treated
    as controller-owned values and are never passed to tools for modification.
    """

    digest: str
    catalog: dict
    contents: dict[str, str]

    @classmethod
    def load(cls, root: Path, expected_digest: str | None = None):
        """Snapshot a verified library before model access.

        Args:
            root: Reference-pack directory containing catalog.json.
            expected_digest: Optional catalog SHA-256 locked by the R controller.

        Returns:
            New ReferenceLibrary containing verified text and catalog metadata.

        Raises:
            ValueError: The catalog/version/digest or an approved payload is invalid.
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
        """Compose the common brief and available section IDs for shared instructions.

        Returns:
            Prompt text with reference_brief delimiters. Full optional excerpts
            are not injected; the model requests those through read_reference.
        """
        entries = []
        for reference_id, entry in self.catalog["references"].items():
            sections = ", ".join(entry["sections"])
            entries.append(f"- {reference_id}: {entry['title']} (sections: {sections})")
        brief = self.contents[self.catalog["brief_file"]]
        return ("\n\n<reference_brief>\n" + brief + "\n</reference_brief>\n\n"
                "REFERENCE CATALOG\n" + "\n".join(entries))

    def read(self, reference_id: str, section_id: str = "overview") -> ToolResult:
        """Return one approved section with attribution and PDF page locators.

        Args:
            reference_id: Allowlisted library ID from the common catalog.
            section_id: Named section, defaulting to overview.

        Returns:
            ToolResult whose stdout is the cited section, bounded to 8 KiB total.

        Raises:
            ValueError: IDs are unknown or the response exceeds its size limit.
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
        """Describe exactly which reference context was available in this session.

        Returns:
            Dictionary containing the catalog digest, full catalog, and injected
            brief. Requested section content is recorded in conversation audits.
        """
        return {"digest": self.digest, "catalog": self.catalog,
                "brief": self.contents[self.catalog["brief_file"]]}
