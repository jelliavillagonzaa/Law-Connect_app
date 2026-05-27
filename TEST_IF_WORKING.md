# ✅ Test: Is Supabase Storage Working?

## Quick Test Steps

1. **Open your Flutter app**
2. **Go to Profile screen**
3. **Click the camera icon** (to change profile picture)
4. **Select an image**
5. **Wait for upload**

## What Should Happen

### ✅ If Working:
- Image uploads successfully
- No error message appears
- Profile picture updates
- You see the new image in your profile

### ❌ If Not Working:
- Red error banner appears
- Error message shows (e.g., "bucket not found" or "permission denied")

## Check Supabase Dashboard

1. Go to **Supabase Dashboard** → **Storage** → **Buckets**
2. Click on the **`files`** bucket
3. Go to **Files** tab
4. You should see a folder: `profile_photos/`
5. Inside should be your uploaded image

## If Still Not Working

Check these:
- [ ] Bucket name is exactly `files` (lowercase)
- [ ] Bucket is marked as **PUBLIC**
- [ ] You have at least 2 policies (INSERT and SELECT)
- [ ] You restarted the app after creating the bucket

---

**Answer**: Test it now and let me know what happens!

