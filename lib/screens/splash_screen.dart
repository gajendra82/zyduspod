import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/config.dart';
import 'package:zydus_vistaar/routes.dart';
import 'package:zydus_vistaar/services/app_version_service.dart';
import 'package:zydus_vistaar/widgets/version_update_dialog.dart';

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

    // SSO handoff: Laravel-side redirects in here with
    //   ?auth_handoff=<single-use-token>[&to=upload]
    // when the user clicks "Upload POD" while logged into the Blade
    // dashboard. Exchange the token for a Sanctum bearer BEFORE the normal
    // token-presence check so we land logged-in even if SharedPreferences
    // is empty.
    final handoff = await _consumeHandoffTokenIfPresent();
    if (!mounted) return;
    if (handoff != null) {
      Navigator.of(context).pushReplacementNamed(handoff);
      return;
    }

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

  /// Read `?auth_handoff=...&to=...` from the current URL (web only — on
  /// mobile this is always null because the user can't reach the splash
  /// via a deep-link with these params). POST the token to the backend's
  /// exchange endpoint. On success, store the returned Sanctum bearer in
  /// SharedPreferences (same key the regular login uses) and return the
  /// route the caller should navigate to. Returns null when there is no
  /// handoff token, or when the exchange failed and we want to fall
  /// through to the regular login flow.
  Future<String?> _consumeHandoffTokenIfPresent() async {
    final params = Uri.base.queryParameters;
    final handoffToken = params['auth_handoff'];
    if (handoffToken == null || handoffToken.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.parse('${API_BASE_URL}auth/handoff/exchange');
      final resp = await http.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'handoff_token': handoffToken}),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[HANDOFF] exchange HTTP ${resp.statusCode}: ${resp.body}');
        }
        return null;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final data = body['data'] as Map<String, dynamic>;
      final bearer = (data['token'] ?? '').toString();
      if (bearer.isEmpty) return null;

      final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? const {};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('authToken', bearer);
      if (user['name'] != null) {
        await prefs.setString('userName', user['name'].toString());
      }
      if (user['email'] != null) {
        await prefs.setString('userEmail', user['email'].toString());
      }
      if (user['id'] != null) {
        await prefs.setInt('userId', int.tryParse(user['id'].toString()) ?? 0);
      }

      // Mirror the regular login flow's stockist handling: the SSO handoff
      // response uses the same backend user-resolution path, so it carries
      // is_stockist + stockist payload for stockist accounts. Without
      // persisting these, a stockist who clicks "Upload POD" on the Blade
      // dashboard lands in the KAM MainNavigation and gets the wrong
      // upload screen. Accept the fields from either the top-level body or
      // the nested data block to stay tolerant of response shape.
      final isStockist = (data['is_stockist'] == true) ||
          (body['is_stockist'] == true);
      await prefs.setBool('isStockist', isStockist);
      if (isStockist) {
        final stockist = (data['stockist'] ?? body['stockist']);
        if (stockist is Map) {
          await prefs.setInt(
            'stockistId',
            (stockist['id'] is int)
                ? stockist['id']
                : int.tryParse('${stockist['id'] ?? ''}') ?? 0,
          );
          await prefs.setString('stockistName', '${stockist['name'] ?? ''}');
          await prefs.setString('stockistCode', '${stockist['code'] ?? ''}');
        }
      } else {
        await prefs.remove('stockistId');
        await prefs.remove('stockistName');
        await prefs.remove('stockistCode');
      }

      // Route by role. KAMs continue landing on the normal dashboard
      // (matches the standard Flutter login flow with only the password
      // prompt skipped). Stockists go to the dedicated stockist upload
      // shell — same rule as the regular login flow.
      final stockistId = prefs.getInt('stockistId') ?? 0;
      if (isStockist && stockistId > 0) {
        return AppRoutes.stockistUpload;
      }
      return AppRoutes.mainNavigation;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HANDOFF] exchange failed: $e');
      }
      return null;
    }
  }

  /// Returns true when the backend reports a different version than what is
  /// bundled (and the prompt was shown). Caller must abort further
  /// navigation in that case.
  Future<bool> _checkVersionAndPromptIfStale() async {
    final svc = AppVersionService();
    final latest = await svc.fetchLatest();
    if (latest == null) return false;

    final current = await svc.getCurrent();

    // Deployed bundle is newer than DB — self-heal app_versions, no prompt.
    if (svc.isAheadOfServer(current, latest)) {
      await svc.syncAheadBundleIfNeeded(current, latest);
      await svc.acknowledge(current);
      return false;
    }

    // Up to date — continue.
    if (!svc.needsUpdate(current, latest)) {
      await svc.acknowledge(latest);
      return false;
    }

    // Installed bundle is behind the server — block until user refreshes.
    if (!mounted) return true;
    await VersionUpdateDialog.show(
      context,
      currentVersion: current.display,
      latestVersion: latest.display,
      latestInfo: latest,
      currentInfo: current,
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
                          'Zydus Healthcare KAM CRM Platform',
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
