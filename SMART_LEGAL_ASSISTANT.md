# Smart legal assistant (court notices → calendar)

## What was added

- **Upload flow:** Staff or attorney opens **Court notice scan** (sidebar / drawer / attorney nav **Notice scan**), picks a **PDF** or **image**.
- **Text:** PDFs use **Syncfusion** text extraction. Images use **ML Kit** OCR on mobile/desktop (not on web).
- **Extraction:** Rule-based English heuristics populate `CourtMessageExtraction`. If configured, the app POSTs `{ "text": "..." }` to your **secure backend** and merges JSON fields (same contract as `LegalAssistantCloudParser`).
- **Calendar:** Creates a **`hearing`** document in `calendar_events` via existing `StaffService.createCalendarEvent` (same fields as the staff calendar UI). Sets `remindAttorney: true`, `notifyStaff: true`, `sendNow: true`, optional case/client linkage.
- **Audit:** `system_logs` (via `AdminService`) and `activity_logs` (via `StaffService.logActivity`) record scheduling actions.
- **Auto vs confirm:** Controlled by Firestore (see below). Default is **always review** before scheduling unless auto-create is enabled and a hearing date was parsed.

## Firestore configuration

### `app_settings/legal_assistant` (document)

| Field | Type | Default | Meaning |
|--------|------|---------|---------|
| `enabled` | bool | true | Master switch; if false, feature is hidden/denied. |
| `extractionApiUrl` | string | _(empty)_ | HTTPS URL for optional LLM/rules API. **No API keys in the app** — keys stay on your server. |
| `autoCreateWithoutConfirm` | bool | false | If true, org default is to schedule immediately when a hearing date is found (still uses same calendar pipeline). |

### `users/{uid}` (optional overrides)

| Field | Type | Meaning |
|--------|------|---------|
| `legalAssistantAutoCreate` | bool? | If set, overrides `autoCreateWithoutConfirm` for that user. |
| `legalAssistantDisabled` | bool | If true, user cannot use the tool. |

**Roles allowed:** `staff`, `attorney`, `admin` (staff must have `assignedAttorneyId`).

## Backend API contract (optional)

`POST` JSON body:

```json
{ "text": "full plain text from PDF/OCR" }
```

Response: JSON object with optional keys (all strings unless noted):

- `hearingDateTime` — ISO-8601 string
- `courtName`, `court`, `judge`, `caseNumber`, `case_number`
- `plaintiff`, `defendant`, `attorney`, `attorneyMentioned`, `client`, `clientMentioned`
- `room`, `roomOrBranch`, `summary`, `summaryNotes`

The app merges these with the on-device rule baseline (`LegalAssistantCloudParser`).

## Test checklist

1. **Text PDF (English)** with a clear `mm/dd/yyyy` and time → fields populate; schedule → event appears on staff calendar for the assigned attorney.
2. **Scanned PDF** → depends on text layer; if empty, try **image** on Android/iOS.
3. **Image on web** → expect message to use PDF instead (OCR not wired for web).
4. **Missing date** → scheduling should fail with a clear message until the user sets date/time in the review screen.
5. **Permissions:** set `legalAssistantDisabled: true` on a user → screen should deny access.
6. **Auto-create:** set `autoCreateWithoutConfirm: true` and confirm a notice with a parsed date schedules without pressing the button (snackbar confirms).

## Files to know

- `lib/models/court_message_extraction.dart`
- `lib/services/court_notice_service.dart` — orchestration
- `lib/services/court_notice_rule_extractor.dart` — heuristics
- `lib/services/court_notice_text_extractor.dart` — PDF + OCR entry
- `lib/services/legal_assistant_settings_service.dart` — Firestore flags
- `lib/services/legal_assistant_cloud_parser.dart` — HTTP merge
- `lib/screens/common/court_notice_upload_screen.dart` — UI
- `lib/utils/temp_file_for_ocr.dart` — conditional IO for image bytes → temp path

No changes were made to **staff/attorney calendar screen layouts**; only new navigation entry points and shared services.

## Email automation (Cloud Functions)

For **webhook-based court email** ingestion → same `calendar_events` + review queue, see **[EMAIL_INGEST.md](./EMAIL_INGEST.md)** (`functions/` + `courtEmailIngest`).
