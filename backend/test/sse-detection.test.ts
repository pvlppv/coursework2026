import { describe, expect, it } from "vitest";
import { lineHasContentDelta } from "../src/lib/sse.js";

describe("lineHasContentDelta", () => {
  it("detects OpenAI-compatible content delta chunks", () => {
    expect(lineHasContentDelta('data: {"choices":[{"delta":{"content":"Hello"}}]}')).toBe(true);
  });

  it("ignores non-content SSE events", () => {
    expect(lineHasContentDelta(": ping")).toBe(false);
    expect(lineHasContentDelta("data: [DONE]")).toBe(false);
    expect(lineHasContentDelta('data: {"choices":[{"delta":{}}]}')).toBe(false);
    expect(lineHasContentDelta('data: {"choices":[{"delta":{"reasoning":"hidden"}}]}')).toBe(false);
  });
});
