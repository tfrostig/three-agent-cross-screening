import asyncio

import httpx
import pytest

from agents.transport import CountedTransport


def test_physical_attempt_budget_includes_transient_retries(monkeypatch):
    calls = []

    async def respond(request):
        calls.append(request)
        return httpx.Response(503, request=request)

    async def no_delay(_):
        pass

    monkeypatch.setattr("agents.transport.asyncio.sleep", no_delay)
    transport = CountedTransport(2, retries=2, transport=httpx.MockTransport(respond))
    request = httpx.Request("POST", "https://api.openai.com/v1/responses", json={})
    with pytest.raises(RuntimeError, match="limit"):
        asyncio.run(transport.handle_async_request(request))
    assert len(calls) == 2
    assert transport.attempts == 2


def test_transport_rejects_arbitrary_destinations():
    transport = CountedTransport(16)
    request = httpx.Request("POST", "https://example.com/v1/responses")
    with pytest.raises(RuntimeError, match="destination"):
        asyncio.run(transport.handle_async_request(request))
