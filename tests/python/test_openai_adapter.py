import asyncio
import json
from dataclasses import replace

import httpx
from openai import AsyncOpenAI
from pydantic_ai.models.openai import OpenAIResponsesModel
from pydantic_ai.providers.openai import OpenAIProvider

from agents.factory import build_agent
from agents.models import AgentDependencies
from agents.references import ReferenceLibrary
from tests.python.test_agents import FakeRunner, config_for, manifest, seed_artifacts


def test_responses_adapter_preserves_model_and_stateless_tool_contract(tmp_path):
    payloads = []

    async def respond(request):
        payload = json.loads(request.content)
        payloads.append(payload)
        step = len(payloads)
        names = ["read_reference", "run_r", "check_design", "finalize_design"]
        arguments = [{"reference_id": "two-team"}, {"code": "cat(dim(exposed))"}, {}, manifest().model_dump()]
        body = {"id": f"resp_fixture_{step}", "object": "response", "created_at": 1,
                "status": "completed", "model": "gpt-6.1-sol", "output": [{
                    "type": "function_call", "id": f"fc_{step}", "call_id": f"call_{step}",
                    "name": names[step - 1], "arguments": json.dumps(arguments[step - 1])}],
                "usage": {"input_tokens": 20, "output_tokens": 10, "total_tokens": 30}}
        return httpx.Response(200, json=body, request=request)

    async def run():
        config = config_for(tmp_path)
        seed_artifacts(config.workspace)
        client = AsyncOpenAI(api_key="synthetic-fixture-key", max_retries=0,
                             http_client=httpx.AsyncClient(transport=httpx.MockTransport(respond)))
        model = OpenAIResponsesModel(config.model, provider=OpenAIProvider(openai_client=client))
        agent = build_agent(model, "system", "instructions")
        try:
            references = ReferenceLibrary.load(config.project_root / "references/agent-pack")
            return await agent.run("own-marker", deps=AgentDependencies(config, FakeRunner(), references=references),
                                    model_settings={"openai_store": False, "parallel_tool_calls": False,
                                                    "max_tokens": 8192})
        finally:
            await client.close()

    result = asyncio.run(run())
    assert result.output == manifest()
    assert len(payloads) == 4
    assert all(p["model"] == "gpt-6.1-sol" and p["store"] is False for p in payloads)
    assert all(p.get("parallel_tool_calls") is False for p in payloads)
    assert all("previous_response_id" not in p and "conversation" not in p for p in payloads)
    assert {t["name"] for t in payloads[0]["tools"]} == {
        "run_r", "read_reference", "write_artifact_file", "check_design", "finalize_design"}
    assert all(p["max_output_tokens"] == 8192 for p in payloads)
    tools = {t["name"]: t for t in payloads[0]["tools"]}
    assert "Matching column names" in tools["run_r"]["description"]
    assert "Row indices do not indicate matched" in tools["run_r"]["description"]
    assert "source_file" not in tools["read_reference"]["parameters"]["properties"]
    assert "Two-team exploration" in json.dumps(payloads[1]["input"])
