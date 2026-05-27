// Non-web implementation of [hardReloadApp]. Mobile/desktop apps don't have
// a browser-style "hard refresh" — the closest analog is closing the app so
// the user re-launches it with the freshly downloaded bundle (or, on iOS
// where SystemNavigator.pop is a no-op, the dialog message still nudges
// them to do so manually).
import 'package:flutter/services.dart';

Future<void> hardReloadApp() async {
  await SystemNavigator.pop();
}
