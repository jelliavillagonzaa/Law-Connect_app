# 🔧 Step-by-Step: Fix "Bucket Not Found" Error

## What You Need to Do

You need to create a storage bucket named `files` in your Supabase dashboard. Follow these steps **exactly**:

---

## Step 1: Open Supabase Dashboard

1. Go to: **https://supabase.com/dashboard**
2. **Log in** to your account
3. **Click on your project** (the one with URL: `https://oonoopqyyhlwdcqnlpla.supabase.co`)
   - ✅ This is the same project - the `https://` is just the protocol prefix
   - You might see it as `oonoopqyyhlwdcqnlpla.supabase.co` or `https://oonoopqyyhlwdcqnlpla.supabase.co` - both are correct!

---

## Step 2: Go to Storage

1. In the **left sidebar**, find and click **"Storage"**
2. You should see a page with "Buckets" at the top

---

## Step 3: Create the Bucket

1. Look for a button that says **"New bucket"** (usually at the top right)
2. **Click "New bucket"**

3. A form will appear. Fill it out:
   - **Name**: Type exactly: `files` 
     - ⚠️ **IMPORTANT**: All lowercase letters, no capital letters
     - ⚠️ **NOT**: "FILES" or "Files" - must be `files`
   - **Public bucket**: ✅ **Check this box** (very important!)
   - **File size limit**: Type `10485760` (this is 10 MB)
   - **Allowed MIME types**: Leave this **empty**

4. Click **"Create bucket"** button

---

## Step 4: Verify Bucket Was Created

1. You should now see a bucket named **`files`** in your list
2. It should have a tag that says **"PUBLIC"** next to it
3. If you see "FILES" (uppercase), **delete it** and create a new one with lowercase `files`

---

## Step 5: Create Policies (Rules)

1. **Click on the `files` bucket** you just created
2. You'll see tabs at the top. Click on the **"Policies"** tab
3. You should see a button **"New policy"** - click it

### Policy 1: Allow Uploads (INSERT)

1. Click **"New policy"**
2. Select **"For full customization"** (or "Create a policy from scratch")
3. Fill in:
   - **Policy name**: `Allow public uploads`
   - **Allowed operation**: Select **INSERT** from the dropdown
   - **Policy definition**: Copy and paste this exactly:
     ```
     bucket_id = 'files'::text
     ```
   - **Policy check**: Leave this **empty**
4. Click **"Review"** then **"Save policy"**

### Policy 2: Allow Downloads (SELECT)

1. Click **"New policy"** again
2. Select **"For full customization"**
3. Fill in:
   - **Policy name**: `Allow public read`
   - **Allowed operation**: Select **SELECT** from the dropdown
   - **Policy definition**: Copy and paste this exactly:
     ```
     bucket_id = 'files'::text
     ```
   - **Policy check**: Leave this **empty**
4. Click **"Review"** then **"Save policy"**

### Policy 3: Allow Deletes (DELETE) - Optional

1. Click **"New policy"** again
2. Select **"For full customization"**
3. Fill in:
   - **Policy name**: `Allow public delete`
   - **Allowed operation**: Select **DELETE** from the dropdown
   - **Policy definition**: Copy and paste this exactly:
     ```
     bucket_id = 'files'::text
     ```
   - **Policy check**: Leave this **empty**
4. Click **"Review"** then **"Save policy"**

---

## Step 6: Verify Policies

1. In the **Policies** tab, you should now see **3 policies**:
   - `Allow public uploads` (INSERT)
   - `Allow public read` (SELECT)
   - `Allow public delete` (DELETE)

---

## Step 7: Restart Your Flutter App

1. **Stop your Flutter app** (press `Ctrl+C` in terminal, or stop it in your IDE)
2. **Start it again**:
   ```bash
   flutter run
   ```

---

## Step 8: Test It

1. **Open your app**
2. **Go to Profile screen**
3. **Click the camera icon** on your profile picture
4. **Select an image** from your phone/gallery
5. **Wait for upload**

### ✅ If It Works:
- No error message appears
- Your profile picture updates
- You see the new image

### ❌ If It Still Doesn't Work:
- Check the error message
- Make sure bucket name is exactly `files` (lowercase)
- Make sure bucket is PUBLIC
- Make sure you have at least 2 policies (INSERT and SELECT)
- Make sure you restarted the app

---

## Common Mistakes to Avoid

❌ **Wrong**: Bucket name is "FILES" (uppercase)
✅ **Correct**: Bucket name is "files" (lowercase)

❌ **Wrong**: Bucket is not public
✅ **Correct**: Bucket has "PUBLIC" tag

❌ **Wrong**: No policies created
✅ **Correct**: At least INSERT and SELECT policies exist

❌ **Wrong**: Policy definition is wrong
✅ **Correct**: Policy definition is exactly: `bucket_id = 'files'::text`

---

## Visual Checklist

Before testing, make sure:
- [ ] Bucket named `files` exists (lowercase)
- [ ] Bucket is marked as PUBLIC
- [ ] INSERT policy exists
- [ ] SELECT policy exists
- [ ] DELETE policy exists (optional)
- [ ] App has been restarted

---

## Still Having Issues?

If you've done all steps but still get errors:

1. **Check the exact error message** - what does it say?
2. **Take a screenshot** of your Supabase Storage page
3. **Check the Policies tab** - do you see 3 policies?
4. **Verify bucket name** - is it exactly `files` (lowercase)?

Let me know what you see and I'll help you fix it!

