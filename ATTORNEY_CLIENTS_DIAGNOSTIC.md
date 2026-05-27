# Attorney Clients Diagnostic Guide

## Why "No Clients Found" for attorney@gmail.com?

### How Clients Are Linked to Attorneys

In your system, **clients are linked to attorneys through cases**:

1. **Client creates a case** → Case has `clientId` and `status: 'pending'`
2. **Attorney accepts the case** → Case gets `attorneyId` set and `status: 'accepted'`
3. **Staff/Attorney views clients** → System queries `cases` where `attorneyId == attorney's UID`, then extracts unique `clientId` values

### Common Reasons for "No Clients Found"

#### 1. **No Cases Created Yet**
- Clients haven't created any cases in the system
- **Solution**: Have a client create a case request

#### 2. **Cases Exist But Not Accepted**
- Cases exist with `status: 'pending'` but attorney hasn't accepted them
- **Solution**: Attorney needs to log in and accept pending cases from their dashboard

#### 3. **Attorney UID Mismatch**
- Cases have `attorneyId` but it doesn't match the attorney's actual UID
- **Solution**: Check that `attorneyId` in cases matches the attorney's document ID in `users` collection

#### 4. **Attorney Account Not Active**
- Attorney account exists but `isActive: false` or `pendingApproval: true`
- **Solution**: Set `isActive: true` and `pendingApproval: false` in attorney's user document

### How to Check Your Attorney Account

#### Option 1: Manual Check in Firebase Console

1. **Find Attorney UID:**
   - Go to Firebase Console → Authentication → Users
   - Find `attorney@gmail.com`
   - Copy the **User UID** (looks like: `abc123xyz789...`)

2. **Check Attorney Document:**
   - Go to Firestore Database → `users` collection
   - Find document with ID = attorney's UID
   - Verify:
     - `role: "attorney"`
     - `isActive: true`
     - `pendingApproval: false`

3. **Check Cases:**
   - Go to Firestore Database → `cases` collection
   - Look for documents where:
     - `attorneyId` field equals the attorney's UID
     - `clientId` field is not null/empty
   - Check `status` field:
     - `pending` = needs attorney to accept
     - `accepted` or `in_progress` = should show clients

#### Option 2: Use Diagnostic Tool

I've created a diagnostic tool at `lib/utils/check_attorney_account.dart`. You can use it in your app to check the attorney account programmatically.

### Quick Fix Steps

1. **Verify Attorney Account:**
   ```
   Firestore: users/{attorneyUID}
   - role: "attorney"
   - isActive: true
   - pendingApproval: false
   ```

2. **Check for Pending Cases:**
   ```
   Firestore: cases collection
   - Look for cases with status: "pending"
   - These need to be accepted by the attorney
   ```

3. **Accept Cases:**
   - Attorney logs in
   - Goes to Cases/Dashboard
   - Accepts pending case requests
   - This sets attorneyId on the case and links the client

4. **Verify Case Has Both IDs:**
   ```
   After accepting, case should have:
   - clientId: "<client_uid>"
   - attorneyId: "<attorney_uid>"
   - status: "accepted" or "in_progress"
   ```

### Expected Data Structure

**For clients to show up, you need:**

```json
// Case document in Firestore
{
  "caseTitle": "Some Case",
  "clientId": "client_user_uid_here",
  "attorneyId": "attorney_user_uid_here",  // ← Must match attorney's UID
  "status": "accepted",  // or "in_progress"
  "createdAt": "...",
  "updatedAt": "..."
}
```

**Attorney user document:**
```json
{
  "email": "attorney@gmail.com",
  "role": "attorney",
  "isActive": true,
  "pendingApproval": false,
  "name": "Attorney Name"
}
```

### Testing Checklist

- [ ] Attorney account exists in Firebase Auth
- [ ] Attorney document exists in Firestore `users` collection with correct UID
- [ ] Attorney document has `role: "attorney"`, `isActive: true`, `pendingApproval: false`
- [ ] At least one case exists in `cases` collection
- [ ] Case has `attorneyId` matching attorney's UID
- [ ] Case has `clientId` set (not null/empty)
- [ ] Case has `status: "accepted"` or `status: "in_progress"` (not "pending")

If all checkboxes are checked and clients still don't show, there may be a query/index issue. Check Firestore indexes.

