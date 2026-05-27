# Google Maps Integration Setup Guide

This guide will help you set up Google Maps in your Flutter app with the OroquietaMapPicker widget.

## Prerequisites

1. Google Cloud Platform (GCP) account
2. Flutter SDK installed
3. Android Studio / Xcode (for platform-specific setup)

## Step 1: Get Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the following APIs:
   - **Maps SDK for Android**
   - **Maps SDK for iOS**
   - **Geocoding API**
   - **Places API** (required for location search functionality)

4. Go to **Credentials** → **Create Credentials** → **API Key**
5. Copy your API key

## Step 2: Configure Android

### 2.1 Update AndroidManifest.xml

The file is located at: `android/app/src/main/AndroidManifest.xml`

**Already configured!** Just replace `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
```

### 2.2 Restrict API Key (Recommended)

1. Go to Google Cloud Console → Credentials
2. Click on your API key
3. Under **Application restrictions**, select **Android apps**
4. Click **Add an item**
5. Enter your package name: `com.example.law_connect`
6. Add your app's SHA-1 certificate fingerprint

To get SHA-1:
```bash
# Debug keystore
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# Release keystore (if you have one)
keytool -list -v -keystore your-release-key.keystore
```

## Step 3: Configure iOS

### 3.1 Update Info.plist

The file is located at: `ios/Runner/Info.plist`

Add the following keys (if not already present):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show your position on the map</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>We need your location to show your position on the map</string>

<key>io.flutter.embedded_views_preview</key>
<true/>
```

### 3.2 Update AppDelegate.swift

The file is located at: `ios/Runner/AppDelegate.swift`

Add the Google Maps import at the top:

```swift
import GoogleMaps
```

In the `application:didFinishLaunchingWithOptions:` method, add:

```swift
GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
```

### 3.3 Restrict API Key for iOS

1. Go to Google Cloud Console → Credentials
2. Click on your API key
3. Under **Application restrictions**, select **iOS apps**
4. Add your bundle identifier: `com.example.lawConnect` (check your actual bundle ID)

## Step 4: Configure Google Places API Key

The map picker includes a Google Places search bar that requires a Places API key.

1. **Get your Places API key** (same key from Step 1, or create a separate one)
2. **Update the API key in code:**
   - Open `lib/widgets/maps/oroquieta_map_picker.dart`
   - Find the line: `static const String _placesApiKey = 'YOUR_GOOGLE_PLACES_API_KEY';`
   - Replace `YOUR_GOOGLE_PLACES_API_KEY` with your actual Places API key

   **Note:** For production, consider storing the API key in:
   - Environment variables
   - Secure storage (flutter_secure_storage)
   - Firebase Remote Config
   - Or pass it as a parameter to the widget

3. **Restrict the API key** (recommended):
   - Go to Google Cloud Console → Credentials
   - Click on your API key
   - Under **API restrictions**, select "Restrict key"
   - Enable only: **Places API**, **Maps SDK for Android**, **Maps SDK for iOS**, **Geocoding API**

## Step 5: Install Dependencies

Run the following command to install all required packages:

```bash
flutter pub get
```

The following packages are already added to `pubspec.yaml`:
- `google_maps_flutter: ^2.9.0`
- `geolocator: ^12.0.0`
- `geocoding: ^3.0.0`
- `permission_handler: ^11.3.1`

## Step 6: Testing

1. **Run the app:**
   ```bash
   flutter run
   ```

2. **Test the map picker:**
   - Go to Admin Profile or Attorney Profile
   - Click "Edit" in Additional Details section
   - Click "Select Location on Map"
   - The map should load centered on Oroquieta City
   - **Test Places Search:**
     - Type in the search bar at the top (e.g., "City Hall", "Market")
     - You should see autocomplete suggestions for Oroquieta City locations
     - Select a suggestion to move the camera and place a marker
   - Tap on the map to drop a marker
   - Click "Confirm Location" to save

3. **Test location permissions:**
   - Click the "Use My Location" button (top right)
   - Grant location permissions when prompted
   - The map should center on your current location

## Usage Example

### From any screen:

```dart
import 'package:law_connect/widgets/maps/oroquieta_map_picker.dart';

// Open map picker
final result = await Navigator.push<MapPickerResult>(
  context,
  MaterialPageRoute(
    builder: (context) => OroquietaMapPicker(
      initialLatitude: 8.4885,  // Optional
      initialLongitude: 123.8047, // Optional
    ),
  ),
);

// Handle the result
if (result != null) {
  print('Latitude: ${result.latitude}');
  print('Longitude: ${result.longitude}');
  print('Address: ${result.address}');
  
  // Save to Firestore
  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .update({
    'latitude': result.latitude,
    'longitude': result.longitude,
    'mapsAddress': result.address,
  });
}
```

### Converting coordinates to address:

```dart
import 'package:law_connect/widgets/maps/oroquieta_map_picker.dart';

final address = await convertCoordinatesToAddress(8.4885, 123.8047);
print('Address: $address');
```

## Features

✅ **Embedded Google Map** - Full map widget inside your app
✅ **Google Places Search** - Search bar with autocomplete for Oroquieta City locations
✅ **Location Filtering** - Only shows suggestions within Oroquieta City
✅ **Oroquieta City Center** - Default location (8.4885, 123.8047)
✅ **Zoom Restrictions** - Between 13-18 zoom levels
✅ **Marker Placement** - Tap anywhere to drop/update marker
✅ **Draggable Marker** - Drag marker to fine-tune position
✅ **Current Location** - "Use My Location" button with permissions
✅ **Geocoding** - Automatic address conversion from coordinates
✅ **Responsive Design** - Works on web, mobile, and tablet
✅ **Color Scheme** - Uses app colors (#CD5656, #AF3E3E)

## Troubleshooting

### Map doesn't show / Blank screen

1. Check that your API key is correctly set in AndroidManifest.xml (Android) or AppDelegate.swift (iOS)
2. Verify that Maps SDK is enabled in Google Cloud Console
3. Check API key restrictions match your app's package/bundle ID
4. Review console logs for error messages

### Location permission denied

1. Check Info.plist has location permission descriptions (iOS)
2. Check AndroidManifest.xml has location permissions
3. Test on a physical device (location services may not work on emulators)
4. Ensure location services are enabled on the device

### Address not loading

1. Verify Geocoding API is enabled in Google Cloud Console
2. Check your API key has access to Geocoding API
3. Check internet connection
4. Review error logs

### Places search not working

1. Verify Places API is enabled in Google Cloud Console
2. Check that you've updated `_placesApiKey` in `oroquieta_map_picker.dart`
3. Ensure your API key has Places API access
4. Check that the API key is not restricted to specific IPs (for mobile apps)
5. Review console logs for API errors
6. Make sure you're searching for places that exist in Oroquieta City

### Build errors

1. Run `flutter clean`
2. Run `flutter pub get`
3. For iOS: `cd ios && pod install && cd ..`
4. Try `flutter run` again

## Firestore Storage Structure

When saving coordinates, store them like this:

```dart
{
  'latitude': 8.4885,
  'longitude': 123.8047,
  'mapsAddress': 'Street, Barangay, Oroquieta City, Misamis Occidental, Philippines',
  'updatedAt': FieldValue.serverTimestamp(),
}
```

## Security Best Practices

1. **Restrict API Keys**: Always restrict your API keys to specific apps/bundles
2. **Billing Alerts**: Set up billing alerts in GCP to monitor usage
3. **Key Rotation**: Regularly rotate API keys
4. **Environment Variables**: For production, consider using environment variables or secure storage

## Support

For issues or questions:
- Check Google Maps Flutter documentation: https://pub.dev/packages/google_maps_flutter
- Check Geolocator documentation: https://pub.dev/packages/geolocator
- Check Geocoding documentation: https://pub.dev/packages/geocoding

---

**Note**: Remember to replace `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key in both AndroidManifest.xml and AppDelegate.swift files.

