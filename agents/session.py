"""Execute one isolated design session launched by the trusted R pipeline.

The controller creates fresh histories, dependencies, runner, reference snapshot,
and client per session. It records partial audits, checks final artifact hashes,
and publishes frozen copies. Target evaluation remains exclusively in R."""

import argparse
import asyncio
import dataclasses
import json
import time
from pathlib import Path

import httpx
from openai import AsyncOpenAI
from pydantic_ai import UsageLimits
from pydantic_ai.models.openai import OpenAIResponsesModel
from pydantic_ai.providers.openai import OpenAIProvider

from agents.artifacts import freeze_design
from agents.credentials import read_api_key
from agents.factory import build_agent
from agents.models import AgentDependencies, SessionConfig
from agents.offline import offline_model
from agents.prompts import load_prompts, user_prompt
from agents.references import ReferenceLibrary
from agents.runner import RRunner
from agents.transport import CountedTransport


def load_session(path: Path) -> SessionConfig:
    """Read a trusted R-controller manifest and prepare session directories.

    Args:
        path: Host-private JSON containing source paths, budgets, and task metadata.

    Returns:
        SessionConfig with resolved paths; creates work/audit directories.
    """
    raw = json.loads(path.read_text(encoding="utf-8"))
    for name in ("input_dir", "workspace", "audit_dir", "project_root"):
        raw[name] = Path(raw[name]).resolve()
    if raw.get("reference_pack") is not None:
        raw["reference_pack"] = Path(raw["reference_pack"]).resolve()
    config = SessionConfig(**raw)
    config.workspace.mkdir(parents=True, exist_ok=True)
    config.workspace.chmod(0o777)
    config.audit_dir.mkdir(parents=True, exist_ok=True)
    return config


async def live_resources(config):
    """Create one Responses model, owned client, and counted transport.

    Args:
        config: SessionConfig with an explicit model ID and OpenAI budgets.

    Returns:
        Tuple of model, AsyncOpenAI client, and CountedTransport. The caller owns
        client cleanup; SDK retries are disabled so physical attempts are counted.
    """
    key = read_api_key(config.project_root)
    if not config.model:
        raise ValueError("Configure an explicit OpenAI model")
    transport = CountedTransport(config.openai["request_limit"], config.openai["transient_retries"])
    http_client = httpx.AsyncClient(transport=transport)
    client = AsyncOpenAI(api_key=key, max_retries=0, http_client=http_client,
                         timeout=config.openai["api_timeout_seconds"])
    model = OpenAIResponsesModel(config.model, provider=OpenAIProvider(openai_client=client))
    return model, client, transport


async def execute(config: SessionConfig, offline: bool) -> dict:
    """Run one source-only design session and freeze the checked artifacts.

    Args:
        config: Independent session configuration; contains no latent effects.
        offline: Use the deterministic provider instead of a live OpenAI model.

    Returns:
        Success summary with duration, retained usage, and frozen hashes. Writes
        prompt/reference/session audits; exceptions propagate to the CLI handler.
    """
    started = time.monotonic()
    client = transport = None
    references = ReferenceLibrary.load(config.reference_pack or config.project_root / "references/agent-pack",
                                       config.reference_digest)
    if offline:
        model = offline_model(with_references=True)
    else:
        model, client, transport = await live_resources(config)
    system, developer = load_prompts(config.project_root, references)
    prompt = user_prompt(config)
    write_audit(config, "prompts.json", {"system": system, "developer": developer, "user": prompt})
    write_audit(config, "references.json", references.audit_record())
    deps = AgentDependencies(config, RRunner(config), references=references)
    agent = build_agent(model, system, developer)
    try:
        result = await run_with_audit(agent, prompt, deps)
        frozen = freeze_design(config.workspace, config.workspace.parent / "frozen",
                               result.output, deps.checked_hashes)
        usage = result.usage() if callable(result.usage) else result.usage
        summary = {"status": "ok", "mode": "offline_fixture" if offline else "live",
                   "model": config.model, "session_id": config.session_id,
                   "duration_seconds": time.monotonic() - started,
                   "physical_api_attempts": transport.attempts if transport else 0,
                   "usage": dataclasses.asdict(usage), "frozen": frozen}
        write_audit(config, "session.json", summary)
        return summary
    finally:
        if client is not None:
            await client.close()


async def run_with_audit(agent, prompt, deps):
    """Run with an empty history and persist exchanges after each graph node.

    Args:
        agent: Fresh PydanticAI agent with typed dependencies and output.
        prompt: Session-specific dimensions, criterion, level, and task.
        deps: State owned by this session alone.

    Returns:
        Completed run result; partial messages are also persisted on failure.
    """
    config = deps.config
    settings = {"openai_store": False, "parallel_tool_calls": False,
                "max_tokens": config.openai["max_output_tokens"]}
    limits = UsageLimits(request_limit=config.openai["request_limit"],
                         tool_calls_limit=config.limits["tool_calls_limit"])
    async with agent.iter(prompt, deps=deps, message_history=[], model_settings=settings,
                          usage_limits=limits) as run:
        try:
            async for _ in run:
                (config.audit_dir / "messages.json").write_bytes(run.all_messages_json())
        finally:
            (config.audit_dir / "messages.json").write_bytes(run.all_messages_json())
        return run.result


def write_audit(config, name, value):
    """Serialize controller metadata outside the agent-visible mounts.

    Args:
        config: SessionConfig identifying the audit directory.
        name: Controller-chosen JSON filename, never an arbitrary model path.
        value: JSON-serializable metadata; unsupported scalar values use str().
    """
    (config.audit_dir / name).write_text(json.dumps(value, indent=2, default=str), encoding="utf-8")


def main():
    """Run the single-session CLI invoked by R/designs.R.

    Reads --session FILE and optional --offline. On an execution failure, records
    failed session metadata and exits with a generic message. Never used to run
    a complete scenario directly; the R pipeline controls freeze/transfer order.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    config = load_session(args.session)
    try:
        asyncio.run(execute(config, args.offline))
    except Exception as error:
        write_audit(config, "session.json", {"status": "failed", "error": str(error),
                                           "mode": "offline_fixture" if args.offline else "live"})
        raise SystemExit("Agent session failed; see its audit/session.json") from None


if __name__ == "__main__":
    main()
