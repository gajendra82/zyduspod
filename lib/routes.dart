import 'package:flutter/material.dart';
import 'package:zydus_vistaar/login_screen.dart';
import 'package:zydus_vistaar/screens/splash_screen.dart';
import 'package:zydus_vistaar/screens/main_navigation.dart';
import 'package:zydus_vistaar/screens/pod_upload_screen.dart';
import 'package:zydus_vistaar/screens/upload_status_screen.dart';
// Hospital mapping is now handled exclusively from the web "Hospital Mapping
// Review" tool. Keeping the import commented (and the screen file in the
// repo) so the work can be revived without git archaeology if the product
// ever wants in-app review again.
// import 'package:zydus_vistaar/screens/pod_review_screen.dart';
import 'package:zydus_vistaar/screens/stockist_main_navigation.dart';
import 'package:zydus_vistaar/screens/batch_detail_screen.dart';
import 'package:zydus_vistaar/screens/batches_list_screen.dart';
import 'package:zydus_vistaar/screens/notifications_screen.dart';
import 'package:zydus_vistaar/screens/modern_document_upload_screen.dart';
import 'package:zydus_vistaar/screens/documents_list_screen.dart';
import 'package:zydus_vistaar/screens/pod_details_screen.dart';
import 'package:zydus_vistaar/screens/e_invoice_data_screen.dart';
import 'package:zydus_vistaar/screens/profile_screen.dart';
import 'package:zydus_vistaar/widgets/PdfPreviewScreen.dart';
import 'package:zydus_vistaar/screens/pod_upload_screen.dart' as pod_upload;
import 'package:zydus_vistaar/screens/sales_dashboard_screen.dart';
import 'package:zydus_vistaar/widgets/notification_handler.dart';

/// Route names constants
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String mainNavigation = '/main';
  static const String podUpload = '/pod-upload';
  static const String stockistUpload = '/stockist-upload';
  static const String uploadStatus = '/upload-status';
  static const String podReview = '/pod-review';
  static const String batchDetail = '/batch-detail';
  static const String batchesList = '/batches-list';
  static const String notifications = '/notifications';
  static const String documentUpload = '/document-upload';
  static const String documentsList = '/documents-list';
  static const String podDetails = '/pod-details';
  static const String eInvoiceData = '/e-invoice-data';
  static const String profile = '/profile';
  static const String pdfPreview = '/pdf-preview';
  static const String notificationSettings = '/notification-settings';
  static const String salesAnalytics = '/sales-analytics';
}

/// Route generator function
class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
        );

      case AppRoutes.login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );

      case AppRoutes.mainNavigation:
        return MaterialPageRoute(
          builder: (_) => const MainNavigation(),
        );

      case AppRoutes.podUpload:
        final docType = (args is Map<String, dynamic>)
            ? (args['documentType'] as String? ?? 'pod')
            : 'pod';
        return MaterialPageRoute(
          builder: (_) => PODUploadScreen(documentType: docType),
        );

      case AppRoutes.salesAnalytics:
        return MaterialPageRoute(
          builder: (_) => const SalesDashboardScreen(),
        );

      case AppRoutes.stockistUpload:
        // Stockist shell: bottom-nav with Upload + Profile (mirrors KAM
        // MainNavigation so stockists can reach the Profile/logout screen).
        return MaterialPageRoute(
          builder: (_) => const StockistMainNavigation(),
        );

      case AppRoutes.uploadStatus:
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            builder: (_) => UploadStatusScreen(
              uploadData: args['uploadData'] as Map<String, dynamic>,
              totalFiles: args['totalFiles'] as int,
            ),
          );
        }
        return _errorRoute('UploadStatusScreen requires uploadData and totalFiles');

      case AppRoutes.podReview:
        // Disabled — hospital mapping moved to the web portal. If something
        // still tries to push this route we silently bounce it to the upload
        // status screen (or main nav) so the app doesn't hard-fail.
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Mapping moved')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Hospital mapping is now done from the web portal. '
                  'Please use the Hospital Mapping Review screen on the web.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
        // Original navigation kept here for rollback:
        // if (args is Map<String, dynamic> && args['review'] is Map<String, dynamic>) {
        //   return MaterialPageRoute(
        //     builder: (_) => PodReviewScreen(
        //       review: args['review'] as Map<String, dynamic>,
        //     ),
        //   );
        // }
        // return _errorRoute('PodReviewScreen requires review payload');

      case AppRoutes.batchDetail:
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            builder: (_) => BatchDetailScreen(
              batchId: args['batchId'] as int,
              batch: args['batch'] as dynamic, // Optional Batch object
            ),
          );
        }
        return _errorRoute('BatchDetailScreen requires batchId');

      case AppRoutes.batchesList:
        return MaterialPageRoute(
          builder: (_) => const BatchesListScreen(),
        );

      case AppRoutes.notifications:
        return MaterialPageRoute(
          builder: (_) => const NotificationsScreen(),
        );

      case AppRoutes.documentUpload:
        return MaterialPageRoute(
          builder: (_) => const ModernDocumentUploadScreen(),
        );

      case AppRoutes.documentsList:
        return MaterialPageRoute(
          builder: (_) => const DocumentsListScreen(),
        );

      case AppRoutes.podDetails:
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            builder: (_) => PodDetailsScreen(
              podId: args['podId'] as int,
              documentType: args['documentType'] as String? ?? 'POD',
            ),
          );
        }
        return _errorRoute('PodDetailsScreen requires podId');

      case AppRoutes.eInvoiceData:
        if (args is Map<String, dynamic>) {
          return MaterialPageRoute(
            builder: (_) => EInvoiceDataScreen(
              qrData: args['qrData'] as Map<String, dynamic>?,
              fileName: args['fileName'] as String? ?? 'E-Invoice.pdf',
              uploadTime: args['uploadTime'] as DateTime? ?? DateTime.now(),
              podId: args['podId'] as String?,
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => EInvoiceDataScreen(
            qrData: null,
            fileName: 'E-Invoice.pdf',
            uploadTime: DateTime.now(),
            podId: null,
          ),
        );

      case AppRoutes.profile:
        return MaterialPageRoute(
          builder: (_) => const ProfileScreen(),
        );

      case AppRoutes.pdfPreview:
        if (args is Map<String, dynamic>) {
          // Handle both File and bytes preview
          if (args.containsKey('pdfFile')) {
            return MaterialPageRoute(
              builder: (_) => PdfPreviewScreen(
                pdfFile: args['pdfFile'] as dynamic, // File type
              ),
            );
          } else if (args.containsKey('pdfBytes')) {
            return MaterialPageRoute(
              builder: (_) => pod_upload.PdfPreviewBytesScreen(
                pdfBytes: args['pdfBytes'] as dynamic, // Uint8List
                title: args['title'] as String? ?? 'Preview',
              ),
            );
          }
        }
        return _errorRoute('PdfPreview requires pdfFile or pdfBytes');

      case AppRoutes.notificationSettings:
        return MaterialPageRoute(
          builder: (_) => const NotificationSettings(),
        );

      default:
        return _errorRoute('Route not found: ${settings.name}');
    }
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Text(message),
        ),
      ),
    );
  }
}

/// Navigation helper class
class AppNavigator {
  /// Navigate to a route by name
  static Future<T?> pushNamed<T>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    return Navigator.pushNamed<T>(
      context,
      routeName,
      arguments: arguments,
    );
  }

  /// Navigate and replace current route
  static Future<T?> pushReplacementNamed<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    T? result,
  }) {
    return Navigator.pushReplacementNamed<T, T>(
      context,
      routeName,
      arguments: arguments,
      result: result,
    );
  }

  /// Navigate and remove all previous routes
  static Future<T?> pushNamedAndRemoveUntil<T>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    bool Function(Route<dynamic>)? predicate,
  }) {
    return Navigator.pushNamedAndRemoveUntil<T>(
      context,
      routeName,
      predicate ?? (route) => false,
      arguments: arguments,
    );
  }

  /// Pop current route
  static void pop<T>(BuildContext context, [T? result]) {
    Navigator.pop<T>(context, result);
  }
}

