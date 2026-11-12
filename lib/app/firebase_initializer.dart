import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;

import '../firebase_options.dart';
import '../utils/quiet_console.dart';
import 'app_startup_state.dart';

/// Firebase init. On web this runs after first paint so the landing page is instant.
Future<void> initializeFirebaseInBackground() async {
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: options,
      ).timeout(const Duration(seconds: 20));
    } else if (!kIsWeb) {
      // Recreate the default app if native auto-init used a different API key,
      // ensuring login matches the working firebase_options key in both debug and release.
      final existing = Firebase.app();
      if (existing.options.apiKey != options.apiKey) {
        await existing.delete();
        await Firebase.initializeApp(
          options: options,
        ).timeout(const Duration(seconds: 20));
      }
    }

    // App Check: Sideloaded APKs distributed directly outside Google Play Store
    // do not support Play Integrity (Play Store installation is required).
    // Skipping Play Integrity avoids invalid App Check tokens blocking Auth and Firestore.

    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
    } catch (_) {}

    AppStartupState.markReady();
  } on TimeoutException {
    AppStartupState.markFailed();
  } catch (e) {
    AppStartupState.markFailed();
    appLog('Firebase init failed: $e', name: 'startup');
  }
}

