# Full Case Creation Flow - Implementation Guide

## Overview
This document describes the complete case creation flow that has been implemented in the Law Connect system, including client requests, attorney case creation, and notifications.

---

## Flow Diagram

```
1. Client sends request/inquiry
   ↓
2. Request appears in Attorney Dashboard (Case Requests section)
   ↓
3. Attorney reviews request
   ↓
4. Attorney creates case from request (or creates new case)
   ↓
5. Case is saved to system
   ↓
6. Client receives notification (FCM + In-app)
   ↓
7. Case appears in both Attorney and Client case lists
   ↓
8. Case updates trigger notifications to client
```

---

## 1. Client Sends Request/Inquiry

### Screen: `SendRequestScreen`
**Location**: `lib/screens/client/send_request_screen.dart`

**Features**:
- Subject selection (predefined options: "Need legal help", "I have a concern", etc.)
- Custom subject input (if "Other" selected)
- Message text area (minimum 20 characters)
- Auto-detects client's assigned attorney (if any)

**How it works**:
1. Client fills out the form
2. System creates a `case_request` document in Firestore
3. Notification is sent to attorney(s) via FCM and in-app notification
4. Request appears in attorney's dashboard

**Service**: `CaseRequestService.createCaseRequest()`

---

## 2. Attorney Reviews Request

### Widget: `CaseRequestsWidget`
**Location**: `lib/widgets/attorney/case_requests_widget.dart`

**Features**:
- Displays all pending case requests
- Shows client name, email, subject, and message preview
- "Create Case" button to convert request to case
- "Dismiss" option to mark request as dismissed
- Click to view full request details

**Where it appears**:
- Attorney Dashboard → Case Requests section (above appointments)

---

## 3. Attorney Creates Case

### Screen: `AttorneyCreateCaseScreen`
**Location**: `lib/screens/attorney/attorney_create_case_screen.dart`

**Features**:
- **Client Selection**: Dropdown of all clients from attorney's cases
- **Case Title**: Text input
- **Case Category**: Dropdown (Criminal, Civil, Family Law, etc.)
- **Case Description**: Multi-line text area (minimum 20 characters)
- **Initial Status**: Dropdown (pending, under_review, in_progress, open, ongoing)

**How it works**:
1. Attorney selects client (or pre-selected from request)
2. Fills out case details
3. Clicks "Create Case"
4. System creates case in Firestore
5. If created from request, request is marked as "converted"
6. Client receives notification

**Service**: `CaseService.createCase()`

---

## 4. Notifications System

### When Case is Created:
- **FCM Push Notification** sent to client
- **In-app Notification** saved to Firestore
- **Local Notification** shown (if app is open)

**Message**: "A new case '[Case Title]' has been created by [Attorney Name]."

### When Case is Updated:
- **Status changes** → Client notified
- **New documents uploaded** → Client notified
- **Case progress updated** → Client notified

**Service**: `CaseService._sendCaseCreatedNotification()` and `CaseService._sendCaseUpdateNotification()`

---

## 5. Notification Bell (Web & Mobile)

### Mobile (AppBar):
- Red notification bell icon
- Badge shows count of unread reminders
- Located in top-right of mobile AppBar

### Web (Desktop Header):
- Red header bar with notification bell
- Shows combined count: reminders + unread messages
- Separate bell for messages
- Located in top-right of desktop header

**Features**:
- Real-time updates
- Click to view all notifications
- Badge shows "99+" if count exceeds 99

---

## Database Structure

### Collection: `case_requests`
```javascript
{
  clientId: string,
  attorneyId: string (optional),
  clientName: string,
  clientEmail: string,
  clientPhone: string (optional),
  subject: string,
  message: string,
  status: "pending" | "reviewed" | "converted" | "dismissed",
  convertedToCaseId: string (optional),
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### Collection: `cases`
```javascript
{
  clientId: string,
  attorneyId: string,
  caseTitle: string,
  caseType: string,
  caseDescription: string,
  status: string,
  documents: array<string> (optional),
  progress: object (optional),
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### Collection: `notifications`
```javascript
{
  userId: string,
  type: "case_created" | "case_updated" | "case_request",
  title: string,
  message: string,
  data: object,
  isRead: boolean,
  createdAt: timestamp
}
```

---

## Services

### `CaseRequestService`
**Location**: `lib/services/case_request_service.dart`

**Methods**:
- `createCaseRequest()` - Client sends request
- `getAttorneyCaseRequests()` - Get requests for attorney
- `getClientCaseRequests()` - Get requests for client
- `markRequestAsReviewed()` - Mark as reviewed
- `markRequestAsConverted()` - Mark as converted to case
- `dismissRequest()` - Dismiss a request

### `CaseService` (Updated)
**Location**: `lib/services/case_service.dart`

**New Features**:
- `createCase()` now returns `String?` (caseId) instead of `bool`
- Automatically sends notifications when case is created
- Sends notifications when case is updated (status, documents, etc.)

---

## Integration Points

### Client Dashboard
- Add button/link to "Send Request" screen
- Can be added to navigation menu or as a card on home screen

### Attorney Dashboard
- Case Requests widget automatically appears
- "Create Case" button in widget header
- Notification bell shows unread count

---

## FCM Notifications

### Setup Required:
1. Firebase Cloud Messaging configured
2. Cloud Function to send FCM (or use Firestore `notification_requests` collection)
3. Web: Service worker and manifest configured

### Notification Types:
- `case_request` - New request from client
- `case_created` - Case created by attorney
- `case_updated` - Case status/document updated

---

## Testing Checklist

- [ ] Client can send request
- [ ] Request appears in attorney dashboard
- [ ] Attorney can view request details
- [ ] Attorney can create case from request
- [ ] Attorney can create case without request
- [ ] Client receives notification when case is created
- [ ] Client receives notification when case is updated
- [ ] Notification bell shows correct count (web & mobile)
- [ ] Case appears in both attorney and client case lists
- [ ] Request is marked as "converted" when case is created

---

## Next Steps

1. **Add to Client Navigation**: Add "Send Request" button to client dashboard
2. **Cloud Function**: Set up FCM Cloud Function for production
3. **Web FCM Setup**: Configure service worker for web push notifications
4. **Testing**: Test full flow end-to-end
5. **Documentation**: Update user guides

---

## Files Created/Modified

### New Files:
- `lib/models/case_request_model.dart`
- `lib/services/case_request_service.dart`
- `lib/screens/client/send_request_screen.dart`
- `lib/screens/attorney/attorney_create_case_screen.dart`
- `lib/widgets/attorney/case_requests_widget.dart`

### Modified Files:
- `lib/services/case_service.dart` - Added notifications
- `lib/pages/attorney/attorney_dashboard.dart` - Added case requests widget and notification bell
- `lib/pages/case/create_case_page.dart` - Updated return type handling

---

## Notes

- All notifications are sent via FCM and saved to Firestore
- Case requests are filtered by attorney (shows requests for that attorney or general requests)
- Client can send requests even without an assigned attorney (goes to all attorneys)
- Attorney can create cases for any client they have worked with
- Case updates trigger automatic notifications to clients

