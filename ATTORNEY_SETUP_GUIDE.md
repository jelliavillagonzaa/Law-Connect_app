# Attorney User Setup Guide

## Quick Setup for Manual Attorney Account

If you've already created an email/password user in Firebase Authentication and want to give them attorney dashboard access, follow these steps:

### Step 1: Get the Firebase Auth UID

1. Go to **Firebase Console** → **Authentication** → **Users**
2. Find your attorney user (e.g., `attorney@gmail.com`)
3. **Copy the User UID** (you'll need this as the Document ID)

### Step 2: Create Firestore Document

1. Go to **Firebase Console** → **Firestore Database**
2. Navigate to the **`users`** collection
3. Click **"Add document"**
4. **Use the User UID as the Document ID** (paste the UID from Step 1)

### Step 3: Add Required Fields

Add the following fields to the document:

| Field Name | Type | Value | Required |
|------------|------|-------|----------|
| `email` | string | `attorney@gmail.com` | ✅ Yes |
| `name` | string | `Attorney Name` | ✅ Yes |
| `fullName` | string | `Attorney Full Name` | ✅ Yes |
| `role` | string | `attorney` | ✅ Yes |
| `isVerified` | boolean | `true` | ✅ Yes |
| `isActive` | boolean | `true` | ✅ Yes (for immediate access) |
| `isAvailable` | boolean | `true` | ✅ Yes |
| `pendingApproval` | boolean | `false` | ✅ Yes |
| `ratingAverage` | number | `0.0` | ✅ Yes |
| `createdAt` | timestamp | [Click timestamp icon → Server Timestamp] | ✅ Yes |

### Step 4: Add Optional Fields (Recommended)

| Field Name | Type | Value | Required |
|------------|------|-------|----------|
| `phoneNumber` | string | `09123456789` | ❌ Optional |
| `address` | string | `Your Address` | ❌ Optional |
| `specialization` | array | `["Criminal Law", "Family Law"]` | ❌ Optional |
| `barNumber` | string | `BAR-2020-12345` | ❌ Optional |
| `licenseState` | string | `Metro Manila` | ❌ Optional |

### Complete Example Document

```
Collection: users
Document ID: [Your Firebase Auth UID]

Fields:
├── email: "attorney@gmail.com"
├── name: "John Attorney"
├── fullName: "John Attorney"
├── role: "attorney"
├── isVerified: true
├── isActive: true          ← Important: Must be true for dashboard access
├── isAvailable: true
├── pendingApproval: false  ← Important: Must be false for dashboard access
├── ratingAverage: 0.0
├── phoneNumber: "09123456789"
├── address: "123 Law Street, City"
├── specialization: ["Criminal Law", "Family Law"]
├── barNumber: "BAR-2020-12345"
├── licenseState: "Metro Manila"
└── createdAt: [Server Timestamp]
```

### Quick Copy-Paste JSON (for Firebase Console)

```json
{
  "email": "attorney@gmail.com",
  "name": "John Attorney",
  "fullName": "John Attorney",
  "role": "attorney",
  "isVerified": true,
  "isActive": true,
  "isAvailable": true,
  "pendingApproval": false,
  "ratingAverage": 0.0,
  "phoneNumber": "09123456789",
  "address": "123 Law Street, City",
  "specialization": ["Criminal Law", "Family Law"],
  "barNumber": "BAR-2020-12345",
  "licenseState": "Metro Manila",
  "createdAt": [Server Timestamp]
}
```

### Important Notes:

1. **Document ID = Firebase Auth UID** - Must match exactly
2. **`isActive: true`** - Required for dashboard access
3. **`pendingApproval: false`** - Required for dashboard access
4. **`role: "attorney"`** - Must be exactly "attorney" (lowercase)

### After Setup:

1. Logout from the app (if logged in)
2. Login with: `attorney@gmail.com` / `attorney123`
3. You should be redirected to the Attorney Dashboard

### Troubleshooting:

- **Can't access dashboard?** Check that `isActive` is `true` and `pendingApproval` is `false`
- **Wrong role error?** Verify `role` field is exactly `"attorney"` (lowercase)
- **Still can't login?** Make sure the Document ID matches the Firebase Auth UID exactly

