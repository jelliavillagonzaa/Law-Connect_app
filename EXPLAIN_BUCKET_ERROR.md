# 📖 Explanation: "Supabase Storage bucket not found" Error

## What's Happening?

Your Flutter app is trying to upload a profile picture to Supabase Storage, but it can't find the storage bucket named `files`.

## The Problem in Simple Terms

Think of Supabase Storage like a **filing cabinet**:
- **Bucket** = A drawer in the filing cabinet
- **Files** = Documents you put in the drawer
- **Your app** = Someone trying to put a document in the drawer

**Right now**: Your app is trying to open a drawer called `files`, but that drawer doesn't exist in your Supabase "filing cabinet"!

## Why This Error Appears

1. **You're trying to upload a profile picture** (clicking the camera icon)
2. **Your app code says**: "Put this image in the `files` bucket"
3. **Supabase says**: "I don't have a bucket called `files`!"
4. **Result**: Error message appears

## What You Need to Do

You need to **create the `files` bucket** in your Supabase dashboard.

### Step-by-Step Fix:

1. **Go to Supabase Dashboard**
   - Open https://supabase.com/dashboard
   - Select your project

2. **Create the Bucket**
   - Click **"Storage"** in the left menu
   - Click **"New bucket"** button
   - **Name**: Type exactly `files` (lowercase, all small letters)
   - **Public bucket**: ✅ Check this box (IMPORTANT!)
   - Click **"Create bucket"**

3. **Add Policies** (Rules for who can upload/download)
   - Click on the `files` bucket you just created
   - Go to **"Policies"** tab
   - Click **"New Policy"** three times to create:

   **Policy 1 - INSERT (for uploads):**
   - Name: `Allow public uploads`
   - Command: `INSERT`
   - Policy definition: `bucket_id = 'files'::text`

   **Policy 2 - SELECT (for downloads):**
   - Name: `Allow public read`
   - Command: `SELECT`
   - Policy definition: `bucket_id = 'files'::text`

   **Policy 3 - DELETE (optional):**
   - Name: `Allow public delete`
   - Command: `DELETE`
   - Policy definition: `bucket_id = 'files'::text`

4. **Restart Your App**
   - Stop your Flutter app
   - Run it again: `flutter run`

5. **Try Again**
   - Go to Profile screen
   - Click camera icon
   - Select image
   - It should work now! ✅

## Important Notes

### ⚠️ Bucket Name Must Be Exact
- ✅ Correct: `files` (lowercase)
- ❌ Wrong: `FILES` (uppercase)
- ❌ Wrong: `Files` (mixed case)

**Supabase is case-sensitive!** The code looks for `files` (lowercase), so the bucket must be exactly `files`.

### ⚠️ Bucket Must Be Public
- Make sure you check the **"Public bucket"** checkbox
- This allows your app to upload and download files

### ⚠️ Policies Are Required
- Without policies, even if the bucket exists, you'll get "Permission denied" errors
- The policies tell Supabase: "Allow anyone to upload/read files in this bucket"

## Visual Flow

```
User clicks camera icon
         ↓
App tries to upload image
         ↓
App looks for bucket: "files"
         ↓
❌ Bucket doesn't exist → ERROR!
         ↓
User sees error message
```

**After Fix:**
```
User clicks camera icon
         ↓
App tries to upload image
         ↓
App looks for bucket: "files"
         ↓
✅ Bucket exists → Upload succeeds!
         ↓
Image appears in profile ✅
```

## Why This Setup?

Your app uses **Firebase Auth** (for user login) but **Supabase Storage** (for file storage). This is a hybrid setup that works well, but you need to configure Supabase Storage properly.

## Still Having Issues?

If you've created the bucket but still see errors:

1. **Check bucket name**: Must be exactly `files` (lowercase)
2. **Check bucket is public**: Should have a "PUBLIC" tag
3. **Check policies exist**: Should see 2-3 policies in the Policies tab
4. **Restart app**: Always restart after making changes
5. **Check console**: Look for more specific error messages

## Summary

**The Problem**: Your app needs a storage "drawer" called `files`, but it doesn't exist yet.

**The Solution**: Create the `files` bucket in Supabase, make it public, and add policies.

**After Fix**: Profile picture uploads will work! 🎉

