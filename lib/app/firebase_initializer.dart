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
    } else if (!kIsWeb && kDebugMode) {
      // google-services.json may auto-init first with the SHA-restricted Android
      // key. Recreate the default app so debug login matches firebase_options.
      final existing = Firebase.app();
      if (existing.options.apiKey != options.apiKey) {
        await existing.delete();
        await Firebase.initializeApp(
          options: options,
        ).timeout(const Duration(seconds: 20));
      }
    }

    // App Check on mobile only in release — debug builds skip it so Firestore reads work
    // without registering a debug token (web never uses App Check here).
    if (!kIsWeb && kReleaseMode) {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.appAttest,
        );
      } catch (e) {
        if (kDebugMode) {
          appLog('App Check activate skipped: $e', name: 'startup');
        }
      }
    }

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

