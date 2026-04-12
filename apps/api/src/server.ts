import Fastify from "fastify";

const server = Fastify({
  logger: true,
});

const OPENAI_API_BASE_URL = "https://api.openai.com/v1";
const STYLE_MODEL = process.env.OPENAI_STYLE_MODEL ?? "gpt-5-mini";
const REALTIME_MODEL = process.env.OPENAI_REALTIME_MODEL ?? "gpt-realtime";
const REALTIME_VOICE = process.env.OPENAI_REALTIME_VOICE ?? "marin";

const STYLE_INSTRUCTIONS = [
  "You are Barber AI, a concise hairstyle consultant inside a live AR try-on app.",
  "Give practical advice about whether the visible hairstyle fits the user's face and look.",
  "If the image quality is weak, say what you can and cannot infer.",
  "Do not identify the person. Do not make sensitive demographic guesses.",
  "Keep answers under 90 words unless the user asks for detail.",
].join(" ");

type StyleAdviceRequest = {
  message?: string;
  imageBase64?: string;
  activeLensId?: string;
  activeStyle?: string;
  hairColor?: string;
};

type RealtimeSdpRequest = {
  sdp?: string;
  imageBase64?: string;
  activeLensId?: string;
  activeStyle?: string;
  hairColor?: string;
};

server.get("/health", async () => {
  return { status: "ok" };
});

server.post<{ Body: StyleAdviceRequest }>("/ai/style-advice", async (request, reply) => {
  const apiKey = requireOpenAIKey();
  const message = request.body.message?.trim() || "Does this hairstyle fit me?";
  const content: Array<Record<string, unknown>> = [
    {
      type: "input_text",
      text: [
        message,
        formatContext(request.body),
      ].filter(Boolean).join("\n\n"),
    },
  ];

  if (request.body.imageBase64) {
    content.push({
      type: "input_image",
      image_url: `data:image/jpeg;base64,${request.body.imageBase64}`,
      detail: "low",
    });
  }

  const response = await fetch(`${OPENAI_API_BASE_URL}/responses`, {
    method: "POST",
    headers: openAIHeaders(apiKey),
    body: JSON.stringify({
      model: STYLE_MODEL,
      instructions: STYLE_INSTRUCTIONS,
      input: [
        {
          role: "user",
          content,
        },
      ],
      max_output_tokens: 240,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    request.log.error({ status: response.status, errorText }, "OpenAI style advice request failed");
    return reply.code(502).send({ error: "style_advice_failed" });
  }

  const data = await response.json() as Record<string, unknown>;
  return { message: extractOutputText(data) || "I could not generate advice for that frame." };
});

server.post<{ Body: RealtimeSdpRequest }>("/ai/realtime/sdp", async (request, reply) => {
  const apiKey = requireOpenAIKey();
  const sdp = request.body.sdp?.trim();

  if (!sdp) {
    return reply.code(400).send({ error: "missing_sdp" });
  }

  const clientSecret = await createRealtimeClientSecret(apiKey, request.body);
  const response = await fetch(`${OPENAI_API_BASE_URL}/realtime/calls`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${clientSecret}`,
      "Content-Type": "application/sdp",
    },
    body: sdp,
  });

  const answerSdp = await response.text();
  if (!response.ok) {
    request.log.error({ status: response.status, answerSdp }, "OpenAI realtime SDP exchange failed");
    return reply.code(502).send({ error: "realtime_sdp_failed" });
  }

  reply.type("application/sdp");
  return answerSdp;
});

async function createRealtimeClientSecret(apiKey: string, context: RealtimeSdpRequest): Promise<string> {
  const response = await fetch(`${OPENAI_API_BASE_URL}/realtime/client_secrets`, {
    method: "POST",
    headers: openAIHeaders(apiKey),
    body: JSON.stringify({
      session: {
        type: "realtime",
        model: REALTIME_MODEL,
        instructions: [
          STYLE_INSTRUCTIONS,
          "This is a voice conversation. Answer naturally and briefly.",
          formatContext(context),
        ].filter(Boolean).join("\n\n"),
        audio: {
          output: {
            voice: REALTIME_VOICE,
          },
        },
      },
    }),
  });

  const data = await response.json() as Record<string, unknown>;
  if (!response.ok) {
    server.log.error({ status: response.status, data }, "OpenAI realtime client secret request failed");
    throw new Error("realtime_client_secret_failed");
  }

  const directValue = data.value;
  if (typeof directValue === "string") {
    return directValue;
  }

  const nestedSecret = data.client_secret;
  if (nestedSecret && typeof nestedSecret === "object" && "value" in nestedSecret) {
    const nestedValue = (nestedSecret as { value?: unknown }).value;
    if (typeof nestedValue === "string") {
      return nestedValue;
    }
  }

  server.log.error({ data }, "OpenAI realtime client secret response had no usable secret");
  throw new Error("missing_realtime_client_secret");
}

function requireOpenAIKey(): string {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set");
  }

  return apiKey;
}

function openAIHeaders(apiKey: string): Record<string, string> {
  return {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  };
}

function formatContext(context: Pick<StyleAdviceRequest, "activeLensId" | "activeStyle" | "hairColor">): string {
  const lines = [
    context.activeStyle ? `Active hairstyle: ${context.activeStyle}` : "",
    context.activeLensId ? `Active Lens ID: ${context.activeLensId}` : "",
    context.hairColor ? `Selected hair color: ${context.hairColor}` : "",
  ].filter(Boolean);

  return lines.length ? `AR context:\n${lines.join("\n")}` : "";
}

function extractOutputText(response: Record<string, unknown>): string | undefined {
  if (typeof response.output_text === "string") {
    return response.output_text;
  }

  const output = response.output;
  if (!Array.isArray(output)) {
    return undefined;
  }

  return output
    .flatMap((item) => {
      if (!item || typeof item !== "object" || !("content" in item)) {
        return [];
      }

      const content = (item as { content?: unknown }).content;
      if (!Array.isArray(content)) {
        return [];
      }

      return content
        .map((part) => {
          if (!part || typeof part !== "object" || !("text" in part)) {
            return "";
          }

          const text = (part as { text?: unknown }).text;
          return typeof text === "string" ? text : "";
        })
        .filter(Boolean);
    })
    .join("\n")
    .trim();
}

const start = async () => {
  try {
    await server.listen({
      port: Number(process.env.PORT ?? 3000),
      host: "0.0.0.0",
    });
  } catch (error) {
    server.log.error(error);
    process.exit(1);
  }
};

void start();
