/** Third-party Gmail / shopping / product mail that leaked in as a court notice. */

export function isOutOfSystemCourtNoticeTitle(title: unknown): boolean {
  const t = String(title ?? "").toLowerCase().trim();
  if (!t) return false;
  return (
    t === "new court notice" ||
    (t.startsWith("new court notice") && !t.includes("court hearings"))
  );
}

export function isOutOfSystemPumpedNoticeText(raw: unknown): boolean {
  const t = String(raw ?? "").toLowerCase();
  if (!t) return false;
  const markers = [
    "ollama",
    "canva",
    "google account data",
    "shared some google account",
    "you shared some google",
    "your order has been delivered",
    "order has been delivered",
    "thanks for shopping with us",
    "thanks for shopping",
    "transparent pricing",
    "your package has been delivered",
    "track your order",
  ];
  return markers.some((m) => t.includes(m));
}

export function isOutOfSystemPumpedNotice(
  data: Record<string, unknown>,
): boolean {
  if (isOutOfSystemCourtNoticeTitle(data.title)) return true;
  const blob = [
    data.title,
    data.message,
    data.body,
    data.summary,
    data.subject,
    data.fullText,
    data.description,
    data.caseTitle,
    data.caseNo,
  ]
    .map((v) => String(v ?? ""))
    .join("\n");
  return isOutOfSystemPumpedNoticeText(blob);
}
