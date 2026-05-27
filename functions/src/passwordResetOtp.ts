import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

function normalizeEmail(email: unknown): string {
  return String(email ?? "")
    .trim()
    .toLowerCase();
}

/**
 * After the client stores a 6-digit OTP in `password_reset_otps/{email}` and emails it,
 * this callable verifies the OTP and sets the Firebase Auth password (Admin SDK).
 */
export const resetPasswordWithOtp = onCall(
  { region: "us-central1", memory: "256MiB" },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    const otp = String(request.data?.otp ?? "").trim();
    const newPassword = String(request.data?.newPassword ?? "");

    if (!email || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "Invalid email.");
    }
    if (!/^\d{6}$/.test(otp)) {
      throw new HttpsError("invalid-argument", "Enter the 6-digit code.");
    }
    if (newPassword.length < 6) {
      throw new HttpsError(
        "invalid-argument",
        "Password must be at least 6 characters.",
      );
    }

    const docRef = admin.firestore().doc(`password_reset_otps/${email}`);
    const doc = await docRef.get();
    if (!doc.exists) {
      throw new HttpsError(
        "not-found",
        "No reset code found. Request a new code.",
      );
    }

    const data = doc.data()!;
    if (data.used === true) {
      throw new HttpsError(
        "failed-precondition",
        "This code was already used. Request a new one.",
      );
    }
    if (String(data.otp) !== otp) {
      throw new HttpsError("permission-denied", "Invalid code.");
    }

    const createdAt = data.createdAt as admin.firestore.Timestamp | undefined;
    if (createdAt) {
      const ageMs = Date.now() - createdAt.toMillis();
      if (ageMs > 15 * 60 * 1000) {
        throw new HttpsError(
          "deadline-exceeded",
          "Code expired. Request a new one.",
        );
      }
    }

    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch {
      throw new HttpsError("not-found", "No account for this email.");
    }

    await admin.auth().updateUser(userRecord.uid, { password: newPassword });
    await docRef.update({ used: true });

    return { success: true };
  },
);
