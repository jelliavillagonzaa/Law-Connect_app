/**
 * Real payment processing via Xendit (GCash, Maya, card, online banking).
 *
 * Flow (queue based, matches the rest of this codebase):
 *  1. Flutter writes a `payment_checkout_requests` doc (status: pending).
 *  2. {@link handlePaymentCheckoutRequest} reads the invoice server-side,
 *     creates a real Xendit Invoice (hosted checkout), a pending `payments`
 *     doc, and writes the hosted `checkoutUrl` back onto the request.
 *  3. The client opens `checkoutUrl` (the real GCash/bank authorization page),
 *     the customer pays real money to the firm's Xendit account.
 *  4. Xendit calls {@link handleXenditWebhook}; only THEN is the invoice
 *     balance updated and the `payments` doc marked `successful`.
 *
 * No money is ever "marked paid" without Xendit confirming a real charge.
 */
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { logger } from "firebase-functions";
import type {
  FirestoreEvent,
  QueryDocumentSnapshot,
} from "firebase-functions/v2/firestore";
import type { Request } from "firebase-functions/v2/https";
import type { Response } from "express";

const XENDIT_API = "https://api.xendit.co";

/** Runtime config resolved from secrets/params in `index.ts`. */
export interface XenditConfig {
  secretKey: string;
  webhookToken: string;
  successUrl: string;
  cancelUrl: string;
}

/**
 * Maps an app payment method id to Xendit Invoice `payment_methods` codes.
 * Returns an empty array when we should not restrict (show all channels).
 */
function xenditPaymentMethods(method: string): string[] {
  switch (method) {
    case "gcash":
      return ["GCASH"];
    case "maya":
      return ["PAYMAYA"];
    case "grab_pay":
      return ["GRABPAY"];
    case "debit_card":
    case "credit_card":
      return ["CREDIT_CARD"];
    case "online_banking":
      // Direct-debit / online banking channels (PH). Left to fallback if any
      // are not activated on the account.
      return ["DD_BPI", "DD_UBP", "DD_BDO_EPAY", "DD_RCBC", "DD_CHINABANK"];
    default:
      return [];
  }
}

function authHeader(secretKey: string): string {
  return "Basic " + Buffer.from(`${secretKey}:`).toString("base64");
}

/** Xendit PHP amounts are in pesos (not centavos). Keep up to 2 decimals. */
function toPesoAmount(pesos: number): number {
  return Math.round(pesos * 100) / 100;
}

/**
 * Handles a `payment_checkout_requests/{id}` create: builds a real Xendit
 * Invoice and returns the hosted payment URL on the request doc.
 */
export async function handlePaymentCheckoutRequest(
  event: FirestoreEvent<QueryDocumentSnapshot | undefined, { docId: string }>,
  cfg: XenditConfig,
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;
  const ref = snap.ref;
  const d = snap.data() as Record<string, unknown>;
  const status = String(d.status || "");
  if (status && status !== "pending") return;

  const db = admin.firestore();
  const fail = async (error: string) => {
    await ref.update({
      status: "failed",
      error,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.warn("xenditCheckout: failed", { docId: event.params.docId, error });
  };

  if (!cfg.secretKey) {
    await fail("Payment gateway not configured. Set the XENDIT_SECRET_KEY secret.");
    return;
  }

  const invoiceId = String(d.invoiceId || "");
  const clientId = String(d.clientId || "");
  const method = String(d.method || "gcash");
  const requestedAmount = Number(d.amount || 0);
  if (!invoiceId || !clientId) {
    await fail("Missing invoiceId or clientId.");
    return;
  }

  // Read the invoice server-side — never trust client-provided amounts.
  const invoiceSnap = await db.collection("invoices").doc(invoiceId).get();
  if (!invoiceSnap.exists) {
    await fail("Invoice not found.");
    return;
  }
  const invoice = invoiceSnap.data() as Record<string, unknown>;
  if (String(invoice.clientId || "") !== clientId) {
    await fail("You are not allowed to pay this invoice.");
    return;
  }

  const totalLegalFee = Number(invoice.totalLegalFee || 0);
  const amountPaid = Number(invoice.amountPaid || 0);
  const remaining = Math.max(0, totalLegalFee - amountPaid);
  // Clamp to the remaining balance; default to full balance when unspecified.
  const amount = requestedAmount > 0 ? Math.min(requestedAmount, remaining) : remaining;
  if (amount <= 0) {
    await fail("Nothing left to pay on this invoice.");
    return;
  }

  const attorneyId = String(invoice.attorneyId || "");
  const caseId = String(invoice.caseId || "");
  const caseTitle = String(invoice.caseTitle || "");
  const clientName = String(invoice.clientName || "");

  // Pre-create the pending payment record so the webhook can flip it to paid.
  // The Xendit Invoice `external_id` is this payment doc id, so the webhook can
  // resolve everything from it without relying on metadata.
  const paymentRef = db.collection("payments").doc();
  await paymentRef.set({
    invoiceId,
    clientId,
    clientName: clientName || null,
    caseId: caseId || null,
    caseTitle: caseTitle || null,
    attorneyId: attorneyId || null,
    amount,
    method,
    reference: "",
    status: "pending",
    provider: "xendit",
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    const description =
      caseTitle && caseTitle.length > 0
        ? `Legal Fee – ${caseTitle}`
        : "Legal fee payment";
    const baseBody: Record<string, unknown> = {
      external_id: paymentRef.id,
      amount: toPesoAmount(amount),
      currency: "PHP",
      description,
      success_redirect_url: cfg.successUrl,
      failure_redirect_url: cfg.cancelUrl,
      metadata: {
        invoiceId,
        paymentDocId: paymentRef.id,
        clientId,
        attorneyId,
      },
    };
    const methods = xenditPaymentMethods(method);
    const createInvoice = async (withMethods: boolean) => {
      const body =
        withMethods && methods.length > 0
          ? { ...baseBody, payment_methods: methods }
          : baseBody;
      return fetch(`${XENDIT_API}/v2/invoices`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: authHeader(cfg.secretKey),
        },
        body: JSON.stringify(body),
      });
    };

    // Try with the chosen channel(s) first; if Xendit rejects because a channel
    // isn't activated, retry with all channels so the payment still works.
    let resp = await createInvoice(true);
    let json = (await resp.json()) as Record<string, unknown>;
    if (!resp.ok && methods.length > 0) {
      logger.warn("xenditCheckout: restricted create failed, retrying open", {
        detail: json?.message || json?.error_code,
      });
      resp = await createInvoice(false);
      json = (await resp.json()) as Record<string, unknown>;
    }
    if (!resp.ok) {
      const detail =
        (json?.message as string) ||
        (json?.error_code as string) ||
        `Xendit error (${resp.status}).`;
      await paymentRef.update({ status: "failed", error: detail });
      await fail(detail);
      return;
    }

    const sessionId = json.id as string;
    const checkoutUrl = json.invoice_url as string | undefined;
    if (!checkoutUrl) {
      await paymentRef.update({ status: "failed", error: "No invoice_url." });
      await fail("Xendit did not return a checkout URL.");
      return;
    }

    await paymentRef.update({ checkoutSessionId: sessionId });
    await ref.update({
      status: "ready",
      checkoutUrl,
      paymentDocId: paymentRef.id,
      checkoutSessionId: sessionId,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info("xenditCheckout: ready", {
      docId: event.params.docId,
      paymentDocId: paymentRef.id,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await paymentRef.update({ status: "failed", error: msg });
    await fail(msg);
  }
}

/**
 * Verifies the Xendit webhook by comparing the `x-callback-token` header with
 * the account's webhook verification token (constant-time compare).
 */
function verifyXenditToken(
  headerToken: string | undefined,
  webhookToken: string,
): boolean {
  if (!webhookToken) return false; // Not configured → reject to stay safe.
  if (!headerToken) return false;
  try {
    return crypto.timingSafeEqual(
      Buffer.from(headerToken, "utf8"),
      Buffer.from(webhookToken, "utf8"),
    );
  } catch {
    return false;
  }
}

interface NotifyArgs {
  attorneyId: string;
  clientName: string;
  caseTitle: string;
  amount: number;
  method: string;
  invoiceId: string;
  clientId: string;
}

async function notifyPaymentReceived(
  db: admin.firestore.Firestore,
  args: NotifyArgs,
): Promise<void> {
  const { attorneyId } = args;
  if (!attorneyId) return;
  const recipients = new Set<string>([attorneyId]);
  try {
    const staffSnap = await db
      .collection("users")
      .where("role", "==", "staff")
      .where("assignedAttorneyId", "==", attorneyId)
      .get();
    staffSnap.forEach((doc) => recipients.add(doc.id));
  } catch (e) {
    logger.warn("xendit: staff lookup failed", { e: String(e) });
  }

  const clientName = args.clientName || "A client";
  const caseLabel = args.caseTitle ? ` (${args.caseTitle})` : "";
  const methodLabel = methodDisplay(args.method);
  const title = "Payment Received";
  const message = `${clientName} paid ₱${args.amount.toLocaleString("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} via ${methodLabel}${caseLabel}.`;

  const batch = db.batch();
  recipients.forEach((uid) => {
    const nRef = db.collection("notifications").doc();
    batch.set(nRef, {
      userId: uid,
      type: "payment_received",
      title,
      message,
      data: {
        invoiceId: args.invoiceId,
        clientId: args.clientId,
        amount: args.amount,
        method: args.method,
      },
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();
}

function methodDisplay(method: string): string {
  switch (method) {
    case "gcash":
      return "GCash";
    case "maya":
      return "Maya";
    case "grab_pay":
      return "GrabPay";
    case "debit_card":
      return "Debit Card";
    case "credit_card":
      return "Credit Card";
    case "online_banking":
      return "Online Banking";
    default:
      return method;
  }
}

/**
 * Xendit Invoice webhook endpoint. Confirms a real charge, then (and only then)
 * updates the invoice balance and marks the payment successful.
 */
export async function handleXenditWebhook(
  req: Request,
  res: Response,
  cfg: XenditConfig,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }
  const headerToken = req.headers["x-callback-token"] as string | undefined;
  if (!verifyXenditToken(headerToken, cfg.webhookToken)) {
    logger.warn("xendit webhook: invalid callback token");
    res.status(401).send("Invalid token");
    return;
  }

  const body = (req.body || {}) as Record<string, unknown>;
  const status = String(body.status || "").toUpperCase();
  const externalId = String(body.external_id || ""); // == payment doc id

  // Acknowledge non-paid events (and dashboard test pings) quickly.
  if (status !== "PAID" && status !== "SETTLED") {
    res.status(200).send("Ignored");
    return;
  }
  if (!externalId) {
    res.status(200).send("No external_id");
    return;
  }

  const db = admin.firestore();
  try {
    const paidAmount = Number(body.paid_amount ?? body.amount ?? 0);
    const providerPaymentId = String(body.id || "");
    const paymentChannel = String(body.payment_channel || "");
    const paymentRef = db.collection("payments").doc(externalId);
    let notifyArgs: NotifyArgs | null = null;

    await db.runTransaction(async (tx) => {
      const paymentSnap = await tx.get(paymentRef);
      if (!paymentSnap.exists) return;
      const payment = paymentSnap.data() as Record<string, unknown>;
      // Idempotency: ignore if already settled.
      if (String(payment.status) === "successful") return;

      const amount = paidAmount > 0 ? paidAmount : Number(payment.amount || 0);
      const invoiceId = String(payment.invoiceId || "");
      const invoiceRef = db.collection("invoices").doc(invoiceId);
      const invoiceSnap = invoiceId ? await tx.get(invoiceRef) : null;
      if (invoiceSnap && invoiceSnap.exists) {
        const inv = invoiceSnap.data() as Record<string, unknown>;
        const total = Number(inv.totalLegalFee || 0);
        const currentPaid = Number(inv.amountPaid || 0);
        const newPaid = currentPaid + amount;
        const newStatus =
          total <= 0 || newPaid <= 0
            ? "unpaid"
            : newPaid >= total
              ? "paid"
              : "partially_paid";
        tx.update(invoiceRef, {
          amountPaid: newPaid,
          status: newStatus,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        notifyArgs = {
          attorneyId: String(inv.attorneyId || payment.attorneyId || ""),
          clientName: String(inv.clientName || payment.clientName || ""),
          caseTitle: String(inv.caseTitle || payment.caseTitle || ""),
          amount,
          method: String(payment.method || "gcash"),
          invoiceId,
          clientId: String(inv.clientId || payment.clientId || ""),
        };
      }
      tx.update(paymentRef, {
        status: "successful",
        amount,
        reference: providerPaymentId || paymentChannel || externalId,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    if (notifyArgs) {
      await notifyPaymentReceived(db, notifyArgs);
    }
    res.status(200).send("OK");
  } catch (e) {
    logger.error("xendit webhook: processing error", { e: String(e) });
    res.status(500).send("Error");
  }
}
