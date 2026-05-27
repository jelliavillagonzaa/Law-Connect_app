import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

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
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
    _navigateToLogin();
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
              // Logo mark: Shield + Scale + Initial
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: AppTheme.elevatedShadow,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Shield
                    Icon(
                      Icons.shield,
                      size: 60,
                      color: AppTheme.navy,
                    ),
                    // Scale
                    Positioned(
                      bottom: 20,
                      child: Icon(
                        Icons.balance,
                        size: 30,
                        color: AppTheme.gold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'JurisLink',
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

