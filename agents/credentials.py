"""Private runtime credential loading without shell evaluation or secret output."""

import argparse
import os
import shlex
from pathlib import Path


def read_api_key(project_root: Path) -> str:
    """Return the exported key or the authorized local .env assignment.

    Args:
        project_root: Trusted project directory containing the optional .env.

    Returns:
        The API key, kept in process memory rather than exported to tools.
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
    """Parse one literal assignment without expansion or executing commands."""
    try:
        parts = shlex.split(value, comments=True, posix=True)
    except ValueError:
        raise ValueError("Malformed OPENAI_API_KEY assignment") from None
    if len(parts) != 1 or not parts[0].strip():
        raise ValueError("OPENAI_API_KEY is empty or malformed")
    return parts[0]


def verify_model(project_root: Path, model: str) -> bool:
    """Check model access without sending observations or printing API errors."""
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
    """Check availability or model access while never emitting a key value."""
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
