"""Verify current tools and stateless Responses requests with a mock HTTP provider."""

import asyncio
import json

import httpx
from openai import AsyncOpenAI
from pydantic_ai.models.openai import OpenAIResponsesModel
from pydantic_ai.providers.openai import OpenAIProvider

from agents.document import Submission, build
from agents.document_state import fixture_report
from agents.models import AgentDependencies
from tests.python.helpers import FakeRunner, config_for


def test_responses_adapter_preserves_current_stateless_contract(tmp_path):
    """Exercise exploration, artifact writes and typed finalization over mock HTTP."""
    payloads = []

    async def respond(request):
        payloads.append(json.loads(request.content))
        step = len(payloads)
        names = ["run_r", "write_artifact_file", "write_artifact_file", "finalize_design"]
        arguments = [{"code": "cat(dim(exposed))"}, {"path": "analysis.R", "content": "fixture"},
                     {"path": "report.md", "content": fixture_report()},
                     {"script_file": "analysis.R", "report_file": "report.md"}]
        body = {"id": f"resp_fixture_{step}", "object": "response", "created_at": 1,
                "status": "completed", "model": "gpt-6.1-sol", "output": [{
                    "type": "function_call", "id": f"fc_{step}", "call_id": f"call_{step}",
                    "name": names[step-1], "arguments": json.dumps(arguments[step-1])}],
                "usage": {"input_tokens": 20, "output_tokens": 10, "total_tokens": 30}}
        return httpx.Response(200, json=body, request=request)

    async def run():
        config = config_for(tmp_path)
        client = AsyncOpenAI(api_key="synthetic-fixture-key", max_retries=0,
                             http_client=httpx.AsyncClient(transport=httpx.MockTransport(respond)))
        model = OpenAIResponsesModel(config.model, provider=OpenAIProvider(openai_client=client))
        try:
            return await build(model, "current-scientific-instructions").run("own-marker",
                deps=AgentDependencies(config, FakeRunner()), model_settings={"openai_store": False,
                    "parallel_tool_calls": False, "max_tokens": 8192})
        finally:
            await client.close()

    result = asyncio.run(run())
    assert result.output == Submission(script_file="analysis.R", report_file="report.md")
    assert len(payloads) == 4
    assert all(p["model"] == "gpt-6.1-sol" and p["store"] is False for p in payloads)
    assert all(p.get("parallel_tool_calls") is False and "previous_response_id" not in p and "conversation" not in p for p in payloads)
    assert {t["name"] for t in payloads[0]["tools"]} == {"run_r", "write_artifact_file", "finalize_design"}
    assert all(p["max_output_tokens"] == 8192 for p in payloads)
