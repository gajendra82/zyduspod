// Web implementation — emulates a "Ctrl+Shift+R" hard refresh from JS:
// unregister any service workers, flush the CacheStorage, then replace the
// document URL with a cache-busting query param so the browser refetches
// the HTML + asset bundle from the server instead of disk cache.
//
// The non-web stub at app_hard_reload_stub.dart is swapped in by the
// conditional import in callers (`if (dart.library.io) ...stub.dart`).
import 'dart:async';
import 'dart:html' as html;

Future<void> hardReloadApp() async {
  // Unregister service workers so a stale SW can't keep serving the old
  // bundle on the next visit.
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        try {
          await r.unregister();
        } catch (_) {}
      }
    }
  } catch (_) {}

  // Clear CacheStorage entries (used by Flutter web's PWA caching).
  try {
    final dynamic caches = (html.window as dynamic).caches;
    if (caches != null) {
      final keys = await caches.keys();
      for (final k in keys) {
        try {
          await caches.delete(k);
        } catch (_) {}
      }
    }
  } catch (_) {}

  // Rebuild the URL with a fresh _v query param so the document and all
  // its cached subresources miss the HTTP cache on the next load.
  final loc = html.window.location;
  final current = Uri.parse(loc.href);
  final newParams = Map<String, String>.from(current.queryParameters);
  newParams['_v'] = DateTime.now().millisecondsSinceEpoch.toString();
  final next = current.replace(queryParameters: newParams);
  // `replace` (vs `href = ...`) avoids polluting the browser history with a
  // stale entry that points at the cached doc.
  loc.replace(next.toString());
}
