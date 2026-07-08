// Web implementation — emulates a "Ctrl+Shift+R" hard refresh from JS:
// unregister any service workers, flush the CacheStorage, then navigate with
// a cache-busting query param so the browser refetches HTML + JS from the server.
//
// The non-web stub at app_hard_reload_stub.dart is swapped in by the
// conditional import in callers (`if (dart.library.io) ...stub.dart`).
import 'dart:async';
import 'dart:html' as html;

Future<void> hardReloadApp() async {
  // Unregister service workers so a stale SW cannot keep serving the old bundle.
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      await Future.wait(regs.map((r) => r.unregister().catchError((_) => false)));
    }
  } catch (_) {}

  // Clear CacheStorage entries (Flutter web PWA caching).
  try {
    final dynamic caches = (html.window as dynamic).caches;
    if (caches != null) {
      final keys = await caches.keys() as List<dynamic>;
      await Future.wait(
        keys.map((k) => caches.delete(k).catchError((_) => false)),
      );
    }
  } catch (_) {}

  // Brief pause so unregister/delete completes before the next navigation.
  await Future<void>.delayed(const Duration(milliseconds: 150));

  final loc = html.window.location;
  final current = Uri.parse(loc.href);

  // Fresh cache-buster on every hard reload attempt.
  final newParams = Map<String, String>.from(current.queryParameters)
    ..remove('_v')
    ..['_v'] = DateTime.now().millisecondsSinceEpoch.toString();

  final next = current.replace(queryParameters: newParams, fragment: '');

  // Full navigation (not replace) so the browser treats this as a new load.
  loc.href = next.toString();
}
