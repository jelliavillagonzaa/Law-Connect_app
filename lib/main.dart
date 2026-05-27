import 'dart:async' show runZonedGuarded, unawaited;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'controllers/auth_controller.dart';
import 'theme/app_theme.dart';
import 'pages/client/client_landing_page.dart';
import 'pages/staff/staff_landing_page.dart';
import 'pages/staff/staff_application_page.dart';
import 'pages/staff/staff_complete_registration_page.dart';
import 'pages/staff/staff_application_status_page.dart';
import 'pages/attorney/attorney_landing_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/signup_page.dart';
import 'pages/auth/otp_verification.dart';
import 'pages/admin/admin_dashboard.dart';
import 'pages/attorney/attorney_dashboard.dart';
import 'pages/staff/staff_dashboard.dart';
import 'screens/client/dashboard_screen_with_nav.dart';
import 'services/notification_service.dart';
import 'services/fcm_service.dart';
import 'firebase_messaging_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'supabase/supabase_bootstrap.dart';
import 'services/supabase_service.dart';
import 'utils/app_scroll_behavior.dart';
import 'utils/quiet_console.dart';

bool _isBenignFirestoreRuntimeError(Object? error) {
  if (error == null) return false;
  if (error is FirebaseException) {
    return error.code == 'permission-denied';
  }
  final s = error.toString();
  if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
    return true;
  }
  if (s.contains('Timestamp') && s.contains('is not a subtype of type')) {
    return true;
  }
  return false;
}

Future<void> _initDeferredServices() async {
  await Future<void>.delayed(const Duration(seconds: 3));

  if (isSupabaseClientReady) {
    unawaited(
      SupabaseService.instance.verifyProjectOnline().catchError((_) {}),
    );
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    unawaited(NotificationService().initialize().catchError((_) {}));
    unawaited(FCMService().initialize().catchError((_) {}));
  }
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureQuietConsole();

  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isBenignFirestoreRuntimeError(details.exception)) return;
    if (kShowFrameworkErrors) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (_isBenignFirestoreRuntimeError(error)) return true;
    if (kShowFrameworkErrors) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
    return false;
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    try {
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: !kIsWeb,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
    } catch (_) {}
  } catch (_) {}

  try {
    await initializeSupabase();
  } catch (_) {}

  Get.config(enableLog: false);
  runApp(const LawConnectApp());
  unawaited(_initDeferredServices());
}

Future<void> main() async {
  await runQuiet(_bootstrap);
}

class LawConnectApp extends StatelessWidget {
  const LawConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Law Connect',
      theme: AppTheme.lightTheme,
      scrollBehavior: const AppScrollBehavior(),
      logWriterCallback: kVerboseAppLogs
          ? null
          : (text, {bool isError = false}) {},
      initialBinding: BindingsBuilder(() {
        Get.put(AuthController(), permanent: true);
        Get.put(SupabaseService.instance, permanent: true);
      }),
      getPages: [
        GetPage(name: '/', page: () => const ClientLandingPage()),
        GetPage(name: '/ClientLanding', page: () => const ClientLandingPage()),
        GetPage(name: '/StaffLanding', page: () => const StaffLandingPage()),
        GetPage(name: '/StaffApply', page: () => const StaffApplicationPage()),
        GetPage(
          name: '/StaffCompleteRegistration',
          page: () => const StaffCompleteRegistrationPage(),
        ),
        GetPage(
          name: '/StaffApplicationStatus',
          page: () => const StaffApplicationStatusPage(),
        ),
        GetPage(
          name: '/AttorneyLanding',
          page: () => const AttorneyLandingPage(),
        ),
        GetPage(name: '/LoginPage', page: () => const LoginPage()),
        GetPage(name: '/Signup', page: () => const SignupPage()),
        GetPage(name: '/ClientSignup', page: () => const SignupPage()),
        GetPage(
          name: '/OtpVerification',
          page: () => const OtpVerificationPage(),
        ),
        GetPage(name: '/AdminDashboard', page: () => const AdminDashboard()),
        GetPage(
          name: '/AttorneyDashboard',
          page: () => const AttorneyDashboard(),
        ),
        GetPage(name: '/StaffDashboard', page: () => const StaffDashboard()),
        GetPage(
          name: '/ClientDashboard',
          page: () => const DashboardScreenWithNav(),
        ),
      ],
      unknownRoute: GetPage(
        name: '/notfound',
        page: () => const ClientLandingPage(),
      ),
      initialRoute: '/',
    );
  }
}
