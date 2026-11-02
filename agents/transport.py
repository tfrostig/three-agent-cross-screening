"""Count physical API attempts rather than only model-loop requests.

A single session owns this transport and its attempt budget. The allowlist is
HTTPS POST /v1/responses on api.openai.com; SDK retries are disabled separately.
The transport is not used for the standalone model-availability preflight."""

import asyncio

import httpx


class CountedTransport(httpx.AsyncBaseTransport):
    """Session-owned transport restricting destinations and counting retries.

    Attributes:
        limit: Maximum physical outbound attempts in the whole session.
        retries: Maximum extra attempts per individual request.
        attempts: Number of physical attempts already started.
        transport: Owned httpx backend, with its own retries disabled by default.
    """

    def __init__(self, limit: int, retries: int = 2, transport=None):
        """Configure a shared physical-request budget for one model session.

        Args:
            limit: Maximum total outbound attempts, including transient retries.
            retries: Additional retries per request, still bounded by limit.
            transport: Optional async transport used by deterministic HTTP tests.
        """
        self.limit = limit
        self.retries = retries
        self.attempts = 0
        self.transport = transport or httpx.AsyncHTTPTransport(retries=0)

    async def handle_async_request(self, request):
        """Send only HTTPS POST /v1/responses to api.openai.com.

        Args:
            request: httpx request whose body can be replayed for bounded retries.

        Returns:
            Response from the underlying transport. Retries transport errors and
            HTTP 408/409/429/500/502/503/504; HTTP 520 is not retried here.

        Raises:
            RuntimeError: Destination/endpoint is unsupported or the budget is spent.
        """
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
        """Release the owned underlying HTTP transport.
        """
        await self.transport.aclose()
