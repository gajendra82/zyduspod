import 'dart:async';
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

    // Compare the bundled version against the backend `app_versions` row.
    // If the running bundle is older, show a blocking "Update available"
    // dialog and do not proceed — the Refresh button is the only exit and
    // triggers a platform-appropriate hard reload.
    final outdated = await _checkVersionAndPromptIfStale();
    if (outdated) return;

    // Check if user is already logged in
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // Stockist users land on the dedicated stockist upload screen — same
      // routing rule the login flow applies, so a refresh keeps them on
      // their portal instead of bouncing them into the KAM main navigation.
      final isStockist = prefs.getBool('isStockist') ?? false;
      final stockistId = prefs.getInt('stockistId') ?? 0;
      final landing = (isStockist && stockistId > 0)
          ? AppRoutes.stockistUpload
          : AppRoutes.mainNavigation;
      Navigator.of(context).pushReplacementNamed(landing);
    } else {
      // User is not logged in, go to login screen
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }
  }

  /// Returns true when the backend reports a different version than what is
  /// bundled (and the prompt was shown). Caller must abort further
  /// navigation in that case.
  ///
  /// Per-device acknowledgement: once the user has tapped Refresh for a
  /// given backend version, that value is persisted in SharedPreferences.
  /// On subsequent launches we skip the prompt as long as the backend still
  /// advertises the same version — this breaks the re-prompt loop when the
  /// browser cache (or a stale service worker) keeps serving the old bundle
  /// even after a hard-reload.
  Future<bool> _checkVersionAndPromptIfStale() async {
    final svc = AppVersionService();
    final latest = await svc.fetchLatest();
    if (latest == null) return false; // network/server failure → skip silently
    final current = await svc.getCurrent();
    if (!svc.isOutdated(current, latest)) return false;
    final ack = await svc.getAcknowledgedVersion();
    if (ack != null && ack == latest.display) {
      // User already refreshed for this exact backend version on this device;
      // don't trap them in a loop if the cache still serves the old bundle.
      return false;
    }
    if (!mounted) return true;
    await VersionUpdateDialog.show(
      context,
      currentVersion: current.display,
      latestVersion: latest.display,
      latestInfo: latest,
    );
    return true;
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
