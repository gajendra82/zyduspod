import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/routes.dart';
import 'package:zyduspod/services/app_version_service.dart';
import 'package:zyduspod/widgets/version_update_dialog.dart';

const String _splashLogoAsset = 'assets/branding/logo1.jpeg';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
      ),
    );

    // Start animation
    _animationController.forward();

    // Navigate after splash duration
    _navigateAfterSplash();
  }

  Future<void> _navigateAfterSplash() async {
    // Wait for splash screen to show for at least 3 seconds
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // iOS only: prompt the user to update via the App Store when the
    // backend advertises a newer version. The dialog is dismissible — App
    // Store updates can't be forced from inside the app, so we don't lock
    // the UI; tap "Later" persists an ack to avoid re-prompting on every
    // cold start until the admin bumps the row again.
    if (Platform.isIOS) {
      await _checkVersionAndPromptIfStale();
      if (!mounted) return;
    }

    // Check if user is already logged in
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // User is logged in, go to main navigation
      Navigator.of(context).pushReplacementNamed(AppRoutes.mainNavigation);
    } else {
      // User is not logged in, go to login screen
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }
  }

  /// Compare bundled version against the backend `app_versions` row. If
  /// outdated, surface the iOS "Update Available" dialog (dismissible —
  /// App Store updates can't be forced from inside the app, so we don't
  /// block the user). Per-device ack prevents re-prompting on every cold
  /// start for the same backend version; admin bumping the row again
  /// re-fires the dialog because the ack no longer matches.
  Future<void> _checkVersionAndPromptIfStale() async {
    final svc = AppVersionService();
    final latest = await svc.fetchLatest();
    if (latest == null) return;
    final current = await svc.getCurrent();
    if (!svc.isOutdated(current, latest)) return;
    final ack = await svc.getAcknowledgedVersion();
    if (ack != null && ack == latest.display) return;
    if (!mounted) return;
    await VersionUpdateDialog.show(
      context,
      currentVersion: current.display,
      latestVersion: latest.display,
      latestInfo: latest,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF00A0A8),
              const Color(0xFF6EC1C7),
              const Color(0xFFB24B9E),
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          _splashLogoAsset,
                          height: 120,
                          width: 120,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),

              // App Title
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        const Text(
                          'Zydus Vistaar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Proof of Delivery Management',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 60),

              // Loading Indicator
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  'Powered by Globalspace Technology Ltd',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
