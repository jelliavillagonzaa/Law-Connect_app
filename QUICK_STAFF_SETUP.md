# Quick Staff Account Setup Guide

## 🚀 Quick Setup: Manual Staff Account

You've already created the Firebase Auth user (`assistant@gmail.com`). Now create the Firestore document:

### Step 1: Get the User UID
1. Go to **Firebase Console** → **Authentication** → **Users**
2. Find `assistant@gmail.com`
3. **Copy the User UID** (looks like: `abc123xyz789...`)

### Step 2: Get an Attorney UID (Required for Staff)

You need to assign the staff to an attorney. Get an attorney's UID:
1. Go to **Firestore Database** → **`users`** collection
2. Find an attorney document (where `role: "attorney"`)
3. **Copy that attorney's Document ID (UID)**
   - If you don't have an attorney yet, you can use the attorney you just created

### Step 3: Create Firestore Document

1. Go to **Firebase Console** → **Firestore Database**
2. Click **`users`** collection (NOT a separate `staff` collection)
3. Click **"Add document"**
4. **Paste the User UID as Document ID** (from Step 1)
5. Add these fields:

| Field | Type | Value |
|-------|------|-------|
| `email` | string | `assistant@gmail.com` |
| `name` | string | `Staff Name` |
| `fullName` | string | `Staff Full Name` |
| `role` | string | `staff` ⭐ **MUST be "staff"** |
| `assignedAttorneyId` | string | `[Attorney's UID from Step 2]` ⭐ **REQUIRED** |
| `isVerified` | boolean | `true` |
| `createdAt` | timestamp | [Click timestamp icon → **Server Timestamp**] |

### Quick Copy-Paste (Firebase Console JSON):

```json
{
  "email": "assistant@gmail.com",
  "name": "Assistant Staff",
  "fullName": "Assistant Staff",
  "role": "staff",
  "assignedAttorneyId": "[ATTORNEY_UID_HERE]",
  "isVerified": true,
  "createdAt": [Server Timestamp]
}
```

### Optional Fields (Add if you want):

```json
{
  "phoneNumber": "09123456789",
  "address": "123 Office Street, City",
  "phone": "09123456789"
}
```

---

## ⚠️ Important Notes

1. **Document ID = Firebase Auth UID** - Must match exactly
2. **`role: "staff"`** - Must be exactly `"staff"` (lowercase)
3. **`assignedAttorneyId` is REQUIRED** - Staff cannot access dashboard without it
4. **Collection: `users`** - Staff are in the `users` collection, NOT a separate collection

---

## ✅ Complete Example Document

```
Collection: users
Document ID: [Your Firebase Auth UID for assistant@gmail.com]

Fields:
├── email: "assistant@gmail.com"
├── name: "Assistant Staff"
├── fullName: "Assistant Staff"
├── role: "staff"
├── assignedAttorneyId: "attorney_uid_here"  ← CRITICAL
├── isVerified: true
├── phoneNumber: "09123456789" (optional)
├── address: "123 Office St" (optional)
└── createdAt: [Server Timestamp]
```

---

## 🎯 After Setup

1. **Login** with `assistant@gmail.com` / `assistant123`
2. **Should redirect to Staff Dashboard** ✅

---

## 🔧 Troubleshooting

**Can't access dashboard?**
- Check `role` is exactly `"staff"` (lowercase)
- Check `assignedAttorneyId` is set to a valid attorney UID
- Check Document ID matches Firebase Auth UID exactly
- Check `isVerified` is `true`

**Need an attorney UID?**
- Check your `users` collection for documents where `role: "attorney"`
- Use that document's ID as the `assignedAttorneyId`

---

## 📝 Notes

- Staff must be assigned to an attorney to access the dashboard
- Staff can only see cases and data for their assigned attorney
- You can change `assignedAttorneyId` later if needed

