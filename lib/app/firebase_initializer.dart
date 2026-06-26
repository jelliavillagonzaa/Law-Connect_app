import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;

import '../firebase_options.dart';
import '../utils/quiet_console.dart';
import 'app_startup_state.dart';

/// Firebase init — must complete before runApp (Auth uses Firebase on first screen).
Future<void> initializeFirebaseInBackground() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 20));
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
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: !kIsWeb,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
    } catch (_) {}

    AppStartupState.firebaseReady = true;
  } on TimeoutException {
    AppStartupState.firebaseReady = false;
  } catch (e) {
    AppStartupState.firebaseReady = false;
    appLog('Firebase init failed: $e', name: 'startup');
  }
}

