# Sound File Setup Instructions

This guide explains how to set up the custom notification sound `alert_sound.wav` for both Android and iOS.

## Required Sound File

- **File Name**: `alert_sound.wav`
- **Format**: WAV format (recommended) or AIFF for iOS
- **Duration**: Keep it short (1-3 seconds recommended)
- **Location**: See platform-specific instructions below

## Android Setup

### Step 1: Create the raw directory
If it doesn't exist, create the following directory:
```
android/app/src/main/res/raw/
```

### Step 2: Copy the sound file
1. Place your `alert_sound.wav` file in `android/app/src/main/res/raw/`
2. The file should be named exactly: `alert_sound.wav`
3. Note: Android will automatically strip the `.wav` extension when referencing it

### Step 3: Verify
Your file structure should look like:
```
android/app/src/main/res/
  ├── raw/
  │   └── alert_sound.wav
  ├── mipmap-*/
  └── ...
```

### Android Sound File Requirements:
- Format: WAV, MP3, or OGG
- File size: Keep under 1MB for best performance
- Duration: 1-5 seconds recommended
- Sample rate: 44.1kHz or 48kHz
- Bit depth: 16-bit or 24-bit

## iOS Setup

### Step 1: Copy the sound file
1. Place your `alert_sound.wav` file in `ios/Runner/Resources/`
2. The file should be named exactly: `alert_sound.wav`
3. Alternatively, you can use AIFF format: `alert_sound.aiff`

### Step 2: Add to Xcode project
1. Open your project in Xcode
2. Right-click on `Runner` folder in the project navigator
3. Select "Add Files to Runner..."
4. Navigate to `ios/Runner/Resources/alert_sound.wav`
5. Make sure "Copy items if needed" is checked
6. Make sure "Add to targets: Runner" is checked
7. Click "Add"

### Step 3: Verify in Info.plist
The sound file should be automatically included in the app bundle. You can verify by checking that the file appears in Xcode's project navigator.

### iOS Sound File Requirements:
- Format: WAV, AIFF, CAF, or MP3
- File size: Keep under 1MB
- Duration: 1-30 seconds (but keep it short for notifications)
- Sample rate: 44.1kHz recommended
- Bit depth: 16-bit or 24-bit

## Testing the Sound

### Android:
1. Build and run the app
2. Schedule a test appointment reminder
3. Wait for the notification to trigger
4. The custom sound should play

### iOS:
1. Build and run the app on a physical device (sounds don't work in simulator)
2. Schedule a test appointment reminder
3. Wait for the notification to trigger
4. The custom sound should play

## Troubleshooting

### Android: Sound not playing
1. Check that the file is in `android/app/src/main/res/raw/alert_sound.wav`
2. Verify the file name matches exactly (case-sensitive)
3. Check Android logs: `adb logcat | grep NotificationService`
4. Ensure the notification channel is created with the sound
5. Check device volume and notification settings

### iOS: Sound not playing
1. Verify the file is in `ios/Runner/Resources/`
2. Check that it's added to the Xcode project and target
3. Ensure the file format is supported (WAV or AIFF)
4. Test on a physical device (simulator may not play sounds)
5. Check iOS notification settings in Settings > Notifications

## Alternative: Using Existing Sound File

If you already have `notification_alert.mp3` in `assets/sounds/`, you can:

1. **For Android**: Convert it to WAV and place in `res/raw/` as `alert_sound.wav`
2. **For iOS**: Convert it to WAV or AIFF and place in `Runner/Resources/`

### Online Conversion Tools:
- Use online converters like CloudConvert or Online-Convert
- Convert MP3 → WAV
- Ensure the output is 44.1kHz, 16-bit for best compatibility

## Quick Setup Script (Optional)

You can create a script to copy the sound file to both locations:

```bash
#!/bin/bash
# copy_sound.sh

# Copy to Android
cp assets/sounds/alert_sound.wav android/app/src/main/res/raw/alert_sound.wav

# Copy to iOS
cp assets/sounds/alert_sound.wav ios/Runner/Resources/alert_sound.wav

echo "Sound files copied successfully!"
```

## Notes

- The sound file must exist in both Android and iOS locations
- File names are case-sensitive
- After adding files, you may need to clean and rebuild:
  - Android: `flutter clean && flutter build apk`
  - iOS: Clean build folder in Xcode (Cmd+Shift+K)

