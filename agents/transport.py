"""Count physical HTTP attempts independently of agent-loop usage."""

import asyncio

import httpx


class CountedTransport(httpx.AsyncBaseTransport):
    """Restrict provider destinations and bound transient retries."""

    def __init__(self, limit: int, retries: int = 2, transport=None):
        self.limit = limit
        self.retries = retries
        self.attempts = 0
        self.transport = transport or httpx.AsyncHTTPTransport(retries=0)

    async def handle_async_request(self, request):
        """Send one Responses request with a bounded physical-attempt budget."""
        if request.url.host != "api.openai.com" or request.url.scheme != "https":
            raise RuntimeError("Unexpected provider destination")
        if request.method != "POST" or request.url.path != "/v1/responses":
            raise RuntimeError("Only the Responses endpoint is permitted")
        await request.aread()
        for retry in range(self.retries + 1):
            if self.attempts >= self.limit:
                raise RuntimeError("Physical API-attempt limit reached")
            self.attempts += 1
            try:
                response = await self.transport.handle_async_request(request)
            except httpx.TransportError:
                if retry == self.retries:
                    raise
            else:
                if response.status_code not in {408, 409, 429, 500, 502, 503, 504}:
                    return response
                if retry == self.retries:
                    return response
                await response.aclose()
            await asyncio.sleep(min(2 ** retry, 4))
        raise RuntimeError("Retry budget exhausted")

    async def aclose(self):
        """Close the underlying transport."""
        await self.transport.aclose()
