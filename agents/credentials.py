"""Trusted-controller credential parsing and optional model-access checks.

Uses an exported key first, otherwise the previously authorized private loader.
Assignments are never shell-sourced, expanded, logged, or sent to R containers.
Publication/documentation checks never call this loader."""

import argparse
import os
import shlex
from pathlib import Path


def read_api_key(project_root: Path) -> str:
    """Load the runtime key without shell evaluation or secret output.

    Args:
        project_root: Trusted project directory with an optional authorized .env.

    Returns:
        Exported OPENAI_API_KEY when set, otherwise its literal .env assignment.
        The value stays in controller memory and is never passed to R containers.

    Raises:
        ValueError: The assignment is missing, empty, or malformed.
    """
    exported = os.environ.get("OPENAI_API_KEY", "").strip()
    if exported:
        return exported
    path = project_root / ".env"
    if not path.is_file():
        raise ValueError("No exported OPENAI_API_KEY or local .env credential")
    with path.open(encoding="utf-8-sig") as stream:
        for line in stream:
            assignment = line.strip().removeprefix("export ").strip()
            name, separator, value = assignment.partition("=")
            if separator and name.strip() == "OPENAI_API_KEY":
                return parse_key(value)
    raise ValueError("OPENAI_API_KEY is missing from the local credential file")


def parse_key(value: str) -> str:
    """Parse one literal key assignment without expansion or execution.

    Args:
        value: Right-hand side of an OPENAI_API_KEY assignment, with optional quotes.

    Returns:
        Exactly one nonempty literal token; shell substitutions remain literal.

    Raises:
        ValueError: Invalid quoting or multiple/empty tokens, with no secret echoed.
    """
    try:
        parts = shlex.split(value, comments=True, posix=True)
    except ValueError:
        raise ValueError("Malformed OPENAI_API_KEY assignment") from None
    if len(parts) != 1 or not parts[0].strip():
        raise ValueError("OPENAI_API_KEY is empty or malformed")
    return parts[0]


def verify_model(project_root: Path, model: str) -> bool:
    """Check model availability through the trusted controller only.

    Args:
        project_root: Root used by the private credential loader.
        model: Explicit provider model ID; never substituted automatically.

    Returns:
        Boolean success; prints only model identity or error class/HTTP status.
        This uses the models endpoint outside the design-session transport.
    """
    from openai import OpenAI

    try:
        with OpenAI(api_key=read_api_key(project_root), max_retries=0, timeout=30) as client:
            client.models.retrieve(model)
    except Exception as error:
        status = getattr(error, "status_code", None)
        print(f"Model-access check failed: {type(error).__name__}; HTTP status={status}")
        return False
    print(f"Credential configured; model access verified: {model}")
    return True


def main():
    """Check runtime credential availability or explicit model access.

    --check only checks key availability. --verify-model MODEL makes a provider
    model-access request without sending observations or printing the credential.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--verify-model")
    args = parser.parse_args()
    root = Path.cwd()
    if args.verify_model:
        raise SystemExit(0 if verify_model(root, args.verify_model) else 1)
    try:
        read_api_key(root)
    except ValueError:
        raise SystemExit("Credential unavailable; export OPENAI_API_KEY or configure local .env") from None
    print("Credential configured (value not displayed)")


if __name__ == "__main__":
    main()
