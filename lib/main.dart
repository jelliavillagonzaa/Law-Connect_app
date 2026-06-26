import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'app/firebase_initializer.dart';
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
import 'routes/deferred_route_loaders.dart';
import 'services/notification_service.dart';
import 'services/fcm_service.dart';
import 'firebase_messaging_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'supabase/supabase_bootstrap.dart';
import 'services/supabase_service.dart';
import 'utils/app_scroll_behavior.dart';
import 'utils/quiet_console.dart';

Future<void> _initDeferredServices() async {
  try {
    await initializeSupabase().timeout(const Duration(seconds: 8));
  } on TimeoutException {
    // Optional backend — never block UI.
  } catch (_) {}

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
  installQuietErrorHandlers();
  Get.config(enableLog: false);

  // Firebase must be ready before runApp — LoginPage/AuthService use it on first frame.
  await initializeFirebaseInBackground();

  runApp(const LawConnectApp());
  unawaited(_initDeferredServices());
  if (kIsWeb) {
    unawaited(DeferredClientDashboard.prefetch());
    unawaited(DeferredClientNotificationsScreen.prefetch());
  }
}

Future<void> main() async {
  await runQuietApp(_bootstrap);
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
        Get.lazyPut<AuthController>(() => AuthController(), fenix: true);
        Get.lazyPut<SupabaseService>(() => SupabaseService.instance, fenix: true);
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
        GetPage(
          name: '/AdminDashboard',
          page: () => const DeferredAdminDashboard(),
        ),
        GetPage(
          name: '/AttorneyDashboard',
          page: () => const DeferredAttorneyDashboard(),
        ),
        GetPage(
          name: '/StaffDashboard',
          page: () => const DeferredStaffDashboard(),
        ),
        GetPage(
          name: '/ClientDashboard',
          page: () => const DeferredClientDashboard(),
        ),
        GetPage(
          name: '/ClientNotifications',
          page: () => const DeferredClientNotificationsScreen(),
        ),
      ],
      unknownRoute: GetPage(
        name: '/notfound',
        page: () => const ClientLandingPage(),
      ),
      initialRoute: kIsWeb ? '/' : '/LoginPage',
    );
  }
}
