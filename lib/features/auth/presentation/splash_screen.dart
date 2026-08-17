// lib/features/auth/presentation/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../loans/data/loan_repository.dart';
import '../data/auth_service.dart';
import 'auth_gate.dart';

class SplashScreen extends StatefulWidget {
  final AuthService authService;
  final LoanRepository loanRepository;
  final NotificationsRepository notificationsRepository;

  const SplashScreen({
    super.key,
    required this.authService,
    required this.loanRepository,
    required this.notificationsRepository,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _frameAnimation;
  
  // You have 32 frames (000 to 031)
  final int _frameCount = 32;

  @override
  void initState() {
    super.initState();
    
    // Play the animation over 2 seconds
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _frameAnimation = IntTween(begin: 0, end: _frameCount - 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );

    // Start the animation and wait for it to finish
    _controller.forward().then((_) {
      // Once the animation completes, navigate to the AuthGate
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => AuthGate(
              authService: widget.authService,
              loanRepository: widget.loanRepository,
              notificationsRepository: widget.notificationsRepository,
            ),
            // Add a smooth fade transition to the next screen
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: scheme.surface,
      // backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    scheme.primary.withValues(alpha: 0.15),
                    AppColors.darkBg,
                  ],
                ),
              ),
            ),
          ),
          
          // Animated SVG Sequence
          Center(
            child: AnimatedBuilder(
              animation: _frameAnimation,
              builder: (context, child) {
                // Pad the index with leading zeros (000, 001, ..., 031)
                final frameIndex = _frameAnimation.value.toString().padLeft(3, '0');
                
                return SvgPicture.asset(
                  'assets/animations/splash_animation/loan_19005121_$frameIndex.svg',
                  width: 120, // Adjust size as needed
                  height: 120,
                  colorFilter: ColorFilter.mode(scheme.primary, BlendMode.srcIn),
                );
              },
            ),
          ),
          
          // Optional: Brand Text at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Text(
                'AEC',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}