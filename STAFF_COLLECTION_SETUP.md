# Staff Collection Setup Guide

## Overview
Staff users are now stored in a **separate `staff` collection** instead of the `users` collection. This provides better organization and separation of concerns.

## Collection Structure

### Collection Name: `staff`

### Document Structure

**Document ID:** Use the Firebase Auth User UID

**Required Fields:**

```json
{
  "email": "staff@lawfirm.com",
  "name": "Jane Smith",
  "assignedAttorneyId": "attorney_uid_here",
  "isVerified": true,
  "createdAt": [Server Timestamp]
}
```

**Optional Fields:**

```json
{
  "phone": "+1234567890",
  "phoneNumber": "+1234567890",
  "address": "123 Main St, City, State",
  "photoUrl": "https://...",
  "updatedAt": [Server Timestamp]
}
```

## Field Details

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | ✅ Yes | Staff email address |
| `name` | string | ✅ Yes | Staff full name |
| `assignedAttorneyId` | string | ✅ Yes | UID of the attorney this staff is assigned to |
| `isVerified` | boolean | ✅ Yes | Set to `true` |
| `createdAt` | timestamp | ✅ Yes | Use "Server Timestamp" |
| `phone` | string | ❌ Optional | Phone number |
| `phoneNumber` | string | ❌ Optional | Alternative phone field |
| `address` | string | ❌ Optional | Address |
| `photoUrl` | string | ❌ Optional | Profile photo URL |
| `updatedAt` | timestamp | ❌ Optional | Last update timestamp |

## How to Create Staff User

### Step 1: Create User in Firebase Authentication
1. Go to Firebase Console → Authentication → Users
2. Click "Add user"
3. Enter email and password
4. **Copy the User UID** (you'll need this)

### Step 2: Create Staff Document in Firestore

1. Go to Firestore Database
2. Navigate to the **`staff`** collection (create it if it doesn't exist)
3. Click "Add document"
4. Use the **User UID** from Step 1 as the Document ID
5. Add the following fields:

```
Field Name          | Type          | Value
--------------------|---------------|--------------------------
email               | string        | staff@lawfirm.com
name                | string        | Jane Smith
assignedAttorneyId  | string        | [Attorney's UID]
isVerified          | boolean       | true
createdAt           | timestamp     | [Click timestamp icon → Server Timestamp]
phone               | string        | +1234567890 (optional)
address             | string        | 123 Main St (optional)
```

### Example Complete Document

```
Collection: staff
Document ID: abc123xyz789

Fields:
├── email: "paralegal@lawfirm.com"
├── name: "Jane Smith"
├── assignedAttorneyId: "attorney_uid_here"
├── isVerified: true
├── createdAt: [Server Timestamp]
├── phone: "+1234567890"
└── address: "123 Main St, City, State"
```

## Important Notes

1. **Document ID = Firebase Auth UID** - Must match exactly
2. **assignedAttorneyId is REQUIRED** - Staff cannot access dashboard without it
3. **No `role` field needed** - Staff collection implies role is 'staff'
4. **Separate from users** - Staff are NOT in the `users` collection

## Migration from Users Collection

If you have existing staff in the `users` collection:

1. Find staff documents in `users` collection where `role == 'staff'`
2. Copy the document data
3. Create new document in `staff` collection with same UID
4. Remove `role` field (not needed in staff collection)
5. Ensure `assignedAttorneyId` is set
6. Delete old document from `users` collection (optional, but recommended)

## Firestore Rules

The Firestore rules have been updated to:
- Allow staff to read their own document
- Allow attorneys to read staff assigned to them
- Allow admins to read all staff
- Only admins can create/delete staff
- Staff can update their own profile

## Testing

After creating a staff user:
1. Logout and login with staff credentials
2. Should automatically route to Staff Dashboard
3. All features should work as expected


