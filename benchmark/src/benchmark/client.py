"""OpenRouter SSE streaming client with TTFT measurement.

Matches production settings exactly (see backend/src/http/app.ts:streamWithRetries
and backend/src/services/openrouter-service.ts):

  - stream: true
  - temperature: 1.0
  - max_completion_tokens: 1024
  - reasoning: { effort: "minimal", exclude: true }
  - provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } }

Why streaming: TTFT is the part of latency the user actually feels in the
Go Deeper conversational UI. Nielsen (1993) puts the "system feels responsive"
threshold at 1s. Both TTFT and total wall-clock time are recorded.

We do NOT send `usage: {include: true}` as a body field because OpenRouter's
production-shaped request uses standard usage-on-stream-end. Token counts
come from the final SSE chunk's `usage` field.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential


OPENROUTER_BASE = "https://openrouter.ai/api/v1"

# Production provider policy — matches backend/src/http/app.ts:513
PRODUCTION_PROVIDER_POLICY: dict[str, Any] = {
    "zdr": True,
    "sort": "latency",
    "preferred_max_latency": {"p90": 3},
}

# Production reasoning policy — matches backend/src/http/app.ts:550
PRODUCTION_REASONING_POLICY: dict[str, Any] = {
    "effort": "minimal",
    "exclude": True,
}


@dataclass
class StreamedCompletion:
    text: str
    ttft_ms: Optional[float]
    total_ms: float
    input_tokens: int
    output_tokens: int
    reasoning_tokens: int
    cached_input_tokens: int
    finish_reason: Optional[str]
    provider_name: Optional[str]
    openrouter_request_id: Optional[str]
    raw_chunks: list[dict[str, Any]] = field(default_factory=list)


class OpenRouterClient:
    def __init__(
        self,
        api_key: Optional[str] = None,
        timeout_s: float = 60.0,
        site_url: str = "https://github.com/popov-pavel/sotie-coursework",
        app_name: str = "sotie-benchmark",
    ) -> None:
        self.api_key = api_key or os.environ.get("OPENROUTER_API_KEY")
        if not self.api_key:
            raise RuntimeError(
                "OPENROUTER_API_KEY not set. Export it or pass api_key="
            )
        self.timeout_s = timeout_s
        self.site_url = site_url
        self.app_name = app_name

    def _headers(self) -> dict[str, str]:
        # Production uses X-OpenRouter-Title; OpenRouter also accepts X-Title.
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": self.site_url,
            "X-OpenRouter-Title": self.app_name,
        }

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=20),
        reraise=True,
    )
    def stream_completion(
        self,
        *,
        model: str,
        messages: list[dict[str, str]],
        temperature: float = 1.0,
        max_completion_tokens: int = 1024,
        reasoning: Optional[dict] = None,
        provider: Optional[dict] = None,
    ) -> StreamedCompletion:
        """Stream a chat completion, measuring TTFT and total latency.

        Defaults match production. Pass `reasoning=None` / `provider=None` to
        omit those fields entirely (some models do not accept reasoning).
        """
        body: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_completion_tokens": max_completion_tokens,
            "stream": True,
        }
        if reasoning is not None:
            body["reasoning"] = reasoning
        if provider is not None:
            body["provider"] = provider

        url = f"{OPENROUTER_BASE}/chat/completions"
        t0 = time.perf_counter()
        ttft_ms: Optional[float] = None
        text_parts: list[str] = []
        raw_chunks: list[dict[str, Any]] = []
        input_tokens = 0
        output_tokens = 0
        reasoning_tokens = 0
        cached_input_tokens = 0
        finish_reason: Optional[str] = None
        provider_name: Optional[str] = None
        request_id: Optional[str] = None

        with httpx.Client(timeout=self.timeout_s) as client:
            with client.stream("POST", url, headers=self._headers(), json=body) as r:
                r.raise_for_status()
                request_id = r.headers.get("x-request-id") or r.headers.get(
                    "openrouter-request-id"
                )
                for line in r.iter_lines():
                    if not line or not line.startswith("data: "):
                        continue
                    data = line[len("data: "):]
                    if data.strip() == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    raw_chunks.append(chunk)

                    if "provider" in chunk:
                        provider_name = chunk["provider"]

                    choices = chunk.get("choices") or []
                    if choices:
                        delta = choices[0].get("delta") or {}
                        content_piece = delta.get("content")
                        if content_piece:
                            if ttft_ms is None:
                                ttft_ms = (time.perf_counter() - t0) * 1000.0
                            text_parts.append(content_piece)
                        fr = choices[0].get("finish_reason")
                        if fr:
                            finish_reason = fr

                    usage = chunk.get("usage")
                    if usage:
                        input_tokens = usage.get("prompt_tokens", input_tokens) or input_tokens
                        output_tokens = (
                            usage.get("completion_tokens", output_tokens) or output_tokens
                        )
                        details = usage.get("completion_tokens_details") or {}
                        reasoning_tokens = (
                            details.get("reasoning_tokens", reasoning_tokens) or reasoning_tokens
                        )
                        prompt_details = usage.get("prompt_tokens_details") or {}
                        cached_input_tokens = (
                            prompt_details.get("cached_tokens", cached_input_tokens)
                            or cached_input_tokens
                        )

        total_ms = (time.perf_counter() - t0) * 1000.0
        return StreamedCompletion(
            text="".join(text_parts),
            ttft_ms=ttft_ms,
            total_ms=total_ms,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            reasoning_tokens=reasoning_tokens,
            cached_input_tokens=cached_input_tokens,
            finish_reason=finish_reason,
            provider_name=provider_name,
            openrouter_request_id=request_id,
            raw_chunks=raw_chunks,
        )
