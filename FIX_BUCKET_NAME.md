# 🔧 Fix: Bucket Name Case Sensitivity Issue

## Problem
Your Supabase bucket is named **"FILES"** (uppercase), but the code expects **"files"** (lowercase). Supabase bucket names are case-sensitive!

## Solution: Create the Correct Bucket

### Option 1: Delete and Recreate (Recommended)

1. **Go to Supabase Dashboard** → **Storage** → **Buckets**
2. **Delete the "FILES" bucket**:
   - Click on the "FILES" bucket
   - Click the settings/gear icon
   - Click "Delete bucket"
   - Confirm deletion

3. **Create a new bucket with lowercase name**:
   - Click **"New bucket"**
   - **Name**: Type exactly `files` (lowercase, no quotes)
   - **Public bucket**: ✅ Check this box
   - **File size limit**: `10485760` (10 MB) or higher
   - Click **"Create bucket"**

4. **Recreate the policies**:
   - Go to the new `files` bucket → **Policies** tab
   - Click **"New Policy"**
   
   **Policy 1 - INSERT:**
   - Name: `Allow public uploads`
   - Command: `INSERT`
   - Policy definition: `bucket_id = 'files'::text`
   
   **Policy 2 - SELECT:**
   - Name: `Allow public read`
   - Command: `SELECT`
   - Policy definition: `bucket_id = 'files'::text`
   
   **Policy 3 - DELETE (Optional):**
   - Name: `Allow public delete`
   - Command: `DELETE`
   - Policy definition: `bucket_id = 'files'::text`

### Option 2: Update Code (Not Recommended)

If you can't delete the bucket, I can update the code to use "FILES" instead, but this is not recommended as it goes against naming conventions.

---

## ✅ After Fixing

1. **Restart your Flutter app**
2. **Try uploading a profile picture again**
3. The error should be gone!

---

**The bucket name MUST be exactly**: `files` (lowercase)

