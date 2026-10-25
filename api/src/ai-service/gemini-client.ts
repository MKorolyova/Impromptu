import { env } from "@/env";
import type {
  GeminiErrorBody,
  GeminiGenerateContentRequest,
  GeminiGenerateContentResponse,
  GeminiSchema,
} from "@/types/gemini";

const GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models";
const REQUEST_TIMEOUT_MS = 15_000;

export class GeminiError extends Error {
  readonly status: number | null;

  constructor(message: string, status: number | null = null) {
    super(message);
    this.name = "GeminiError";
    this.status = status;
  }
}

export function isGeminiConfigured(): boolean {
  return env.GEMINI_API_KEY !== null;
}

// Asks Gemini for JSON matching `schema` and returns it parsed. The caller still validates the values.
export async function generateGeminiJson<T>(input: {
  system: string;
  prompt: string;
  schema: GeminiSchema;
}): Promise<T> {
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw new GeminiError("GEMINI_API_KEY is not set");

  const body: GeminiGenerateContentRequest = {
    systemInstruction: { parts: [{ text: input.system }] },
    contents: [{ role: "user", parts: [{ text: input.prompt }] }],
    generationConfig: { temperature: 0, responseMimeType: "application/json", responseSchema: input.schema },
  };

  const response = await fetch(`${GEMINI_API_URL}/${encodeURIComponent(env.GEMINI_MODEL)}:generateContent`, {
    method: "POST",
    // The key goes in a header, never in the URL.
    headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (!response.ok) {
    const error = (await response.json().catch(() => null)) as GeminiErrorBody | null;
    throw new GeminiError(error?.error?.message ?? `Gemini request failed (${response.status})`, response.status);
  }

  const result = (await response.json()) as GeminiGenerateContentResponse;
  const text = result.candidates?.[0]?.content?.parts?.map((part) => part.text).join("");
  if (!text) {
    const reason = result.promptFeedback?.blockReason ?? result.candidates?.[0]?.finishReason ?? "empty response";
    throw new GeminiError(`Gemini returned no content (${reason})`);
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new GeminiError("Gemini returned invalid JSON");
  }
}
