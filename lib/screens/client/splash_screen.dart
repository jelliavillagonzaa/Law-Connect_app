import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../widgets/common/law_connect_logo.dart';
import '../../theme/app_theme.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  /// When false, skips the delayed navigation (useful for widget tests).
  const SplashScreen({super.key, this.autoNavigate = true});

  final bool autoNavigate;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
    if (widget.autoNavigate) {
      _navigateToLogin();
    }
  }

  void _navigateToLogin() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      // TODO: Check if user is already logged in
      // If logged in, navigate to appropriate dashboard
      Get.off(() => const LoginScreen());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo using LawConnectLogo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: AppTheme.elevatedShadow,
                ),
                child: const Center(child: LawConnectLogo(size: 80)),
              ),
              const SizedBox(height: 32),
              Text(
                'Law Connect',
                style: AppTheme.heading1.copyWith(
                  color: AppTheme.white,
                  fontSize: 32,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Professional Legal Services',
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
