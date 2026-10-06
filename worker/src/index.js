/**
 * FlipStudy card generation Worker.
 *
 * Why this exists at all: the iPhone app must never carry Cloudflare
 * credentials — an .ipa is a zip file, and anyone who downloads it can read the
 * strings inside. So the app holds only a token it earned by redeeming a family
 * code, and this Worker is the only thing that can actually spend AI credits.
 *
 * Two endpoints:
 *   POST /v1/redeem    { code, device }  -> { token, label }
 *   POST /v1/generate  (Bearer token)    -> { cards } | { terms }
 *
 * Codes are stored hashed, so a dump of the KV namespace never reveals a
 * working code. Tokens are bound to one device id, which is what lets you
 * revoke a single phone without reissuing the whole family's code.
 */

/** JSON mode model. Swappable: every call goes through `runModel` below. */
const MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

/** Hard clamp on page text. A long scan is the expensive case, and an
 *  unbounded one is how a loop turns into a bill. */
const MAX_INPUT_CHARS = 6000;
const MAX_TOPIC_CHARS = 200;
/** Ceiling on how many items we will ever ask for, whatever the client sends. */
const MAX_COUNT = 30;
/** Room for a full page of cards. Comfortably above 30 cards of prose. */
const MAX_OUTPUT_TOKENS = 4096;

const CARDS_SCHEMA = {
  type: "object",
  properties: {
    cards: {
      type: "array",
      items: {
        type: "object",
        properties: {
          front: { type: "string" },
          back: { type: "string" },
        },
        required: ["front", "back"],
      },
    },
  },
  required: ["cards"],
};

const TERMS_SCHEMA = {
  type: "object",
  properties: {
    terms: { type: "array", items: { type: "string" } },
  },
  required: ["terms"],
};

// The instructions deliberately mirror FlipStudy/Services/AICardGenerator.swift.
// Two engines that read the same page should produce the same *kind* of cards;
// if these drift, a family member's decks stop looking like everyone else's.
const SYSTEM = {
  qa: `You turn raw text scanned from a page into accurate study flashcards. Read
the material, work out what it is teaching, and extract the question/answer
or term/definition pairs a student would actually want to memorize. Fix
obvious OCR slips when you're confident, keep answers short and correct, and
leave out page furniture like headers, page numbers, and stray fragments.
Never invent facts that aren't supported by the text. If the text has no
studiable content, return no cards.`,

  vocab: `You extract vocabulary from a page captured by OCR. The student already
chose these words — your job is to return them, not to teach them. Never
translate, define, or expand an item yourself, and never invent new ones.

If the page gives each word's translation or meaning beside it, return that
pairing exactly as the page wrote it. If the page is a plain list with nothing
beside each word, return the word with an empty back. Be strict about what
counts as vocabulary: app names, button labels, menu items, status-bar times
and numbers, page furniture and stray OCR fragments are never vocabulary, and a
garbled token you cannot confidently restore to a real word is dropped, not
kept.`,

  topic: `You are a helpful study assistant that writes clear, accurate flashcards.
Fronts are brief terms or questions. Backs are short, correct answers or
definitions. Avoid trick questions and keep the language age-appropriate.`,

  concepts: `You build English study lists for language learners. Always write in English,
no matter what language or country the topic mentions — that is only the
subject; a separate translator adds the other language afterward. Give the most
useful items first, follow the requested style exactly, and output nothing but
the English items — no translations, no numbering, no notes.`,
};

const STYLE_RULES = {
  phrases:
    "Each item MUST be a complete, natural English phrase or sentence of several words — never a single word.",
  words: "Each item is a single English word or a very short term.",
  sentenceStarters:
    "Each item MUST be a short English SENTENCE OPENER — the first few words a sentence commonly begins with, left unfinished so the learner can complete it. Two to four words each. Do NOT write complete sentences.",
};

// ---------------------------------------------------------------- utilities

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const fail = (code, status) => json({ error: code }, status);

/** Codes are compared by hash so the stored form is useless if leaked. */
export async function hashCode(code) {
  const normalized = code.trim().toUpperCase().replace(/\s|-/g, "");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function newToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

const today = () => new Date().toISOString().slice(0, 10);

/**
 * Count one request against the code's daily allowance. Returns false when the
 * code is already spent for the day. KV is eventually consistent, so a burst
 * can slip slightly over the cap — that is fine here: the cap exists to stop a
 * runaway or a leaked code, not to bill to the neuron.
 */
async function withinQuota(env, codeHash, limit) {
  const key = `use:${codeHash}:${today()}`;
  const used = parseInt((await env.USAGE.get(key)) || "0", 10);
  if (used >= limit) return false;
  // Expire a day after the day ends, so yesterday's counters clean themselves up.
  await env.USAGE.put(key, String(used + 1), { expirationTtl: 172800 });
  return true;
}

/** Resolve a Bearer token to its code record, or null. */
async function authenticate(request, env) {
  const header = request.headers.get("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return null;

  const bound = await env.TOKENS.get(`tok:${token}`, "json");
  if (!bound) return null;

  const record = await env.CODES.get(`code:${bound.codeHash}`, "json");
  if (!record || record.active === false) return null;

  return { ...bound, record };
}

async function runModel(env, system, user, schema) {
  const result = await env.AI.run(MODEL, {
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
    response_format: { type: "json_schema", json_schema: schema },
    // Workers AI defaults to a small output budget. A full page of cards blows
    // straight past it, and the reply comes back as JSON cut off mid-structure
    // — which fails to parse and surfaces as a mystifying "had a problem
    // making these cards". This is a ceiling, not a reservation: neurons are
    // billed on what the model actually generates.
    max_tokens: MAX_OUTPUT_TOKENS,
  });

  // Workers AI returns the structured payload under `response`, sometimes
  // already parsed and sometimes as a JSON string depending on the model.
  let payload = result?.response ?? result;
  if (typeof payload === "string") {
    try {
      payload = JSON.parse(payload);
    } catch {
      return null;
    }
  }
  return payload;
}

// ------------------------------------------------------------------ prompts

function buildPrompt(body) {
  const count = Math.min(parseInt(body.count, 10) || 12, MAX_COUNT);

  switch (body.mode) {
    case "qa": {
      const text = String(body.text || "").slice(0, MAX_INPUT_CHARS);
      if (!text.trim()) return null;
      return {
        system: SYSTEM.qa,
        schema: CARDS_SCHEMA,
        user: `Below is text captured from a page by OCR. Study it and create up to ${count} flashcards that capture the most useful facts, terms, and ideas a student should learn from it. Decide for yourself what the material is about; do not assume a subject. If the page already pairs terms with definitions or questions with answers, use those pairings. Otherwise, write a clear question or term for the front and a concise answer for the back. Ignore page numbers, headers, and other noise.\n\nPAGE TEXT:\n${text}`,
      };
    }

    case "vocab": {
      const text = String(body.text || "").slice(0, MAX_INPUT_CHARS);
      if (!text.trim()) return null;
      return {
        system: SYSTEM.vocab,
        schema: CARDS_SCHEMA,
        user: `Below is text captured by OCR from a vocabulary page or a screenshot of an app. Alongside the vocabulary it can contain interface junk: clock times, battery numbers, app and button names (like "Ask", "Search", "Send"), model or product names, navigation labels, and stray symbols. None of that is vocabulary — leave it out.\n\nList up to ${count} items the student wants to learn. For each one:\n- "front" is the word or phrase, exactly as written (fixing obvious OCR slips you can confidently restore). If it is garbled beyond recognition, leave the item out.\n- "back" is the translation or meaning THE PAGE ITSELF gives for it, exactly as written. If the page gives none, use an empty string.\n\nDo not translate, define or explain anything yourself — an empty back is correct when the page has no translation.\n\nOCR TEXT:\n${text}`,
      };
    }

    case "topic": {
      const topic = String(body.topic || "").slice(0, MAX_TOPIC_CHARS);
      if (!topic.trim()) return null;
      return {
        system: SYSTEM.topic,
        schema: CARDS_SCHEMA,
        user: `Create ${count} study flashcards about: ${topic}.\nEach card has a short prompt on the front and a concise answer on the back. Keep them factual and suitable for a student.`,
      };
    }

    case "concepts": {
      const topic = String(body.topic || "").slice(0, MAX_TOPIC_CHARS);
      if (!topic.trim()) return null;
      const rule = STYLE_RULES[body.style] || STYLE_RULES.phrases;
      return {
        system: SYSTEM.concepts,
        schema: TERMS_SCHEMA,
        user: `Study topic: ${topic}\n\nIn ENGLISH ONLY, list ${count} useful items to study for this topic. Ignore any language or country named in the topic — that only tells you the subject; you must still write in English. ${rule}\n\nNo numbering, no translations, no notes — English only.`,
      };
    }

    default:
      return null;
  }
}

// ------------------------------------------------------------------- routes

async function handleRedeem(request, env) {
  const body = await request.json().catch(() => null);
  if (!body?.code || !body?.device) return fail("bad_request", 400);

  const codeHash = await hashCode(String(body.code));
  const record = await env.CODES.get(`code:${codeHash}`, "json");
  if (!record || record.active === false) return fail("invalid_code", 403);

  const device = String(body.device).slice(0, 64);
  const devices = record.devices || [];

  // A family code is meant for a handful of phones. The cap is what stops one
  // forwarded code from quietly becoming a public API.
  if (!devices.includes(device)) {
    if (devices.length >= (record.deviceLimit ?? 5)) {
      return fail("device_limit", 409);
    }
    devices.push(device);
    await env.CODES.put(
      `code:${codeHash}`,
      JSON.stringify({ ...record, devices }),
    );
  }

  const token = newToken();
  await env.TOKENS.put(
    `tok:${token}`,
    JSON.stringify({ codeHash, device, issued: new Date().toISOString() }),
  );

  return json({ token, label: record.label || "FlipStudy Cloud" });
}

async function handleGenerate(request, env) {
  const auth = await authenticate(request, env);
  if (!auth) return fail("unauthorized", 401);

  const limit = auth.record.dailyRequests ?? parseInt(env.MAX_DAILY_REQUESTS || "50", 10);
  if (!(await withinQuota(env, auth.codeHash, limit))) {
    return fail("quota_exceeded", 429);
  }

  const body = await request.json().catch(() => null);
  if (!body) return fail("bad_request", 400);

  const prompt = buildPrompt(body);
  if (!prompt) return fail("bad_request", 400);

  let payload;
  try {
    payload = await runModel(env, prompt.system, prompt.user, prompt.schema);
  } catch (err) {
    // Never echo the model's raw error to the phone; it can carry internals.
    console.error("model_error", err?.message);
    return fail("model_error", 502);
  }
  if (!payload) return fail("model_error", 502);

  if (prompt.schema === CARDS_SCHEMA) {
    const cards = (payload.cards || [])
      .map((c) => ({
        front: String(c.front || "").trim(),
        back: String(c.back || "").trim(),
      }))
      .filter((c) => c.front);
    return json({ cards });
  }

  const terms = (payload.terms || [])
    .map((t) => String(t || "").trim())
    .filter(Boolean);
  return json({ terms });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }
    if (request.method !== "POST") return fail("not_found", 404);

    if (url.pathname === "/v1/redeem") return handleRedeem(request, env);
    if (url.pathname === "/v1/generate") return handleGenerate(request, env);

    return fail("not_found", 404);
  },
};
