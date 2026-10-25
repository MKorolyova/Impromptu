// Shapes for Gemini's generateContent REST API. Only fields this app uses are listed.

// Gemini's OpenAPI-style schema subset for structured output.
export type GeminiSchema =
  | { type: "STRING"; enum?: string[]; description?: string }
  | { type: "NUMBER" | "INTEGER" | "BOOLEAN"; description?: string }
  | { type: "ARRAY"; items: GeminiSchema }
  | { type: "OBJECT"; properties: Record<string, GeminiSchema>; required?: string[] };

export type GeminiPart = { text: string };

export type GeminiGenerateContentRequest = {
  systemInstruction?: { parts: GeminiPart[] };
  contents: { role: "user" | "model"; parts: GeminiPart[] }[];
  generationConfig?: {
    temperature?: number;
    responseMimeType?: "application/json" | "text/plain";
    responseSchema?: GeminiSchema;
  };
};

export type GeminiGenerateContentResponse = {
  candidates?: {
    content?: { parts?: GeminiPart[] };
    finishReason?: string;
  }[];
  promptFeedback?: { blockReason?: string };
};

export type GeminiErrorBody = {
  error?: { code: number; message: string; status: string };
};
