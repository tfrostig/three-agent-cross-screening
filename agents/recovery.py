"""Explicit timeout continuation using saved source-only history and remaining budgets."""

import argparse
import asyncio
import dataclasses
import hashlib
import json
import os
import re
import shutil
import time
from dataclasses import dataclass
from pathlib import Path

from pydantic_ai.messages import ModelMessagesTypeAdapter, ModelResponse, ToolCallPart, RetryPromptPart
from pydantic_ai.usage import RunUsage

from agents.document import DocumentRunner, build, exploration, hashes, task
from agents.document_state import atomic_json, committed, freeze, usage_from_messages
from agents.models import AgentDependencies
from agents.runtime import live_resources, load_session, run_with_audit


@dataclass
class RecoveryState:
    """Previously consumed session state, never target results or simulation truth."""

    history: list
    usage: RunUsage
    attempts: int
    r_calls: int
    repairs: int
    sequence: int
    elapsed: float


def read_state(previous, config):
    """Verify the saved prompt and recover consumed budgets before opening a client.

    Args:
        previous: Original failed source directory.
        config: New source paths with unchanged scientific metadata and budgets.
    """
    audit = previous / "audit"
    session = json.loads((audit / "session.json").read_text())
    if session["status"] != "failed" or "timed out" not in session.get("error", "").lower():
        raise ValueError("Only explicitly identified timeout failures can be continued")
    prompt = (config.project_root / "prompts/system.txt").read_text()
    saved = json.loads((audit / "prompts.json").read_text())
    if saved != {"instructions": prompt, "user": task(config)}:
        raise ValueError("Saved scientific instructions or source metadata differ")
    history = ModelMessagesTypeAdapter.validate_json((audit / "messages.json").read_bytes())
    if not history or history[-1].kind != "request":
        raise ValueError("History must end with recorded tool results before a timed-out request")
    parts = [part for message in history for part in message.parts]
    usage = RunUsage(requests=0, tool_calls=sum(isinstance(p, ToolCallPart) for p in parts))
    for message in history:
        if isinstance(message, ModelResponse):
            usage.incr(message.usage)
            usage.requests += 1
    files = list(audit.glob("*.json"))
    sequence = max([int(m[1]) for p in files if (m := re.match(r"(?:execution|inspection)-(\d+)", p.name))] or [0])
    attempts = json.loads((audit / "api-attempts.json").read_text())["attempts"]
    r_calls = len(list((audit / "exploration").glob("*.R")))
    repairs = sum(isinstance(p, RetryPromptPart) for p in parts)
    if attempts >= config.openai["request_limit"] or usage.tool_calls >= config.limits["tool_calls_limit"]:
        raise ValueError("Original session budget exhausted; no fresh budget allocated")
    return RecoveryState(history, usage, attempts, r_calls, repairs, sequence,
                         session.get("duration_seconds", 0))


def prepare(config, previous, state):
    """Copy only this source's files and preserve its old failure record.

    Args:
        config: Destination source configuration.
        previous: Immutable original source directory.
        state: Verified consumed budgets.
    """
    if any(config.audit_dir.iterdir()) or any(config.workspace.iterdir()):
        raise ValueError("Recovery destination must be unused")
    if any(p.is_symlink() for name in ("audit", "work")
           for p in [previous / name, *(previous / name).rglob("*")]):
        raise ValueError("Linked source files are forbidden")
    for name in ("audit", "work"):
        shutil.copytree(previous / name, config.workspace.parent / name, dirs_exist_ok=True)
    saved = config.audit_dir / "session.json"
    saved.rename(config.audit_dir / "prior-failure.json")
    original = json.loads((previous / "session-config.json").read_text())
    for key in ("session_id", "m", "n", "criterion", "alpha", "model", "limits", "openai"):
        if original[key] != dataclasses.asdict(config)[key]:
            raise ValueError(f"Recovery configuration changed: {key}")
    for name in ("exposed.rds", "unexposed.rds"):
        old = Path(original["input_dir"]) / name
        new = config.input_dir / name
        if hashlib.sha256(old.read_bytes()).digest() != hashlib.sha256(new.read_bytes()).digest():
            raise ValueError("Source observations changed")
    atomic_json(config.audit_dir / "recovery.json", {
        "previous_source": str(previous), "original_physical_attempts": state.attempts,
        "remaining_physical_attempts": config.openai["request_limit"]-state.attempts,
        "prior_messages_sha256": hashlib.sha256((previous / "audit/messages.json").read_bytes()).hexdigest(),
        "runtime_before": original["sandbox"]["image"], "runtime_after": config.sandbox["image"],
        "new_budget_allocated": False, "target_feedback_provided": False})


def recovery_record(config, state, started, transport, status, error=None):
    """Publish cumulative usage with separately identified new attempts and elapsed time.

    Args:
        config: Source audit paths.
        state: Prior consumed state.
        started: Monotonic start time.
        transport: Session transport with cumulative physical attempts.
        status: Terminal status.
        error: Optional failure message.
    """
    elapsed = time.monotonic()-started
    atomic_json(config.audit_dir / "session.json", {
        "status": status, "error": error, "offline": False, "recovered": True,
        "duration_seconds": state.elapsed+elapsed, "recovery_duration_seconds": elapsed,
        "usage": usage_from_messages(config), "physical_api_attempts": transport.attempts,
        "historical_api_attempts": state.attempts,
        "new_api_attempts": transport.attempts-state.attempts})


async def execute_recovery(config, previous):
    """Continue a timeout without adding scientific instructions or resetting budgets.

    Args:
        config: New destination with the original model, metadata and budgets.
        previous: Original failed source, never modified.
    """
    if committed(config):
        return
    state = read_state(previous, config)
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        raise ValueError("Export OPENAI_API_KEY")
    prepare(config, previous, state)
    model, client, transport = await live_resources(config, exported_key=key)
    transport.attempts = state.attempts
    transport.attempt_observer = lambda count: atomic_json(config.audit_dir / "api-attempts.json", {"attempts": count})
    runner = DocumentRunner(config)
    runner.calls = state.sequence
    deps = AgentDependencies(config, runner, r_executions=state.r_calls, repairs=state.repairs)
    agent = build(model, (config.project_root / "prompts/system.txt").read_text())
    started = time.monotonic()
    try:
        await run_with_audit(agent, None, deps, history=state.history, usage=state.usage)
        freeze(config, deps.checked_hashes, runner.family, exploration(config), hashes)
        recovery_record(config, state, started, transport, "ok")
    except BaseException as error:
        recovery_record(config, state, started, transport, "failed", str(error))
        raise
    finally:
        await client.close()


def main():
    """Require explicit source and new destination; credentials are exported only."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--previous", type=Path, required=True)
    args = parser.parse_args()
    try:
        asyncio.run(execute_recovery(load_session(args.session), args.previous.resolve()))
    except Exception:
        raise SystemExit("Recovery failed; inspect the source audit. No automatic budget reset.") from None


if __name__ == "__main__":
    main()
