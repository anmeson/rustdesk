// AnmesonDesk login gate -- the state the `require-login` switch acts on.
//
// Registration runs in the service process (root/SYSTEM), which resolves to a
// different config directory than the GUI (`hbb_common::config::patch`) and so
// cannot read the GUI's `LocalConfig`, where the account token lives. The token
// deliberately does not cross that boundary; `config.rs` warns about exactly
// that confused deputy. What crosses is one bit -- "a user is signed in" -- over
// `ipc::Data::LoginState`, modelled on `Data::Deployed`.
//
// The bit is persisted, which is the one place this departs from `Data::Deployed`.
// `NEEDS_DEPLOY` can live in memory because the server re-derives it on every
// registration (`RegisterPkResponse::NOT_DEPLOYED`); nothing re-derives login
// state for the service. In memory only, every reboot would leave an unattended
// machine unregistered until somebody opened the GUI and signed in again.
//
// It is persisted into the service's own `LocalConfig`, not `Config`, because
// `Config` options are mirrored to the GUI and written back wholesale by
// `ipc::set_options` -- a GUI settings save could clobber the bit. Nothing but
// the service touches the service's `LocalConfig`.

use hbb_common::{config::LocalConfig, log};

// Deliberately not in `base::config::keys`: this key is written and read only by
// the service process, is not settable through custom.txt, and is not a
// user-facing option. The keys crate is the import path for *options*; this is
// internal state that happens to use the same file.
const OPTION_LOGIN_STATE: &str = "anmeson-login-state";

/// Whether a user was signed in on this device, as last reported by the GUI.
///
/// Reads the config's in-memory map under a read lock, so it is cheap enough for
/// the registration loop to call on every pass; no cached mirror is kept, which
/// would only be one more thing to get out of step with the file.
#[inline]
pub fn is_logged_in() -> bool {
    LocalConfig::get_option(OPTION_LOGIN_STATE) == "Y"
}

/// Record a login or logout and restart the mediator so the new state takes
/// effect. Service process only -- in the GUI this would write the GUI's own
/// config file, where nothing reads it.
pub fn set_logged_in(logged_in: bool) {
    let value = if logged_in { "Y" } else { "" };
    if LocalConfig::get_option(OPTION_LOGIN_STATE) == value {
        return;
    }
    LocalConfig::set_option(OPTION_LOGIN_STATE.to_owned(), value.to_owned());
    log::info!("login gate: logged_in={logged_in}, restarting mediator");
    crate::rendezvous_mediator::RendezvousMediator::restart();
}

/// True when the gate is on and this device has no signed-in user, i.e. the
/// registration loop must not run.
///
/// Note the asymmetry with `hbbs`: this is the client declining to announce
/// itself, not an enforcement point. A patched client can simply not call it.
/// Enforcement is `hbbs` (Milestone 3).
#[inline]
pub fn is_blocked() -> bool {
    base::config::keys::require_login() && !is_logged_in()
}

// ---------------------------------------------------------------------------
// GUI side
// ---------------------------------------------------------------------------

/// The account token has just been written or cleared in this process. Hand the
/// service the one bit that follows from it.
///
/// Call this from the **GUI** process, from every path that changes
/// `access_token` -- that string is the login state, and the service has no way
/// to observe it. There is no single place to hook: password login and logout
/// go through `ui_interface::set_local_option`, while OIDC writes the token in
/// Rust directly (`hbbs_http::account`). Hooking `LocalConfig::set_option`
/// itself would catch both, but it lives in the `hbb_common` submodule shared
/// with the server, so it is off limits.
///
/// A no-op with the gate off, so an ungated build keeps upstream's behaviour
/// exactly -- no IPC, and no mediator restart on sign-in.
pub fn notify_token_changed(token: &str) {
    // In the GUI the authoritative read is the IPC-synced options map, not
    // `Config` on disk: this process's own config file is not the one the
    // service owns. `require_login()` is the service-side read.
    if crate::ui_interface::get_option(base::config::keys::OPTION_REQUIRE_LOGIN) != "Y" {
        return;
    }
    let logged_in = !token.is_empty();
    #[cfg(target_os = "android")]
    {
        // No separate service process; the mediator runs here.
        set_logged_in(logged_in);
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if let Err(err) = crate::ipc::notify_login_state(logged_in) {
        log::warn!("login gate: failed to notify the service: {err}");
    }
}
