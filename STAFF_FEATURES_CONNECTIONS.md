# Staff Features - Client & Attorney Data Connections

## Overview
Staff (Paralegal/Legal Assistant) can view and assist with all data from their assigned attorney and the attorney's clients. All features are properly connected to show relevant client and attorney information.

---

## 1. Dashboard ✅

**Connected Data:**
- ✅ **Assigned Tasks** - Shows tasks assigned to staff from attorney
- ✅ **Upcoming Deadlines** - Shows calendar events from attorney's calendar (hearings, filings, deadlines)
- ✅ **Notifications** - Shows unread messages from attorney
- ✅ **Active Cases** - Shows cases assigned to staff (quick access)
- ✅ **Statistics** - Calculated from staff's tasks and assigned cases

**Data Source:**
- Tasks: `tasks` collection (where `assignedTo == staffId`)
- Cases: `cases` collection (where `staffAssigned` contains staffId OR `attorneyId == assignedAttorneyId`)
- Calendar Events: `calendar_events` collection (where `assignedTo == assignedAttorneyId`)
- Messages: `messages` collection (chat with attorney)

---

## 2. Case Support Management ✅

**Connected Data:**
- ✅ **View All Attorney Cases** - Toggle button to view all cases from assigned attorney (not just assigned ones)
- ✅ **View Case Details** - Shows full case information including:
  - Case title, type, description, status
  - **Client Information** (name, email, phone) - Loaded from `users` collection
  - Case documents
  - Case notes
- ✅ **Add Notes** - Staff can add notes for attorney review
- ✅ **Upload Documents** - Staff can upload secondary documents to cases
- ✅ **Update Minor Info** - Staff can update case information (with restrictions)

**Restrictions:**
- ❌ Cannot delete cases
- ❌ Cannot close cases
- ❌ Cannot change case status

**Data Source:**
- Cases: `cases` collection (where `attorneyId == assignedAttorneyId`)
- Client Info: `users` collection (where `id == case.clientId`)
- Documents: Stored in case document's `documents` array

---

## 3. Client Assistance ✅

**Connected Data:**
- ✅ **View Client Profiles** - Shows all clients from attorney's cases
- ✅ **Client Information Displayed:**
  - Client name
  - Email
  - Phone number
  - Address
  - Associated cases count
- ✅ **Update Client Info** - Staff can update:
  - Phone number
  - Email
  - Address
- ✅ **Schedule Meetings** - Staff can create appointments for clients
- ✅ **View Client Cases** - See all cases associated with each client

**Data Source:**
- Clients: Derived from `cases` collection (where `attorneyId == assignedAttorneyId`)
- Client Details: `users` collection (where `role == 'client'`)
- Appointments: `appointments` collection (created for attorney's clients)

---

## 4. Schedule & Calendar ✅

**Connected Data:**
- ✅ **View Attorney's Calendar** - Shows all calendar events for assigned attorney
- ✅ **Event Types:**
  - Hearings
  - Filings
  - Deadlines
  - Meetings
  - Reminders
- ✅ **Add Events** - Staff can create calendar events for attorney
- ✅ **Event Details:**
  - Title, description, date/time
  - Event type
  - Associated case (if linked)

**Data Source:**
- Calendar Events: `calendar_events` collection (where `assignedTo == assignedAttorneyId`)
- Cases: Linked via `caseId` field in events

---

## 5. Document Management ✅

**Connected Data:**
- ✅ **View All Case Documents** - Toggle to view documents from all attorney cases (not just assigned)
- ✅ **Document Organization:**
  - Grouped by case
  - Grouped by folder
  - Grouped by document type
- ✅ **Upload Documents** - Staff can upload documents to any attorney case
- ✅ **Document Metadata:**
  - Document name, type, folder
  - Upload date
  - Uploaded by (staff info)
  - Associated case

**Data Source:**
- Cases: `cases` collection (where `attorneyId == assignedAttorneyId`)
- Documents: Stored in case document's `documents` array
- Storage: Firebase Storage (document files)

---

## 6. Task Management ✅

**Connected Data:**
- ✅ **View Assigned Tasks** - Shows tasks assigned to staff
- ✅ **Task Details:**
  - Title, description, status
  - Priority
  - Due date
  - Associated case (if linked)
  - Created by attorney
- ✅ **Update Task Status** - Staff can change status (Pending → In Progress → Completed)
- ✅ **Set Priority** - Staff can prioritize tasks
- ✅ **Notify Attorney** - Automatic notification when task is completed

**Data Source:**
- Tasks: `tasks` collection (where `assignedTo == staffId`)
- Attorney Info: `users` collection (where `id == task.attorneyId`)

---

## 7. Communication ✅

**Connected Data:**
- ✅ **Chat with Attorney** - Direct messaging with assigned attorney
- ✅ **Chat with Clients (Through Attorney)** - Participate in client conversations that belong to their assigned attorney or to them as staff
- ✅ **Message Features:**
  - Send/receive messages
  - View message history
  - Unread message count

**Data Source:**
- Messages: `messages` collection (conversations where:
  - `attorneyId == assignedAttorneyId` (client–attorney chats staff can assist on), or
  - `staffId == staffId` / `staffEmail == staff.email` (direct staff chats))
- Attorney Info: `users` collection (where `id == assignedAttorneyId`)

---

## 8. Filing & Submission Assistance ✅

**Connected Data:**
- ✅ **View Filing Deadlines** - Shows all filing deadlines from attorney's calendar
- ✅ **Deadline Types:**
  - Filing deadlines
  - Submission deadlines
  - Hearing dates
- ✅ **Add Filing Deadlines** - Staff can create new filing deadlines
- ✅ **Urgency Indicators** - Shows how urgent each deadline is
- ✅ **Deadline Notifications** - Staff can see approaching deadlines

**Data Source:**
- Calendar Events: `calendar_events` collection (where `assignedTo == assignedAttorneyId` AND `eventType` in ['filing', 'deadline', 'hearing'])

---

## 9. Reports & Logs ✅

**Connected Data:**
- ✅ **Activity Logs** - Shows all staff activities:
  - Document uploads
  - Case notes added
  - Client info updates
  - Calendar events created
- ✅ **Task Completion Reports** - Shows:
  - Completed tasks count
  - Pending tasks count
  - In progress tasks count
  - Recent completed tasks
- ✅ **Document Upload History** - Shows:
  - All documents uploaded by staff
  - Upload dates
  - Associated cases

**Data Source:**
- Activity Logs: `activity_logs` collection (where `userId == staffId`)
- Tasks: `tasks` collection (where `assignedTo == staffId`)
- Documents: From activity logs (filtered by action type)

---

## 10. Restricted Access Control ✅

**What Staff CANNOT Do:**
- ❌ Delete cases
- ❌ Close cases
- ❌ View sensitive financial information
- ❌ Edit high-level legal decisions
- ❌ Message clients directly (if restricted)

**What Staff CAN Do:**
- ✅ View all attorney cases and client data
- ✅ Add notes and upload documents
- ✅ Update client contact information
- ✅ Schedule meetings and create calendar events
- ✅ Update task progress
- ✅ View all attorney calendar events
- ✅ Assist with filing deadlines

---

## Data Flow Summary

### Staff → Attorney Connection
- Staff has `assignedAttorneyId` field
- All queries filter by `attorneyId == assignedAttorneyId`

### Staff → Client Connection
- Clients are found through attorney's cases
- Query: `cases` where `attorneyId == assignedAttorneyId`
- Then get client info from `users` collection using `case.clientId`

### Staff → Case Connection
- Staff can view:
  1. Cases assigned to them: `cases` where `staffAssigned` contains staffId
  2. All attorney cases: `cases` where `attorneyId == assignedAttorneyId`
- Toggle button in Cases screen to switch between views

### Staff → Documents Connection
- Documents are stored in case documents array
- Staff can view documents from all attorney cases
- Toggle button in Documents screen to switch between assigned/all cases

### Staff → Calendar Connection
- All calendar events for attorney: `calendar_events` where `assignedTo == assignedAttorneyId`
- Staff can create events for attorney
- Events can be linked to cases via `caseId` field

---

## Key Service Methods

### StaffService Methods:
- `getAssignedCases(staffId)` - Cases assigned to staff
- `getAttorneyCases(attorneyId)` - All cases from attorney
- `getAttorneyClients(attorneyId)` - All clients from attorney's cases
- `getCalendarEvents(attorneyId)` - All calendar events for attorney
- `getAttorneyCaseDocuments(attorneyId)` - All documents from attorney's cases
- `getAttorneyFilingDeadlines(attorneyId)` - Filing deadlines for attorney

---

## Implementation Status

✅ All features are implemented and connected
✅ Staff can view all attorney and client data
✅ Toggle buttons allow viewing assigned vs. all attorney cases
✅ Client information is displayed in case details
✅ All screens properly filter by assigned attorney
✅ Restricted access is enforced in UI and Firestore rules

---

## Testing Checklist

- [ ] Staff can view all attorney cases (toggle button works)
- [ ] Staff can see client info in case details
- [ ] Staff can view documents from all attorney cases
- [ ] Staff can see all attorney calendar events
- [ ] Staff can update client contact information
- [ ] Staff can schedule meetings for clients
- [ ] Staff cannot delete or close cases
- [ ] Staff can only message attorney (not clients)
- [ ] All data is properly filtered by assigned attorney





