/**
 * One-shot PhilSMS test (1 credit). Run from functions/:
 *   npm run build && npm run test:philsms
 */
import { createRequire } from "module";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const require = createRequire(import.meta.url);
const __dir = dirname(fileURLToPath(import.meta.url));
const { sendPhilSms } = require(join(__dir, "../lib/philsmsClient.js"));

// Use env only when explicitly passed: PHILSMS_API_TOKEN=xxx npm run test:philsms
const token =
  process.argv.includes("--use-env") && process.env.PHILSMS_API_TOKEN?.trim()
    ? process.env.PHILSMS_API_TOKEN.trim()
    : "3121|EcLePG3aVbu2YUoc6nxNVONdIW1BFThS1CN9ZxBqf680e780";

const phone = process.env.PHILSMS_TEST_PHONE || "09351914214";
const msg =
  process.env.PHILSMS_TEST_MESSAGE ||
  "JurisLink PhilSMS test - safe to ignore";

console.log(`Sending 1 test SMS to ${phone}...`);
const result = await sendPhilSms(
  { apiToken: token, senderId: process.env.PHILSMS_SENDER_ID || "PhilSMS" },
  phone,
  msg,
);

if (result.ok) {
  console.log("OK — PhilSMS accepted the message (1 credit used).");
  process.exit(0);
}
console.error("FAILED:", result.error);
process.exit(1);
