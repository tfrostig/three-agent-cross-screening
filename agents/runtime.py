"""Shared provider lifecycle and audit helpers for the current design agents.

Credentials are accepted only as an exported key supplied by the controller.
This module never opens credential files or defines a separate agent protocol.
"""

import json
from pathlib import Path

import httpx
from openai import AsyncOpenAI
from pydantic_ai import UsageLimits
from pydantic_ai.models.openai import OpenAIResponsesModel
from pydantic_ai.providers.openai import OpenAIProvider

from agents.models import SessionConfig
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
    config = SessionConfig(**raw)
    config.workspace.mkdir(parents=True, exist_ok=True)
    config.workspace.chmod(0o777)
    config.audit_dir.mkdir(parents=True, exist_ok=True)
    return config


async def live_resources(config, *, exported_key: str):
    """Create one Responses model, owned client, and counted transport.

    Args:
        config: SessionConfig with an explicit model ID and OpenAI budgets.
        exported_key: Nonempty key passed in memory by the trusted controller.

    Returns:
        Tuple of model, AsyncOpenAI client, and CountedTransport. The caller owns
        client cleanup; SDK retries are disabled so physical attempts are counted.
    """
    key = exported_key.strip()
    if not key:
        raise ValueError("Export OPENAI_API_KEY")
    if not config.model:
        raise ValueError("Configure an explicit OpenAI model")
    transport = CountedTransport(config.openai["request_limit"], config.openai["transient_retries"])
    http_client = httpx.AsyncClient(transport=transport)
    client = AsyncOpenAI(api_key=key, max_retries=0, http_client=http_client,
                         timeout=config.openai["api_timeout_seconds"])
    model = OpenAIResponsesModel(config.model, provider=OpenAIProvider(openai_client=client))
    return model, client, transport


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
