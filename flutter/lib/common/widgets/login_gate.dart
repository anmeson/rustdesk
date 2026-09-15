// AnmesonDesk login gate -- the user-facing half.
//
// This is **not** an enforcement point and cannot be one: it runs inside the
// process it is protecting, so a patched client simply does not call it. It
// stops an unauthenticated *operator*, which is all a UI can do. The security
// boundary is `hbbs` (Milestone 3); the client-side half that matters is T4.3,
// which keeps an unauthenticated device from announcing itself at all.

import 'package:flutter/foundation.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'login.dart';

const String kOptionRequireLogin = 'require-login';

/// Whether this build requires an account before it may be used.
///
/// Compared against 'Y' rather than passed through [option2bool], whose
/// fallback arm is `value != "N"` -- an unset key would read as **true** and
/// gate every build that has never heard of it. Same trap as the Rust
/// `option2bool`, same reason; see `libs/base/src/config/keys.rs`.
///
/// `mainGetOptionSync` reads the options map the service syncs over IPC, so
/// this and the service's own `require_login()` see one value.
bool get requireLogin =>
    bind.mainGetOptionSync(key: kOptionRequireLogin) == 'Y';

/// Hold the app at the login dialog until somebody signs in.
///
/// A no-op when the gate is off, so an ungated build reaches its main window by
/// exactly the path upstream built.
///
/// Cancelling re-opens the dialog: there is nothing behind it the user is
/// allowed to touch. The escape hatch for a misconfigured API server is to
/// clear `require-login` from `RustDesk2.toml`, since Settings is unreachable
/// from here.
Future<void> runLoginGate() async {
  if (!requireLogin) return;
  if (gFFI.userModel.isLogin) return;
  // Says why the app opened on a login dialog, which is otherwise
  // indistinguishable from one the user asked for.
  debugPrint('login gate: require-login is on and nobody is signed in');
  while (!gFFI.userModel.isLogin) {
    await loginDialog();
    // Not a busy loop on repeated cancels, and it lets the dialog finish
    // dismissing before the next one is built.
    await Future.delayed(const Duration(milliseconds: 300));
  }
  debugPrint('login gate: signed in as ${gFFI.userModel.userName.value}');
}
