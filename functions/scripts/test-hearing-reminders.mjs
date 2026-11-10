/**
 * Pure reminder/SMS format checks (no PhilSMS/Semaphore credits).
 *
 *   npm run build && npm run test:hearing-reminders
 */
import { createRequire } from "module";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const require = createRequire(import.meta.url);
const __dir = dirname(fileURLToPath(import.meta.url));
const {
  reminderSchedule,
  expectedReminderAt,
  isHearingInactiveForReminders,
  isActiveHearingReminderKind,
} = require(join(__dir, "../lib/hearingNotifications.js"));
const {
  buildHearingSmsText,
  formatHearingSmsTime,
  formatHearingSmsLocation,
  reminderProviderComplete,
  reminderLegacyLocked,
} = require(join(__dir, "../lib/hearingSmsAlerts.js"));

let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error("FAIL:", msg);
  } else {
    console.log("OK:", msg);
  }
}

const hearingAt = new Date("2026-10-28T08:30:00+08:00");
const nowFar = new Date("2026-09-01T08:30:00+08:00");
const schedule = reminderSchedule(hearingAt, nowFar);

assert(schedule.length === 3, "far-future hearing schedules 3 reminders");
assert(
  schedule[0].kind === "d5" &&
    schedule[0].at.toISOString() ===
      new Date("2026-10-23T08:30:00+08:00").toISOString(),
  "5-day reminder is October 23, 2026 8:30 AM",
);
assert(
  schedule[1].kind === "d2" &&
    schedule[1].at.toISOString() ===
      new Date("2026-10-26T08:30:00+08:00").toISOString(),
  "2-day reminder is October 26, 2026 8:30 AM",
);
assert(
  schedule[2].kind === "hearing_day" &&
    schedule[2].at.toISOString() === hearingAt.toISOString(),
  "hearing-day reminder is October 28, 2026 8:30 AM",
);

const oneDayOut = reminderSchedule(
  hearingAt,
  new Date("2026-10-27T08:30:00+08:00"),
);
assert(
  oneDayOut.length === 1 && oneDayOut[0].kind === "hearing_day",
  "1 day away: only hearing-day reminder",
);

const lessThanTwo = reminderSchedule(
  hearingAt,
  new Date("2026-10-26T09:00:00+08:00"),
);
assert(
  lessThanTwo.every((r) => r.kind !== "d5" && r.kind !== "d2"),
  "after 2-day slot: do not schedule past 5-day or 2-day reminders",
);

const todayMorning = reminderSchedule(
  hearingAt,
  new Date("2026-10-28T07:00:00+08:00"),
);
assert(
  todayMorning.length === 1 && todayMorning[0].kind === "hearing_day",
  "hearing morning: only hearing-day reminder",
);

const afterHearing = reminderSchedule(
  hearingAt,
  new Date("2026-10-28T08:31:00+08:00"),
);
assert(afterHearing.length === 0, "after hearing time: no reminders");

assert(
  expectedReminderAt(hearingAt, "d5").toISOString() ===
    new Date("2026-10-23T08:30:00+08:00").toISOString(),
  "expectedReminderAt d5 uses hearing clock time",
);

assert(
  isHearingInactiveForReminders({ status: "cancelled" }),
  "cancelled hearing is inactive",
);
assert(
  isHearingInactiveForReminders({ status: "completed" }),
  "completed hearing is inactive",
);
assert(
  !isHearingInactiveForReminders({ caseNo: "5297", status: "open" }),
  "open hearing stays active",
);

assert(isActiveHearingReminderKind("d5"), "d5 is active");
assert(isActiveHearingReminderKind("d2"), "d2 is active");
assert(isActiveHearingReminderKind("hearing_day"), "hearing_day is active");
assert(!isActiveHearingReminderKind("d1"), "legacy d1 is not active");
assert(!isActiveHearingReminderKind("day_noon"), "legacy day_noon is not active");

assert(formatHearingSmsTime("8:30 in the morning") === "8:30 AM", "morning → AM");
assert(
  formatHearingSmsTime("1:00 in the afternoon") === "1:00 PM",
  "afternoon → PM",
);
assert(formatHearingSmsLocation("BRANCH 12") === "Branch 12", "BRANCH → Branch");

const sms = buildHearingSmsText({
  roleLabel: "Attorney",
  caseNo: "5297",
  caseTitle:
    "HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA",
  clientName:
    "RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, DENNIS M. LUMANSOC, SPS. DANILO & PRESCILLA ARMINGOL, RUDY ACEBES & RICKY MEDINA",
  hearingDate: "October 28, 2026",
  hearingTime: "8:30 in the morning",
  location: "BRANCH 12",
});

assert(sms.startsWith("LAWCONNECT HEARING REMINDER"), "brand header");
assert(sms.includes("Case #5297"), "case number line");
assert(sms.includes("HEIRS OF VICTORIANA CALIB-OG"), "plaintiff preserved");
assert(sms.includes("vs."), "vs. on its own line");
assert(sms.includes("RUBEN MONTEJO"), "first defendant preserved");
assert(sms.includes("AXEL JOSEPH L. BINAORO"), "additional parties preserved");
assert(sms.includes("Time: 8:30 AM"), "time formatted AM");
assert(sms.includes("Location: Branch 12"), "location title-cased Branch");
assert(!sms.includes("Role: Attorney"), "role prefix omitted");
assert(!sms.includes("in the morning"), "prose morning phrase removed");
assert(!sms.includes(" - "), "not concatenated with dashes");
assert(
  sms.includes("Please be reminded of your scheduled hearing."),
  "scheduled closing",
);

const five = buildHearingSmsText({
  caseNo: "5297",
  caseTitle: "HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO, AXEL JOSEPH L. BINAORO",
  hearingDate: "October 28, 2026",
  hearingTime: "8:30 AM",
  location: "Branch 12",
  reminderKind: "d5",
});
assert(five.includes("Your hearing is in 5 days."), "5-day lead-in");

const two = buildHearingSmsText({
  caseNo: "5297",
  caseTitle: "HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO",
  hearingDate: "October 28, 2026",
  hearingTime: "8:30 AM",
  location: "Branch 12",
  reminderKind: "d2",
});
assert(two.includes("Your hearing is in 2 days."), "2-day lead-in");

const today = buildHearingSmsText({
  caseNo: "5297",
  caseTitle: "HEIRS OF VICTORIANA CALIB-OG vs. RUBEN MONTEJO",
  hearingDate: "October 28, 2026",
  hearingTime: "8:30 AM",
  location: "Branch 12",
  reminderKind: "hearing_day",
});
assert(today.includes("Your hearing is today."), "hearing-day lead-in");

assert(
  reminderProviderComplete(undefined, true, true) === false,
  "new number still needs PhilSMS and Semaphore",
);
assert(
  reminderProviderComplete({ phil: true }, true, true) === false,
  "Semaphore still sends when only PhilSMS succeeded",
);
assert(
  reminderProviderComplete({ phil: true, sem: true }, true, true) === true,
  "both providers delivered skips that number",
);
assert(
  reminderLegacyLocked({}, true) === true,
  "old sent reminder without a phone list is not texted again",
);
assert(
  reminderLegacyLocked({ "639171234567": { phil: true, sem: true } }, true) ===
    false,
  "a saved phone list can still text a newly changed number",
);

if (failed) {
  console.error(`\n${failed} check(s) failed`);
  process.exit(1);
}
console.log("\nAll hearing reminder checks passed.");
