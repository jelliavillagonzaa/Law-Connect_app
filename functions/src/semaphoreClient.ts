export type SemaphoreSendResult = {
  providerMessageId: string;
  networkStatus: string;
  rawResponse?: string;
};

type SemaphoreRow = {
  message_id?: number;
  status?: string;
  message?: string;
};

export function toSemaphoreNumber(e164: string): string {
  if (e164.startsWith("+63")) {
    return "0" + e164.slice(3);
  }
  return e164.replace("+", "");
}

function parseSemaphoreRows(text: string): SemaphoreRow[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`Semaphore invalid JSON: ${text.slice(0, 200)}`);
  }
  if (Array.isArray(parsed)) {
    if (parsed.length === 0) {
      throw new Error(`Semaphore empty response: ${text.slice(0, 200)}`);
    }
    return parsed as SemaphoreRow[];
  }
  if (parsed && typeof parsed === "object") {
    return [parsed as SemaphoreRow];
  }
  throw new Error(`Semaphore unexpected response: ${text.slice(0, 200)}`);
}

function assertSemaphoreAccepted(rows: SemaphoreRow[]): SemaphoreSendResult {
  const first = rows[0];
  const st = String(first.status || "").toLowerCase();
  const detail =
    typeof first.message === "string" ? first.message.trim() : "";

  if (st === "failed") {
    throw new Error(
      detail ||
        "Semaphore rejected the message (status Failed). Check credits, sender name approval, and phone number.",
    );
  }

  if (first.message_id == null || Number.isNaN(Number(first.message_id))) {
    throw new Error(
      detail ||
        "Semaphore did not return a message_id (SMS was not queued). Check SEMAPHORE_API_KEY and account credits at https://semaphore.co",
    );
  }

  return {
    providerMessageId: String(first.message_id),
    networkStatus: st || "unknown",
  };
}

async function postSemaphore(
  path: "messages" | "otp",
  params: URLSearchParams,
): Promise<SemaphoreSendResult> {
  const res = await fetch(`https://api.semaphore.co/api/v4/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Semaphore HTTP ${res.status}: ${text.slice(0, 300)}`);
  }
  const rows = parseSemaphoreRows(text);
  const result = assertSemaphoreAccepted(rows);
  return { ...result, rawResponse: text.slice(0, 500) };
}

function isSenderRelatedError(msg: string): boolean {
  const m = msg.toLowerCase();
  return (
    m.includes("sender") ||
    m.includes("sendername") ||
    m.includes("sender name")
  );
}

/** Standard SMS route (bulk/general notifications). */
export async function sendViaSemaphore(opts: {
  apiKey: string;
  to: string;
  body: string;
  senderName?: string;
}): Promise<SemaphoreSendResult> {
  const build = (senderName?: string) => {
    const params = new URLSearchParams();
    params.set("apikey", opts.apiKey.trim());
    params.set("number", toSemaphoreNumber(opts.to));
    params.set("message", opts.body.trim().slice(0, 1500));
    const sn = senderName?.trim();
    if (sn) params.set("sendername", sn.slice(0, 11));
    return params;
  };

  try {
    return await postSemaphore("messages", build(opts.senderName));
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (opts.senderName?.trim() && isSenderRelatedError(msg)) {
      return await postSemaphore("messages", build(undefined));
    }
    throw e;
  }
}

/** Dedicated OTP route (better delivery on PH networks). */
export async function sendViaSemaphoreOtp(opts: {
  apiKey: string;
  to: string;
  body: string;
  code: string;
  senderName?: string;
}): Promise<SemaphoreSendResult> {
  const build = (senderName?: string) => {
    const params = new URLSearchParams();
    params.set("apikey", opts.apiKey.trim());
    params.set("number", toSemaphoreNumber(opts.to));
    params.set("message", opts.body.trim().slice(0, 1500));
    params.set("code", opts.code.trim());
    const sn = senderName?.trim();
    if (sn) params.set("sendername", sn.slice(0, 11));
    return params;
  };

  try {
    return await postSemaphore("otp", build(opts.senderName));
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (opts.senderName?.trim() && isSenderRelatedError(msg)) {
      return await postSemaphore("otp", build(undefined));
    }
    throw e;
  }
}
