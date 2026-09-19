#!/usr/bin/env bash
#
# Verify a built client artifact, for the release pipeline (TASK.md T6.4).
#
# release-preflight.sh checks the *inputs*; this checks the *output*. They are
# not the same check. Every input can be correct and still not reach the bundle:
# on macOS three separate files have to be copied in after Xcode has finished,
# `cargo` can reuse an object file compiled against a previous key, and a
# `--dart-define` that never made it to the `flutter build` command line leaves
# no trace anywhere except a string that is missing from the binary.
#
# So this greps the artifact, in the words of docs/LICENSING.md §5 step 5:
# verify the notice is in the thing you are shipping, rather than in the source
# you think you built.
#
#   scripts/release-verify.sh <artifact>
#
#     macOS    path to TraceMote.app
#     Linux    path to the unpacked bundle directory
#     Windows  path to the unpacked Release directory
#
# Same four environment inputs as the preflight, plus one more since T6.10:
#
#   TRACEMOTE_VERIFY_STAGE   `release` (default) or `compile`
#
# The build now happens in two places -- compiled unbranded in the public fork,
# then branded and signed in the private repo -- so this script runs twice on
# the way to one artifact, and the two runs cannot assert the same things.
#
#   compile   the bundle is deliberately mid-assembly: no custom.txt, and on
#             macOS the seal Xcode wrote has just been broken by copying LICENCE
#             in. Checks the four COMPILE-TIME facts, which is all this stage
#             can still do anything about: LICENCE, the service binary, the AGPL
#             stamp and the trust anchor. A failure here means rebuilding.
#   release   the artifact is finished. Everything, including the signature.
#
# Defaulting to `release` keeps every existing caller -- docs/BUILD.md, a human
# checking a local build -- behaving exactly as before.
#
# VERIFIED on macOS arm64 only (2026-09-16). The Linux and Windows branches are
# written from the layout Flutter documents and have never been run -- see the
# note at the bottom of docs/BUILD.md.

set -uo pipefail

STAGE="${TRACEMOTE_VERIFY_STAGE:-release}"
case "$STAGE" in
  compile|release) ;;
  *) echo "TRACEMOTE_VERIFY_STAGE must be 'compile' or 'release', got '$STAGE'" >&2
     exit 2 ;;
esac

# This script lives in the CLIENT FORK and is run from two repositories (T6.10):
# from here, by the public compile pipeline, where the fork is the repo root;
# and from tracemote/tracemote, where the fork is the `apps/rustdesk` submodule
# and a one-line shim at scripts/release-verify.sh execs this file. One copy,
# because the two callers must apply the same checks -- a second copy would
# drift, and the drift would be invisible until a release shipped.
SELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SELF_ROOT/build.py" ]; then
  CLIENT="$SELF_ROOT"                       # run from inside the fork
  REPO_ROOT="$(cd "$SELF_ROOT/../.." 2>/dev/null && pwd || echo "$SELF_ROOT")"
else
  CLIENT="$SELF_ROOT/apps/rustdesk"         # run from the parent repo
  REPO_ROOT="$SELF_ROOT"
fi

ARTIFACT="${1:-}"
if [ -z "$ARTIFACT" ] || [ ! -e "$ARTIFACT" ]; then
  echo "usage: $0 <TraceMote.app | bundle dir>" >&2
  exit 2
fi
ARTIFACT="${ARTIFACT%/}"

FAILED=0
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; FAILED=1; }
ok()   { printf '  \033[32m ok \033[0m  %s\n' "$*"; }
note() { printf '        %s\n' "$*"; }

# Where each platform puts the things we care about. RES is where the client
# looks for custom.txt (BRANDING.md §4) and where LICENCE is conveyed; SNAPSHOT
# is the compiled Dart, which is what has to contain the notice strings.
case "$(uname -s)" in
  Darwin)  PLATFORM=macos;   RES="$ARTIFACT/Contents/Resources"
           SNAPSHOT="$ARTIFACT/Contents/Frameworks/App.framework/App"
           SERVICE="$ARTIFACT/Contents/MacOS/service" ;;
  Linux)   PLATFORM=linux;   RES="$ARTIFACT"
           SNAPSHOT="$ARTIFACT/lib/libapp.so"
           SERVICE="" ;;
  *)       PLATFORM=windows; RES="$ARTIFACT"
           SNAPSHOT="$ARTIFACT/data/app.so"
           SERVICE="" ;;
esac

# EXE is the launcher, and its *filename* is load-bearing on two of the three
# platforms: the Windows installer writes `{app-name}.exe` into the registry and
# every shortcut without ever creating it (PATCH_MAP B11), and the macOS launchd
# plists name `Contents/MacOS/{app-name}` (B9). Linux is still upstream's
# `rustdesk` because B10 is not written; that is expected, not a failure.
#
# `app-name` comes out of the SIGNED config, not out of branding.json.
# branding.json is the file a human edits and it is gitignored -- it carries the
# server key -- so on CI it does not exist, and the Windows job died on exactly
# that: `sed: can't read /d/a/tracemote/tracemote/branding.json`. What CI has,
# and what the artifact itself carries, is custom.txt: 64 bytes of Ed25519
# signature followed by the plaintext JSON, base64 (tools/custom-client.py).
# Reading the name from there is also the stricter check of the two -- it is the
# name the shipped client will use at runtime, rather than one a local,
# unsigned, possibly-drifted file claims. branding.json stays as the last
# fallback so a dev host that has not exported custom.txt still gets the check.
config_in_custom_txt() {
  local f="$1" raw="" d=""
  [ -f "$f" ] || return 1
  # `base64 -d` is GNU and git-bash; `-D` is BSD/macOS; openssl is the backstop.
  for d in "base64 -d" "base64 -D" "openssl base64 -d -A"; do
    raw="$($d <"$f" 2>/dev/null | tail -c +65)" || raw=""
    case "$raw" in '{'*) printf '%s' "$raw"; return 0 ;; esac
  done
  return 1
}

app_name_in() {
  sed -n 's/.*"app-name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

APP_NAME=""
APP_NAME_SRC=""
for CFG_SRC in "$RES/custom.txt" "${TRACEMOTE_CUSTOM_TXT:-}"; do
  [ -n "$CFG_SRC" ] && [ -f "$CFG_SRC" ] || continue
  CFG="$(config_in_custom_txt "$CFG_SRC")" || continue
  APP_NAME="$(printf '%s' "$CFG" | app_name_in)"
  [ -n "$APP_NAME" ] && { APP_NAME_SRC="$CFG_SRC"; break; }
done
if [ -z "$APP_NAME" ] && [ -f "$REPO_ROOT/branding.json" ]; then
  APP_NAME="$(app_name_in <"$REPO_ROOT/branding.json")"
  [ -n "$APP_NAME" ] && APP_NAME_SRC="$REPO_ROOT/branding.json"
fi

EXE=""
case "$PLATFORM" in
  macos)   [ -n "$APP_NAME" ] && EXE="$ARTIFACT/Contents/MacOS/$APP_NAME" ;;
  linux)   EXE="$ARTIFACT/rustdesk" ;;
  windows) [ -n "$APP_NAME" ] && EXE="$ARTIFACT/$APP_NAME.exe" ;;
esac

echo "release verify [$STAGE] -- $PLATFORM -- $ARTIFACT"
echo

# ------------------------------------------------- 1. the three bundled files
# On macOS each of these is copied in after Xcode sealed the bundle, so each one
# breaks the signature and each one has to land before `codesign`. That ordering
# is the single most expensive trap in docs/BUILD.md; this is what proves it was
# honoured rather than remembered.

if [ -f "$RES/LICENCE" ]; then
  if cmp -s "$RES/LICENCE" "$CLIENT/LICENCE"; then
    ok "LICENCE conveyed with the binary, identical to the fork's"
  else
    fail "LICENCE in the bundle differs from $CLIENT/LICENCE"
  fi
else
  fail "no LICENCE in $RES -- AGPL §4 is not satisfied by the repo alone"
fi

if [ -n "${TRACEMOTE_CUSTOM_TXT:-}" ]; then
  if [ ! -f "$RES/custom.txt" ]; then
    fail "no custom.txt in $RES -- the build is unbranded and the gate is off"
    note "it points at rustdesk.com with require-login unset"
  elif cmp -s "$RES/custom.txt" "$TRACEMOTE_CUSTOM_TXT"; then
    ok "custom.txt in the bundle is the one preflight verified"
  else
    fail "custom.txt in the bundle is NOT the file preflight checked"
    note "a different config may be signed by a different key; re-run preflight"
  fi
else
  note "skipped: custom.txt (TRACEMOTE_CUSTOM_TXT unset)"
fi

if [ -n "$SERVICE" ]; then
  if [ -x "$SERVICE" ]; then
    ok "service binary present in the bundle"
  else
    fail "no service binary at $SERVICE -- build.py copies it in after Xcode"
  fi
fi

if [ -z "$APP_NAME" ] && [ "$PLATFORM" != linux ]; then
  note "skipped: launcher name -- no app-name to compare it against"
  note "tried $RES/custom.txt, \$TRACEMOTE_CUSTOM_TXT, $REPO_ROOT/branding.json"
  note "(branding.json is gitignored, so on CI only the custom.txt paths exist)"
elif [ -e "$EXE" ]; then
  ok "launcher is named $(basename "$EXE"), as the installer expects"
elif [ "$PLATFORM" = linux ]; then
  note "skipped: launcher name (Linux is still upstream's; PATCH_MAP B10)"
else
  fail "no launcher at $EXE"
  note "the name it should have came from $APP_NAME_SRC"
  note "what is there instead: $(ls "$(dirname "$EXE")" | tr '\n' ' ')"
  note "the installer writes this exact path into the registry and every"
  note "shortcut but never creates it -- see PATCH_MAP.md, notes on B11"
fi

# ------------------------------------------------------ 2. the stamp, in situ
# LICENSING.md §5 step 5. A `--dart-define` that was dropped from the command
# line leaves no error behind; the only evidence is the string's absence here.

# Search a binary for a LITERAL string, via `strings` rather than by grepping
# the raw file.
#
# This is not defensive programming, it is a measured fix. On the CI arm64
# runner `grep -c --binary-files=text` reported 0 for a string that was
# provably present -- this script's own failure output printed the sentence
# containing it, extracted from the same file by `strings`. The same raw grep
# finds the same strings on the dev host, and the dev host's `grep` turned out
# to be ugrep rather than BSD grep, so the check had never once run against the
# implementation CI uses. `strings` normalises the input to short lines, which
# removes whatever the raw-file path was tripping over (a 13 MB file containing
# zero newline bytes is the leading suspect).
#
# -F because every needle here is data, not a pattern: a base64 key is full of
# characters a regex engine would rather interpret than match.
contains() {
  local f="$1" needle="$2"
  [ -f "$f" ] || return 1
  [ -n "$needle" ] || return 1
  if command -v strings >/dev/null 2>&1; then
    strings -a "$f" 2>/dev/null | LC_ALL=C grep -qF -- "$needle" && return 0
  fi
  LC_ALL=C grep -qaF -- "$needle" "$f" 2>/dev/null
}

# Anything the caller hands us as a needle gets trimmed. A stray newline in a
# CI variable is invisible in every log line that echoes it and turns an exact
# search into a guaranteed miss.
trim() { printf '%s' "${1:-}" | tr -d '[:space:]'; }

TRACEMOTE_SOURCE_COMMIT="$(trim "${TRACEMOTE_SOURCE_COMMIT:-}")"
TRACEMOTE_SOURCE_DATE="$(trim "${TRACEMOTE_SOURCE_DATE:-}")"
TRACEMOTE_CUSTOM_PK="$(trim "${TRACEMOTE_CUSTOM_PK:-}")"

# The AGPL modification notice as it exists in the built artifact, for when a
# check fails and the useful question is "then what IS in there?".
notice_in() {
  local f="$1" out=""
  if command -v strings >/dev/null 2>&1; then
    out="$(strings -a "$f" 2>/dev/null | grep -m1 'Modified build' || true)"
  fi
  [ -n "$out" ] || out="$(grep -a -o -m1 'Modified build.\{0,170\}' "$f" 2>/dev/null || true)"
  printf '%s' "${out:-<no \"Modified build\" string found at all>}"
}

if [ ! -f "$SNAPSHOT" ]; then
  fail "no compiled Dart at $SNAPSHOT -- cannot check the notice"
  note "if the layout moved, fix the case block at the top of this script"
else
  if contains "$SNAPSHOT" 'github.com/tracemote/rustdesk'; then
    ok "the offer of corresponding source is in the compiled Dart"
  else
    fail "the source URL is NOT in $SNAPSHOT -- patch L1 did not reach the build"
  fi

  if [ -n "${TRACEMOTE_SOURCE_COMMIT:-}" ]; then
    if contains "$SNAPSHOT" "$TRACEMOTE_SOURCE_COMMIT"; then
      ok "About names this binary's commit ($TRACEMOTE_SOURCE_COMMIT)"
    else
      fail "the commit is NOT in the binary -- built without --dart-define"
      note "About will say \"unreleased local build\": compiles fine, ships a"
      note "modified AGPL binary with no corresponding source. LICENSING.md §5.3"
    fi
  else
    note "skipped: commit stamp (TRACEMOTE_SOURCE_COMMIT unset)"
  fi

  if [ -n "${TRACEMOTE_SOURCE_DATE:-}" ]; then
    if contains "$SNAPSHOT" "$TRACEMOTE_SOURCE_DATE"; then
      ok "the §5(a) modification date is in the binary"
    else
      fail "the modification date is NOT in the binary"
      # Show what the notice actually says. Dart folds the whole sentence into
      # one constant, so this distinguishes "the define never arrived" (no date
      # at all) from "a different date was baked" -- which are different bugs,
      # and guessing between them has cost several CI rounds.
      note "expected: $TRACEMOTE_SOURCE_DATE"
      note "the notice actually in the binary reads:"
      note "  $(notice_in "$SNAPSHOT")"
    fi
  fi
fi

# ------------------------------------------------ 3. the trust anchor, in situ
# Patch C1 is an `option_env!`, so a stale object file is a real possibility --
# `build.rs` carries rerun-if-env-changed for exactly that reason. This is the
# check that the *rebuild* happened, not just the export.

if [ -n "${TRACEMOTE_CUSTOM_PK:-}" ]; then
  DYLIB="$(find "$ARTIFACT" \( -name 'liblibrustdesk.dylib' -o -name 'librustdesk.dylib' \
            -o -name 'librustdesk.so' -o -name 'librustdesk.dll' \) -print -quit 2>/dev/null)"
  HAYSTACK="${DYLIB:-$ARTIFACT}"
  if contains "$HAYSTACK" "$TRACEMOTE_CUSTOM_PK"; then
    ok "our trust anchor is compiled into $(basename "$HAYSTACK")"
  else
    fail "TRACEMOTE_CUSTOM_PK is not in the shipped binary"
    note "cargo reused an object file built against the previous key, so the"
    note "client trusts upstream's and will discard custom.txt. BRANDING.md §2"
    # Which file was searched, and is the key anywhere else in the bundle? That
    # separates "cargo did not compile it in" from "this script searched the
    # wrong file", which look identical from the line above.
    note "searched: $HAYSTACK ($(wc -c <"$HAYSTACK" 2>/dev/null | tr -d ' ') bytes)"
    if find "$ARTIFACT" -type f -exec sh -c 'strings -a "$1" 2>/dev/null | LC_ALL=C grep -qF -- "$2"' _ {} "$TRACEMOTE_CUSTOM_PK" \; -print -quit | grep -q .; then
      note "BUT the key IS somewhere else in the bundle -- this script searched"
      note "the wrong file and the build is fine. Fix the script, not the build."
    else
      note "the key is in no file in the bundle, so cargo really did not bake it"
    fi
  fi
  # Do NOT also assert upstream's key is absent. It is present 85 times in a
  # perfectly good branded build -- they are localisation examples
  # (`9123456234@...?key=...`) across 54 src/lang/*.rs files, measured in T6.2
  # and re-measured here. Presence of ours is the whole signal: the C1 const is
  # the only place our key can come from, so if it is in the binary,
  # `option_env!` resolved to it.
else
  note "skipped: trust anchor (TRACEMOTE_CUSTOM_PK unset)"
fi

# ----------------------------------------------------------- 4. the signature
# Adding any of the files above re-breaks the seal. Signing is T6.5's job; all
# this asks is that whatever signature the artifact carries is currently valid.
#
# Skipped at the compile stage, and not as a convenience: at that point LICENCE
# has just been copied into a bundle Xcode ad-hoc signed, so the seal is broken
# BY DESIGN and this check would fail every public build. The private pipeline
# adds custom.txt, signs for real, and runs the same script again as `release`
# -- which is the run where an invalid signature is genuine news.

if [ "$PLATFORM" = macos ] && [ "$STAGE" = compile ]; then
  note "skipped: signature (compile stage -- the seal is broken until signing)"
elif [ "$PLATFORM" = macos ]; then
  if codesign --verify --deep --strict "$ARTIFACT" 2>/dev/null; then
    ok "code signature valid on disk ($(codesign -dv "$ARTIFACT" 2>&1 \
        | awk -F= '/^Authority|^Signature/ {print $2; exit}' || echo 'ad-hoc'))"
  else
    fail "code signature is invalid -- a file was added after signing"
    note "$(codesign --verify --deep --strict "$ARTIFACT" 2>&1 | head -2)"
    note "copy LICENCE, custom.txt and service FIRST, then codesign. BUILD.md"
  fi
fi

echo
if [ "$FAILED" = 0 ] && [ "$STAGE" = compile ]; then
  echo "compile-time facts verified -- ready for branding and signing"
elif [ "$FAILED" = 0 ]; then
  echo "artifact verified -- this one is releasable"
else
  echo "artifact FAILED verification [$STAGE] -- do not ship it" >&2
fi
exit "$FAILED"
