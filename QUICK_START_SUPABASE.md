# Quick Start: Supabase Integration

## ✅ What's Been Done

Your Law Connect app has been integrated with Supabase for:
- ✅ Profile image uploads
- ✅ Chat attachment uploads  
- ✅ Case document uploads
- ✅ Attorney license uploads

## 🚀 Quick Setup (3 Steps)

### 1. Get Your Supabase Credentials
1. Go to https://supabase.com → Create/Open your project
2. Go to **Settings** → **API**
3. Copy your **Project URL** and **anon/public key**

### 2. Configure the App
Open `lib/config/supabase_config.dart` and replace:
```dart
static const String supabaseUrl = 'YOUR_SUPABASE_PROJECT_URL';
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```
With your actual values.

### 3. Create Storage Bucket
1. In Supabase dashboard → **Storage**
2. Click **"New bucket"**
3. Name: `files`
4. ✅ Enable **"Public bucket"**
5. Click **"Create bucket"**
6. Go to **Policies** tab → Add these policies:

**Policy 1: Allow Uploads**
- Operation: `INSERT`
- Policy: `(bucket_id = 'files'::text) AND (auth.role() = 'authenticated'::text)`

**Policy 2: Allow Reads**
- Operation: `SELECT`  
- Policy: `bucket_id = 'files'::text`

## 📝 Files Modified

- `lib/config/supabase_config.dart` - Supabase configuration
- `lib/main.dart` - Supabase initialization
- `lib/services/supabase_storage_service.dart` - New storage service
- `lib/services/profile_service.dart` - Updated to use Supabase
- `lib/services/storage_service.dart` - Updated to use Supabase
- `lib/services/chat_service.dart` - Updated to use Supabase

## 🧪 Test It

1. Run: `flutter pub get`
2. Run: `flutter run`
3. Try uploading a profile picture
4. Check Supabase Storage dashboard to see the file

## 📚 Full Guide

See `SUPABASE_INTEGRATION_GUIDE.md` for detailed instructions.

