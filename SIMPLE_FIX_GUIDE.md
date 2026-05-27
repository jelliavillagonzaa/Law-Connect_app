# 🎯 Simple Fix Guide - Follow These Steps

## The Problem
Your app is looking for a storage "drawer" called `files`, but it doesn't exist in Supabase.

## The Solution
Create the `files` bucket in Supabase. Here's how:

---

## 📋 Step-by-Step Instructions

### STEP 1: Open Supabase
1. Go to: **https://supabase.com/dashboard**
2. Log in
3. Click your project (the one with URL: `https://oonoopqyyhlwdcqnlpla.supabase.co`)
   - ✅ Same project - `https://` is just the protocol prefix

### STEP 2: Go to Storage
1. Click **"Storage"** in the left menu
2. You'll see "Buckets" page

### STEP 3: Create Bucket
1. Click **"New bucket"** button (top right)
2. Fill the form:
   ```
   Name: files
   Public bucket: ✅ (check this!)
   File size limit: 10485760
   ```
3. Click **"Create bucket"**

### STEP 4: Add Rules (Policies)
1. Click the **`files`** bucket you just created
2. Click **"Policies"** tab
3. Click **"New policy"** (do this 3 times)

**Policy 1:**
- Name: `Allow public uploads`
- Operation: **INSERT**
- Definition: `bucket_id = 'files'::text`

**Policy 2:**
- Name: `Allow public read`
- Operation: **SELECT**
- Definition: `bucket_id = 'files'::text`

**Policy 3:**
- Name: `Allow public delete`
- Operation: **DELETE**
- Definition: `bucket_id = 'files'::text`

### STEP 5: Restart App
1. Stop your app
2. Run: `flutter run`
3. Try uploading a profile picture

---

## ✅ Done!

After these steps, your profile picture upload should work!

