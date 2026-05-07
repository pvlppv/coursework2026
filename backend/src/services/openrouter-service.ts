import type { Env } from "../config/env.js";
import { HttpError } from "../lib/errors.js";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface StreamRequest {
  messages: ChatMessage[];
  model?: string;
  stream: boolean;
  maxTokens: number;
  temperature: number;
  reasoning?: Record<string, unknown>;
  provider?: Record<string, unknown>;
  responseFormat?: Record<string, unknown>;
}

export class OpenRouterService {
  constructor(private readonly env: Env) {}

  async streamChatCompletion(request: StreamRequest, signal?: AbortSignal): Promise<Response> {
    const response = await this.fetchChatCompletion(request, signal);

    if (!response.ok) {
      throw new HttpError(mapOpenRouterStatus(response.status), "provider_error", "OpenRouter request failed", {
        providerStatus: response.status,
      });
    }

    if (!response.body) {
      throw new HttpError(502, "provider_empty_stream", "OpenRouter returned an empty stream");
    }

    return response;
  }

  async generateChatCompletion(request: Omit<StreamRequest, "stream">, signal?: AbortSignal): Promise<string> {
    const response = await this.fetchChatCompletion({ ...request, stream: false }, signal);

    if (!response.ok) {
      throw new HttpError(mapOpenRouterStatus(response.status), "provider_error", "OpenRouter request failed", {
        providerStatus: response.status,
      });
    }

    const json = (await response.json().catch(() => null)) as { choices?: Array<{ message?: { content?: unknown } }> } | null;
    const content = json?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      throw new HttpError(502, "provider_no_content", "OpenRouter returned no content");
    }

    return content.trim();
  }

  private async fetchChatCompletion(request: StreamRequest, signal?: AbortSignal): Promise<Response> {
    return fetch(`${this.env.OPENROUTER_BASE_URL}/chat/completions`, {
      method: "POST",
      signal,
      headers: {
        Authorization: `Bearer ${this.env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
        "HTTP-Referer": this.env.OPENROUTER_SITE_URL,
        "X-OpenRouter-Title": this.env.OPENROUTER_APP_NAME,
      },
      body: JSON.stringify({
        model: request.model ?? this.env.OPENROUTER_MODEL,
        messages: request.messages,
        stream: request.stream,
        temperature: request.temperature,
        max_completion_tokens: request.maxTokens,
        reasoning: request.reasoning,
        provider: request.provider,
        response_format: request.responseFormat,
      }),
    });
  }
}

function mapOpenRouterStatus(status: number): number {
  if (status === 401 || status === 403) return 502;
  if (status === 429) return 429;
  if (status >= 500) return 502;
  return 400;
}
