export function lineHasContentDelta(line: string): boolean {
  if (!line.startsWith("data:")) {
    return false;
  }

  const payload = line.slice(5).trim();
  if (!payload || payload === "[DONE]") {
    return false;
  }

  try {
    const json = JSON.parse(payload) as { choices?: Array<{ delta?: { content?: unknown } }> };
    return json.choices?.some((choice) => typeof choice.delta?.content === "string" && choice.delta.content.length > 0) ?? false;
  } catch {
    return false;
  }
}
