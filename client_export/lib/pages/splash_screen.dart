import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import '../widgets/common/law_connect_logo.dart';
import 'client/client_landing_page.dart';
import 'auth/otp_verification.dart';
import 'attorney/attorney_dashboard.dart';
import 'admin/admin_dashboard.dart';
import 'staff/staff_dashboard.dart';
import '../screens/client/dashboard_screen_with_nav.dart';
import '../services/appointment_reminder_service.dart';
import '../services/deadline_reminder_service.dart';

class SplashScreen extends StatefulWidget {
  /// If false, the screen will NOT automatically navigate after a delay.
  /// This is useful for widget tests and local rendering.
  const SplashScreen({super.key, this.autoNavigate = true});

  final bool autoNavigate;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<Offset> _taglineSlideAnimation;
  late Animation<double> _taglineFadeAnimation;
  Timer? _autoNavigateTimer;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _taglineSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _taglineFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );

    // Start animations
    _animationController.forward();

    // Auto-navigate after 3 seconds (disabled in widget tests)
    if (widget.autoNavigate) {
      _autoNavigateTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _navigateToNext();
        }
      });
    }
  }

  Future<void> _navigateToNext() async {
    if (!mounted) return;

    try {
      // Check authentication state (wrap in try/catch so the splash screen
      // never crashes if Firebase failed to initialize).
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        // Not logged in - client-facing landing, then sign-in / register
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Get.offAll(() => const ClientLandingPage());
          }
        });
        return;
      }

      // User is logged in - check role and verification
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final role = userData['role'] ?? 'client';
        final isVerified = userData['isVerified'] ?? false;

        // Start appointment reminder service for admins, attorneys, and staff
        if (role == 'admin' || role == 'attorney' || role == 'staff') {
          try {
            final reminderService = AppointmentReminderService();
            reminderService.startReminderCheck();
          } catch (e) {
            // Ignore errors - reminder service is optional
          }
        }

        // Start deadline reminder service for ALL users (staff, attorney, clients, admin)
        // All users need deadline reminders for their cases/deadlines
        try {
          final deadlineReminderService = DeadlineReminderService();
          deadlineReminderService.startDeadlineReminderCheck();
        } catch (e) {
          // Ignore errors - deadline reminder service is optional
        }

        if (!mounted) return;

        // Navigate after frame is complete to avoid disposed view errors
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (role == 'admin') {
            Get.offAll(() => const AdminDashboard());
          } else if (role == 'attorney') {
            Get.offAll(() => const AttorneyDashboard());
          } else if (role == 'staff') {
            Get.offAll(() => const StaffDashboard());
          } else if (role == 'client') {
            if (isVerified) {
              // Route verified clients to the newer dashboard with navigation.
              Get.offAll(() => const DashboardScreenWithNav());
            } else {
              Get.offAll(() => const OtpVerificationPage());
            }
          } else {
            Get.offAll(() => const ClientLandingPage());
          }
        });
      } else {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Get.offAll(() => const ClientLandingPage());
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Get.offAll(() => const ClientLandingPage());
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _autoNavigateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive sizing based on screen size and platform
    final screenSize = MediaQuery.of(context).size;
    final isWeb = kIsWeb;
    final isTablet = screenSize.width > 600 && screenSize.width < 1200;
    final isMobile = screenSize.width <= 600;

    // Calculate responsive sizes
    final logoSize = isWeb
        ? (isTablet ? 140.0 : 160.0)
        : (isMobile ? 120.0 : 140.0);
    final titleFontSize = isWeb
        ? (isTablet ? 42.0 : 48.0)
        : (isMobile ? 32.0 : 36.0);
    final taglineFontSize = isWeb
        ? (isTablet ? 18.0 : 20.0)
        : (isMobile ? 14.0 : 16.0);
    final spacing = isWeb ? 32.0 : 24.0;
    final taglineSpacing = isWeb ? 20.0 : 16.0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A4D8F), // Royal Blue Top
              Color(0xFF0F2E57), // Royal Blue Bottom
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWeb ? 600 : double.infinity,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo with fade and scale animation
                  ScaleTransition(
                    scale: _logoScaleAnimation,
                    child: FadeTransition(
                      opacity: _logoFadeAnimation,
                      child: Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color.fromARGB(
                                255,
                                195,
                                183,
                                183,
                              ).withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Builder(
                          builder: (context) {
                            // On web we can load the file placed at /log.png (in web/ folder)
                            if (isWeb) {
                              return Image.network(
                                '/log.png',
                                width: logoSize,
                                height: logoSize,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) {
                                  return LawConnectLogo(
                                    size: logoSize,
                                    color: Colors.white,
                                    goldColor: const Color(0xFFF1C40F),
                                    showGlow: true,
                                  );
                                },
                              );
                            }

                            // On mobile/desktop try to load an app asset at assets/logo.png
                            return Image.asset(
                              'assets/logo.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, stack) {
                                return LawConnectLogo(
                                  size: logoSize,
                                  color: Colors.white,
                                  goldColor: const Color(0xFFF1C40F),
                                  showGlow: true,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: spacing),
                  // Law Connect Text with enhanced styling
                  FadeTransition(
                    opacity: _logoFadeAnimation,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFE8E8E8)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: Text(
                        'Law Connect',
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2.0,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.3),
                              offset: const Offset(0, 4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  SizedBox(height: taglineSpacing),
                  // Tagline with slide and fade animation
                  SlideTransition(
                    position: _taglineSlideAnimation,
                    child: FadeTransition(
                      opacity: _taglineFadeAnimation,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWeb ? 40 : 32,
                        ),
                        child: Text(
                          'Where Cases Meet Their Best Match.',
                          style: TextStyle(
                            fontSize: taglineFontSize,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFFF1C40F),
                            letterSpacing: 0.8,
                            height: 1.5,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.2),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: spacing * 2),
                  // Loading indicator
                  FadeTransition(
                    opacity: _taglineFadeAnimation,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFFF1C40F).withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
