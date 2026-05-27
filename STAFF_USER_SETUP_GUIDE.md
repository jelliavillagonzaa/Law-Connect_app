# Staff User Setup Guide

## How to Create a Staff User in Firestore

**IMPORTANT:** Staff users are stored in a **separate `staff` collection**, NOT in the `users` collection.

### Step 1: Create User in Firebase Authentication
1. Go to Firebase Console → Authentication → Users
2. Click "Add user"
3. Enter email and password
4. Copy the User UID (you'll need this)

### Step 2: Create Staff Document in Firestore

**Collection:** `staff` (NOT `users` and NOT `admin`)

**Document ID:** Use the User UID from Firebase Auth

**Required Fields:**

```json
{
  "email": "staff@example.com",
  "name": "John Doe",
  "assignedAttorneyId": "attorney_uid_here",
  "isVerified": true,
  "createdAt": [Server Timestamp]
}
```

**Note:** No `role` field is needed - being in the `staff` collection implies the role is 'staff'.

### Field Details:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | ✅ Yes | Staff email address |
| `name` | string | ✅ Yes | Staff full name |
| `role` | string | ✅ Yes | Must be exactly `"staff"` |
| `assignedAttorneyId` | string | ✅ Yes | UID of the attorney this staff is assigned to |
| `isVerified` | boolean | ✅ Yes | Set to `true` |
| `createdAt` | timestamp | ✅ Yes | Use "Server Timestamp" |
| `phone` | string | ❌ Optional | Phone number |
| `phoneNumber` | string | ❌ Optional | Alternative phone field |
| `address` | string | ❌ Optional | Address |
| `photoUrl` | string | ❌ Optional | Profile photo URL |

### Example Staff User Document:

```json
{
  "email": "paralegal@lawfirm.com",
  "name": "Jane Smith",
  "role": "staff",
  "assignedAttorneyId": "abc123xyz789",
  "isVerified": true,
  "phone": "+1234567890",
  "address": "123 Main St, City, State",
  "createdAt": [Server Timestamp]
}
```

### Important Notes:

1. **assignedAttorneyId is REQUIRED** - Staff must be assigned to an attorney to access the dashboard
2. **Use the `staff` collection** - NOT the `users` collection (staff are separated)
3. **Document ID = User UID** - Must match the Firebase Auth UID exactly
4. **No `role` field needed** - Being in `staff` collection automatically means role is 'staff'

### Assigning Cases to Staff:

When an attorney assigns a case to staff, add the staff's UID to the case document:

**Collection:** `cases`
**Field:** `staffAssigned` (array of strings)

```json
{
  "caseTitle": "Example Case",
  "clientId": "client_uid",
  "attorneyId": "attorney_uid",
  "staffAssigned": ["staff_uid_1", "staff_uid_2"],
  ...
}
```

### Quick Setup Checklist:

- [ ] Create user in Firebase Authentication
- [ ] Copy the User UID
- [ ] Create document in `users` collection with UID as document ID
- [ ] Set `role: "staff"`
- [ ] Set `assignedAttorneyId` to attorney's UID
- [ ] Set `isVerified: true`
- [ ] Add `createdAt` as Server Timestamp
- [ ] Staff can now login and access dashboard

