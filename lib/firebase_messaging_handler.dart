import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Top-level function for handling background messages
/// This must be a top-level function, not a class method
/// 
/// IMPORTANT: This function must be registered in main.dart:
/// FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();
  
  if (kDebugMode) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('📨 BACKGROUND MESSAGE RECEIVED');
    debugPrint('═══════════════════════════════════════');
    debugPrint('📋 Title: ${message.notification?.title}');
    debugPrint('📝 Body: ${message.notification?.body}');
    debugPrint('📦 Data: ${message.data}');
    debugPrint('═══════════════════════════════════════');
  }
  
  // Save notification to Firestore
  try {
    final firestore = FirebaseFirestore.instance;
    final userId = message.data['userId'] as String?;
    
    if (userId != null && userId.isNotEmpty) {
      await firestore.collection('notifications').add({
        'userId': userId,
        'clientId': userId,
        'title': message.notification?.title ?? 'Notification',
        'message': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': message.data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) {
        debugPrint('✅ Background notification saved to Firestore for user: $userId');
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ No userId found in background message data');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Error saving background notification: $e');
    }
  }
}

