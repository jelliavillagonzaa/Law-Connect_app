# 🔍 How to Check Your Bucket Name

## Quick Check:

1. In your Supabase dashboard, go to **Storage** → **Buckets**
2. Look at the actual bucket name (not just the display)
3. The bucket name should be exactly: `files` (lowercase)

## If the bucket name is "FILES" (uppercase):

You have two options:

### Option 1: Rename the bucket (Recommended)
1. Delete the current "FILES" bucket
2. Create a new bucket with the name exactly: `files` (lowercase)
3. Make it Public
4. Recreate the policies

### Option 2: Update the code to use "FILES"
- Change all instances of `'files'` to `'FILES'` in the code
- But this is NOT recommended - stick with lowercase "files"

## Your Current Setup:
✅ Bucket exists and is PUBLIC
✅ SELECT policy exists
✅ INSERT policy exists
⚠️ Need to verify bucket name is lowercase "files"

---

**The code expects**: `'files'` (lowercase)
**Make sure your bucket is named**: `files` (lowercase)

