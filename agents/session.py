"""Run one isolated design session with PydanticAI."""

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
    """Load a host-private input manifest that contains no simulation truth."""
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
    """Create an explicit model with bounded transport and no SDK retries."""
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
    """Run one independent agent, then freeze its validated artifacts."""
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
    """Persist the local conversation after each node, including failed runs."""
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
    """Write controller-owned records outside the agent mount."""
    (config.audit_dir / name).write_text(json.dumps(value, indent=2, default=str), encoding="utf-8")


def main():
    """Parse a single-session invocation from the trusted R pipeline."""
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
