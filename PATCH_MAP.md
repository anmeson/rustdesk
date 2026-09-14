# Client Patch Map — `apps/rustdesk`

Every deliberate divergence from upstream `rustdesk/rustdesk` in this tree.

**This file is written as patches are made, never retroactively.** It is the
checklist for re-applying our work after `git fetch upstream && git merge`. A
patch that is not in here will be silently lost at the next upstream bump.

---

## Fork base

| | |
|---|---|
| Upstream | `https://github.com/rustdesk/rustdesk.git` (`master`) |
| Base commit | `65edf214b9801c879a1cd7b3e18a6b3c0ea7244c` |
| `git describe` | `nightly-168-g65edf214b` |
| Declared version | `1.5.0` (`Cargo.toml`) |
| Base date | 2026-09-09 |
| `libs/hbb_common` submodule | `29cf7cbe4d38ce36020749f713fb066299f02431` |
| Working tree at base | clean — no modifications |

Update this block on every upstream merge, and re-verify every entry below.

---

## How to use this file

**Before merging upstream**

1. `git fetch upstream && git log --oneline HEAD..upstream/master -- <paths in this file>`
   to see which of our patch sites moved.
2. Read the **Upstream dependency** column for each entry touching those paths.
   Entries marked ⚠ are the ones to check by hand.

**After merging**

3. Walk this table top to bottom. Confirm each patch still exists, still compiles,
   and still *does what it says* — a patch can survive a merge textually and be
   dead semantically (e.g. its call site moved above the code it was guarding).
4. Re-run the Milestone 5 gate tests. A silently-neutered login gate looks
   exactly like a working one until someone tries to bypass it.
5. Update the fork-base block and any changed line numbers.

**When adding a patch**

6. Add the row *in the same commit as the code*.
7. Prefer **Isolated** over **Structural**. If a change must be structural, say in
   the Notes why an isolated version was not possible.
8. Keep patches behind the `require-login` flag. With the flag off, upstream's
   original path must run unchanged — that is what makes these merges survivable
   (and it is upstream's own rule, `AGENTS.md` → "Be minimally invasive").

### Column meanings

- **Type — Isolated:** additive; a new file, a new function, or a one-line hook.
  Re-applies cleanly in most merges.
- **Type — Structural:** modifies existing control flow or signatures. Expect
  conflicts; expect to re-read the surrounding upstream code each time.
- **Upstream dependency:** internal APIs, structs, or option keys this patch
  leans on that upstream may rename, move, or delete without notice.
  ⚠ marks a real, identified fragility — not just "upstream might change things".

---

## Patches

*No patches applied yet. Phases 1–3 are analysis only; the entries below are*
*pre-registered from Phase 1 findings so the sites are known before the work starts.*

| # | Status | File | What changed | Why | Type | Upstream dependency |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

---

## Planned patches (from Phase 1 — not yet written)

Pre-registered so the merge surface is known before Milestone 4 starts. Each
becomes a real row above, with line numbers, when the code lands. Line references
below are against the fork-base commit.

### P1 — `require-login` option key

- **File:** `libs/base/src/config/keys.rs`
- **What:** add `pub const OPTION_REQUIRE_LOGIN: &str = "require-login";` and
  register it in the appropriate key list (~`:193-320`).
- **Why:** login gate — the single switch every other patch reads.
- **Type:** Isolated. Append-only; the file is a flat list of constants.
- **Upstream dependency:** low. `libs/base` is client-only and upstream's own
  guidance points new option keys here rather than at `hbb_common`. The key lists
  near `:193+` do get reordered — append, never insert.
- **Notes:** deliberately **not** in `hbb_common`, which is a submodule shared
  with the server. Settable through `custom.txt` (`src/custom_server.rs`), so a
  branded build ships gated with no further code change.

### P2 — UI login gate at app start

- **File:** `flutter/lib/main.dart` (`runMainApp`, `:133-144`)
- **What:** when `require-login` is on and `gFFI.userModel.isLogin` is false,
  route to the existing login flow before the main window is shown.
- **Why:** login gate — the user-facing half.
- **Type:** Structural. `runMainApp` is startup sequencing; ordering matters
  (`:140` `startService()`, `:143` `refreshCurrentUser()`, `:144` `runApp`).
- **Upstream dependency:** ⚠ **high.** `runMainApp` is edited often — window
  management, uni-links, theming. Expect a conflict on most merges. Also depends
  on `UserModel.isLogin` (`flutter/lib/models/user_model.dart:26`).
- **Notes:** reuse `flutter/lib/common/widgets/login.dart` (1131 lines, already
  handles password + OIDC). Do not write a second login screen. Keep the patch to
  a guard clause plus one call; resist restructuring the function.

### P3 — connect gate

- **File:** `flutter/lib/common.dart` (`connect()`, `:2572`)
- **What:** refuse and prompt for login when `require-login` is on and the user
  is not logged in.
- **Why:** login gate — prevents outbound connections from the UI.
- **Type:** Isolated. A guard clause at the top of the function, beside the
  existing `if (id == '') return;` (`:2582`).
- **Upstream dependency:** ⚠ medium. `connect()`'s signature grows regularly
  (`connToken`, `isSharedPassword`, `isViewCamera`, `isTerminal` are all recent).
  The *body* start is stable; the parameter list is not.
- **Notes:** this is UX only, **not enforcement** — `hbbs` is the enforcement
  point (Milestone 3). Worth stating in a code comment so a future reader does
  not mistake it for a security boundary. `connect()` is the single funnel for
  every connect flavour, so one guard covers remote/file/terminal/port-forward/RDP.

### P4 — registration gate

- **File:** `src/rendezvous_mediator.rs` (`start_all()`, `:181-259`)
- **What:** when `require-login` is on and no valid session is present, do not
  enter the registration loop; wait for the login signal.
- **Why:** login gate — stops the device announcing itself to `hbbs` while
  unauthenticated.
- **Type:** Structural. Adds a gate to the top of the main loop.
- **Upstream dependency:** ⚠ **high.** `start_all()` is core startup and changes
  often. It already carries several similar early-outs — `config::is_outgoing_only()`
  (`:183`), `stop-service` (`:195`, `:217`) — so there is a clear precedent to
  imitate; imitate it rather than inventing a new shape.
- **Notes:** **this runs in the `--server` service process, as root/SYSTEM.**
  It cannot read the GUI's `LocalConfig` — `hbb_common::config::patch()`
  (`libs/hbb_common/src/config.rs:460-487`) resolves the service to a different
  config directory. The login state must arrive over IPC. See P5.

### P5 — login state across the GUI↔service IPC boundary

- **Files:** `src/ipc.rs` (`Data` enum `:323+`, handler `:1047-1050`),
  `src/ui_interface.rs` (near `deploy_device`, `:1082-1151`)
- **What:** a new IPC message carrying login/logout to the service process, which
  stores it and restarts the mediator.
- **Why:** login gate — P4 cannot work without it.
- **Type:** Isolated *if* modelled exactly on the existing `Data::Deployed`
  (`src/ipc.rs:1047-1050`) + `ipc::notify_deployed()` +
  `RendezvousMediator::restart()` pattern. Structural if we invent a new mechanism.
- **Upstream dependency:** ⚠ medium. The `Data` enum is `#[serde(tag="t", content="c")]`,
  so **adding a variant is wire-compatible in both directions** — a small mercy.
  But variants are added upstream frequently; append at the end, never insert.
- **Notes:** `deploy_device` (`src/ui_interface.rs:1119-1130`) is the exact
  precedent: POST to the API, `ipc::set_config`, `ipc::notify_deployed()`. Follow
  it line for line. **Do not** attempt to share the token file across the
  privilege boundary — that is a confused-deputy bug waiting to happen, and
  `config.rs:748-764` warns about it explicitly.

### P6 — localization keys

- **Files:** `src/lang/template.rs`, `src/lang/en.rs`, `src/lang/*.rs` (~70 files)
- **What:** new keys for the gate's user-facing strings.
- **Why:** login gate — UI strings.
- **Type:** Isolated. Append-only.
- **Upstream dependency:** low, but **high conflict frequency** — every upstream
  release appends here too, and appending at the end of the same list is a
  textbook conflict. Trivial to resolve, tedious at ~70 files.
- **Notes:** upstream's rules (`AGENTS.md` → Localization): sentence case; append
  to `template.rs` and every language file; `it.rs` always gets `""`; a key that
  is already plain English needs no `en.rs` entry.

### P7 — FFI surface for login state *(only if needed)*

- **File:** `src/flutter_ffi.rs`
- **What:** expose the gate's state to Dart, if the existing untyped
  `ffiGetByName` / `ffiSetByName` channel is not sufficient.
- **Why:** login gate — Dart↔Rust plumbing.
- **Type:** Isolated. A new `pub fn` in a 3020-line file of them.
- **Upstream dependency:** low for the function; ⚠ the **build** dependency is the
  catch — `flutter_rust_bridge_codegen` v1.80.1 must regenerate
  `src/bridge_generated.rs` and `flutter/lib/generated_bridge.dart`, both
  gitignored (`.gitignore:22-23,46`). The generated bridge never appears in a diff.
- **Notes:** **prefer no patch at all.** Try `bind.mainGetOption('require-login')`
  through the existing option plumbing first. Every avoided FFI addition is one
  less thing to regenerate and re-verify after a merge.

---

## Explicitly *not* patched

Phase 1 found these already implemented upstream. Recorded here so nobody
re-implements them, and so that if upstream ever removes one we know it was
load-bearing for us.

| Capability | Where upstream already does it |
|---|---|
| Token sent to `hbbs` on every outbound connection | `src/ui_session_interface.rs:1949` → `src/client/io_loop.rs:185-192` → `src/client.rs:891` (`PunchHoleRequest.token`) |
| Connection denial surfaced to the user verbatim | `src/client.rs:940-941` (`PunchHoleResponse.other_failure`) |
| Force-disconnect from the admin console | `src/hbbs_http/sync.rs:252-256` → `src/server/connection.rs:949-955`, `:1283-1288` |
| Session / file-transfer audit logs | `src/server/connection.rs:1421-1470`; `src/common.rs:1197-1203` (`/api/audit/{conn,file}`) |
| Heartbeat, sysinfo upload, remote "strategy" config push | `src/hbbs_http/sync.rs:87-305` |
| Login UI, account model, OIDC | `flutter/lib/common/widgets/login.dart`, `flutter/lib/models/user_model.dart`, `src/hbbs_http/account.rs` |
| Device enrolment by API token | `src/core_main.rs:647-697`, `src/ui_interface.rs:1082-1151` (`--deploy --token`) |
| Graceful handling of "device not enrolled" | `src/rendezvous_mediator.rs:424-429` (`RegisterPkResponse::NOT_DEPLOYED`) |
| Baking server/key/API/settings into a build | `src/custom_server.rs`, `src/common.rs:2224-2244` (`custom.txt`) |

Both settled decisions (docs/PLAN.md D1/D2) were chosen partly *because* they need no
client patch:

| Decision | Why no patch is needed |
|---|---|
| **D2** — revoking a grant kills the live session | Rides the existing heartbeat `disconnect` channel, already handled at `src/server/connection.rs:949-955`. Works for direct and relayed sessions alike. |
| **D1** — break-glass admin capability during an `apps/web` outage | Rides the existing `PunchHoleRequest.token` field. The admin sets `access_token` in their own `RustDesk_local.toml`; `src/ui_session_interface.rs:1949` already forwards it. |

**Because these are unpatched, they are invisible in our diff — and therefore
invisible at merge time.** If an upstream release changes the heartbeat's
`disconnect` field, or stops sending `token` in `PunchHoleRequest`, nothing in
our tree conflicts and nothing fails to compile: a feature just quietly stops
working. Diff these paths on every upstream bump, and cover them in the
Milestone 5 gate tests.

---

## Submodule: `libs/hbb_common`

Shared byte-for-byte with `apps/rustdesk-server`. Changing it means changing a
third repository and bumping the pointer in both forks — upstream's own guidance
(`AGENTS.md`) is to avoid it and put client-only code in `libs/base` instead.

**Current plan: zero patches here.** Two known pressures that could force one,
both deferred:

| Pressure | Where | Milestone |
|---|---|---|
| Hardcoded update-check URL `https://api.rustdesk.com/version/latest` | `libs/hbb_common/src/lib.rs:511` | 6 — only if we take over the update channel |
| Any change to `rendezvous.proto` | `libs/hbb_common/protos/rendezvous.proto` | none planned — `PunchHoleRequest.token` and `PunchHoleResponse.other_failure` already carry everything Milestone 3 needs |

If a proto change ever becomes necessary: it must be applied to **both** forks'
copies (they sit on different commits — see docs/CONTEXT.md §9), stay additive, and
use field numbers upstream is unlikely to reuse.
