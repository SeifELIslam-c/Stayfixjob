import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AppLaunchScreen extends StatefulWidget {
  final Widget nextScreen;

  const AppLaunchScreen({super.key, required this.nextScreen});

  @override
  State<AppLaunchScreen> createState() => _AppLaunchScreenState();
}

class _AppLaunchScreenState extends State<AppLaunchScreen> {
  static const _heroBlue = Color(0xFF0F63FF);
  static const _heroBlueDark = Color(0xFF1C4FCE);
  static const _cardBackground = Color(0xFFFDFEFF);
  static const _headingColor = Color(0xFF13203F);
  static const _bodyColor = Color(0xFF7C8BA8);

  Timer? _navigationTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _scheduleNavigation(const Duration(milliseconds: 3200));
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  void _scheduleNavigation(Duration duration) {
    _navigationTimer?.cancel();
    _navigationTimer = Timer(duration, _goNext);
  }

  void _goNext() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF1F6FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F8FF), Color(0xFFEAF1FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ultraCompact = constraints.maxHeight < 760;
            final heroHeight = (constraints.maxHeight * 0.50).clamp(
              340.0,
              470.0,
            );
            final animationSize = (constraints.maxWidth * 0.80).clamp(
              260.0,
              390.0,
            );

            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _buildHero(
                    heroHeight: heroHeight,
                    animationSize: animationSize,
                    ultraCompact: ultraCompact,
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      transform: Matrix4.translationValues(0, -24, 0),
                      decoration: const BoxDecoration(
                        color: _cardBackground,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x140F63FF),
                            blurRadius: 28,
                            offset: Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          ultraCompact ? 22 : 26,
                          ultraCompact ? 14 : 18,
                          ultraCompact ? 22 : 26,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bienvenue',
                              style: TextStyle(
                                color: _heroBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: ultraCompact ? 13 : 14,
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 4 : 6),
                            Text(
                              'StayFix Job',
                              style: TextStyle(
                                color: _headingColor,
                                fontSize: ultraCompact ? 34 : 38,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.1,
                                height: 1.02,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Votre travail. Notre priorite.',
                              style: TextStyle(
                                color: _bodyColor,
                                fontSize: ultraCompact ? 14 : 15,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 16 : 20),
                            Container(
                              width: 64,
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_heroBlue, Color(0xFF52B6FF)],
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const Spacer(),
                            _buildLoadingCard(ultraCompact),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero({
    required double heroHeight,
    required double animationSize,
    required bool ultraCompact,
  }) {
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_heroBlue, _heroBlueDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -18,
            right: -12,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            left: -34,
            bottom: 32,
            child: Container(
              width: 210,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.02),
                  _heroBlue.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ultraCompact ? 20 : 24,
                ultraCompact ? 8 : 12,
                ultraCompact ? 20 : 24,
                0,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'lib/assets/icon/stayfixjob.png',
                        width: ultraCompact ? 42 : 48,
                        height: ultraCompact ? 42 : 48,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: ultraCompact ? 24 : 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                  color: Colors.white,
                                ),
                                children: const [
                                  TextSpan(text: 'StayFix'),
                                  TextSpan(
                                    text: 'Job',
                                    style: TextStyle(color: Color(0xFF24C2FF)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Votre travail. Notre priorite.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: ultraCompact ? 13 : 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: animationSize,
                    height: animationSize,
                    child: Lottie.asset(
                      'lib/assets/Office worker team work hello office waves.json',
                      fit: BoxFit.contain,
                      repeat: false,
                      onLoaded: (composition) {
                        final duration = composition.duration;
                        final launchDuration =
                            duration < const Duration(milliseconds: 2600)
                            ? const Duration(milliseconds: 2600)
                            : duration + const Duration(milliseconds: 180);
                        _scheduleNavigation(launchDuration);
                      },
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            child: Container(
              height: 22,
              decoration: const BoxDecoration(
                color: _cardBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard(bool ultraCompact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ultraCompact ? 16 : 18,
        vertical: ultraCompact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE7FA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F163B7A),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_heroBlue, _heroBlueDark],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preparation de votre espace',
                  style: TextStyle(
                    color: _headingColor,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Color(0xFFE4ECFA),
                    valueColor: AlwaysStoppedAnimation<Color>(_heroBlue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
