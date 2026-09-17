// TraceMote AGPL notices -- the modification notice, the licence, and the
// offer of corresponding source, as they appear in About.
//
// **This is the one patch that is deliberately not behind `require-login`.**
// Every other client patch is: with the flag off, upstream's path must run
// unchanged (PATCH_MAP.md rule 8). The obligation this file discharges attaches
// to the *binary we distribute*, and that binary is a modified RustDesk whether
// the flag is on or off -- so a notice that the flag could switch off would be
// absent from exactly the builds that still need it. See docs/LICENSING.md.
//
// Nothing here is translated. Upstream leaves its own copyright line
// untranslated in the same card, and adding a key costs 54 files (P6); a legal
// notice that exists in one language is the normal shape for these.

/// Where the corresponding source for *this* binary lives.
///
/// Public, unauthenticated, and verified as such -- if either of these ever
/// stops answering to a logged-out visitor, the offer is broken and the
/// distribution is out of compliance. Re-check at every release (T6.4).
const String kClientSourceUrl = 'https://github.com/tracemote/rustdesk';
const String kServerSourceUrl = 'https://github.com/tracemote/rustdesk-server';

/// The commit the binary was built from, stamped in at build time:
///
/// ```
/// flutter build macos --release \
///   --dart-define=TRACEMOTE_SOURCE_COMMIT=$(git rev-parse HEAD)
/// ```
///
/// A `--dart-define` rather than an FFI constant because the Rust side has no
/// commit to offer either: `gen_version()` writes only `VERSION` and
/// `BUILD_DATE` (`libs/hbb_common/src/lib.rs:228-247`), and `VERSION` is
/// upstream's `1.5.0` -- it does not distinguish our build from theirs, let
/// alone one of ours from the next. Teaching it the commit would mean patching
/// the submodule and adding an FFI call, for a string Dart can be handed for
/// free. See T4.8 on not adding FFI.
///
/// Empty in a local build, and the notice then says so rather than naming a
/// commit it cannot prove. It must **not** be empty in a released binary --
/// that is the release gate in docs/LICENSING.md, because "the source is on
/// GitHub somewhere" is not corresponding source.
const String kSourceCommit =
    String.fromEnvironment('TRACEMOTE_SOURCE_COMMIT', defaultValue: '');

/// The date this build's modifications carry, for AGPL §5(a) ("prominent
/// notices stating that you modified it, and giving a relevant date").
/// Stamped the same way; falls back to the empty string, and the notice then
/// leans on the Build Date already shown two lines above it.
const String kSourceDate =
    String.fromEnvironment('TRACEMOTE_SOURCE_DATE', defaultValue: '');

/// Who modified it. Not a legal entity name -- it is the GitHub organisation
/// that actually hosts the source above, which is the fact a user needs to
/// follow the offer. docs/LICENSING.md carries the open question of what the
/// registered name should be here before the first public binary.
const String kModifierName = 'TraceMote';

/// The §5(a) modification notice.
String get modificationNotice {
  final date = kSourceDate.isNotEmpty ? ' on $kSourceDate' : '';
  return 'Modified build. This is a modified version of RustDesk, '
      'changed by $kModifierName$date. It is not distributed by, '
      'endorsed by, or supported by the RustDesk project.';
}

/// The licence line and the offer of corresponding source.
///
/// Two URLs, not one: the client is what the user is holding, but the `hbbs`
/// they are talking to is a modified AGPL work as well, and §13 reaches a user
/// interacting with it over a network. Naming both here is the cheap half of
/// that question; docs/LICENSING.md carries the rest of it.
String get sourceOfferNotice {
  final at = kSourceCommit.isNotEmpty
      ? 'This binary was built from commit $kSourceCommit.'
      : 'This is an unreleased local build; no source commit was stamped into it.';
  return 'Licensed under the GNU Affero General Public License, version 3 '
      '(AGPL-3.0). The complete corresponding source for this program, and for '
      'the modified server it connects to, is published at:\n'
      '\n'
      '  $kClientSourceUrl\n'
      '  $kServerSourceUrl\n'
      '\n'
      '$at You may copy, modify and redistribute it under the terms of the '
      'AGPL-3.0. A verbatim copy of the licence is included with this program '
      'and with the source, as LICENCE.';
}
