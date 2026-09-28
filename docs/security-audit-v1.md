# DKB Secret — Security audit v1.0.0

Date: 2026-09-17 · Build audited: Release, `CODE_SIGN_IDENTITY = DKB Secret Local Signing`,
Xcode 27.0 beta, macOS 26 (Darwin 27.0.0), Apple M3 Pro.

Checklist from `dkb-secret-build-plan.md` §8 Phase 9.1. "Automated" means a unit test pins
it; "Verified" means checked by hand on this machine on the date above; "Owner" means only
the vault's owner can complete it (needs Touch ID or a system setting).

| # | Check | Result | How |
|---|---|---|---|
| 1 | No `print` / `NSLog` / `os_log` / `Logger` anywhere in App or Core sources | **Pass** | `grep -rnE 'print\(|NSLog\(|os_log|Logger\('` over `DKBSecretApp` and `DKBSecretCore/Sources` → 0 hits |
| 2 | No `String` holding a secret in an `@Observable` model outside a reveal | **Pass** | `ItemDetailViewModel.revealed` is `[RevealKey: SecretBytes]`, dropped on hide / lock. `ItemFormModel.values` holds `String`s only while its sheet is open (TextField requirement); the sheet is closed on lock and the model released. `BackupManager` keeps the session passphrase as `SecretBytes`, cleared on lock. |
| 3 | No plaintext secret in SQLite | **Automated** | `SecretVaultTests.noPlaintextSecretEverLandsInTheDatabase` dumps every text/blob cell after create + rotate + reveal and asserts the canary is absent. `AppDatabase` has no column for plaintext by construction. |
| 4 | Enclave key blob never in SQLite | **Pass** | Only `KeychainStore` (Release) / `DebugKeyBlobStore` (Debug) touch the blob; `AppDatabase` schema has no such column. |
| 5 | Release entitlements | **Pass** | `codesign -d --entitlements :-` → exactly `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`. No `network.client`, no `disable-library-validation`, no `get-task-allow` (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Release). |
| 6 | Signature | **Pass** | `codesign --verify --deep --strict` OK; `flags=0x10000(runtime)` (Hardened Runtime); Authority = DKB Secret Local Signing; 0 embedded dylibs/frameworks (GRDB is linked statically). |
| 7 | No Debug-only switches in the Release binary | **Pass** | `strings` of the Release executable contains none of `DKB_ALLOW_CAPTURE`, `DKB_START_UNLOCKED`, `--seed-sample-data`, `--reset-debug-vault`, `master-key-debug`. |
| 8 | Every window capture-proof | **Verified (main, Release)** / **Pass by code (panel, sheets)** | Release main window: `screencapture -l <id>` → "could not create image from window", `kCGWindowSharingState = 0`. `QuickSearchPanel` sets `sharingType = .none` in Release; sheets are child windows of the main window and inherit it. |
| 9 | Clipboard concealed + timed clear | **Automated + Verified** | `ClipboardServiceTests` (4). Phase 0 PoC confirmed the `org.nspasteboard.ConcealedType` marker is present. **Owner:** confirm your clipboard manager (Raycast/Paste…) does not record a copied secret; note that Universal Clipboard to iPhone cannot be blocked by an app. |
| 10 | Lock clears state | **Automated + Verified** | `VaultSessionTests` (clipboard wiped on lock); `ContentView.onChange(isLocked)` hides revealed values, closes the form and the quick-search panel; `SecureEnclaveSealer.endAuthenticationSession` invalidates the `LAContext`. Verified ⌘L and lock-when-hidden by screenshot. |
| 11 | Lock while a form is open | **Decided** | The sheet is closed and its typed values discarded. Safer than keeping a draft in memory across a lock; the user re-enters. |
| 12 | Touch ID cancel | **Verified** | Cancelling the enclave prompt leaves the value masked and shows no alert (`ItemActions.isUserCancellation` walks the CryptoTokenKit → LAError chain; `ItemActionsTests`). |
| 13 | Crash reports | **Pass by construction** | No secret is ever formatted into a string that reaches a log or an error message; `SecretBytes` has no `description`. |
| 14 | Dependency pin | **Pass** | Only GRDB.swift, pinned in `Package.resolved` to revision `b83108d` (7.11.1), same revision DKB Downloader ships. |
| 15 | Performance | **Automated** | `PerformanceTests.twoThousandItemsSearchUnder50ms`: list, search, filtered search and quick-search ranking over 2 000 items each under 50 ms (whole test incl. inserts: 0.16 s). |
| 16 | Memory after hiding a reveal | **Owner (optional)** | `SecretBytes` zeroes its buffer in `deinit` (`SecretBytesTests.wipeZeroesTheBufferInPlace`); SwiftUI `Text` copies are outside the app's control (plan §2 T8). An Instruments Allocations pass is a nice-to-have, not a gate. |

## Addendum 1.0.1 — recovery codes (docs/dkb-secret-recovery-codes-plan.md)

| # | Check | Result | How |
|---|---|---|---|
| 17 | Codes never in SQLite | **Automated** | `RecoveryCodeUsageTests.codesNeverLandInTheDatabase`: create a set, tick a code, reveal, dump every cell, the canary is absent. The whole set is one HPKE blob. |
| 18 | What metadata reveals | **Decided (RC4)** | `metadata_json` holds the number of codes and which positions are used, with the day each was marked (`codeCount`, `usedCodes`). Never a code. This is what lets ticking and counting work without Touch ID. |
| 19 | Every read of a code goes through the enclave | **Pass by code** | Reveal All, copy one code, copy next unused, edit and export all call `SecretVault.reveal("codes")`. Ticking a checkbox only writes metadata. "No unused codes left" is decided from metadata before any reveal. |
| 20 | Clipboard | **Pass by code** | One code at a time through `ClipboardService` (concealed, timed clear). ⌘C never copies the whole set. |
| 21 | Export | **Pass by code** | `.txt` behind the same plaintext confirmation as `.env`, written 0600. |
| 22 | Entitlements, dependencies | **Unchanged** | Parser is plain Swift in Core; no new entitlement, no new dependency, no schema migration. |

## Known limits (unchanged from the plan's threat model)

- Malware with root, SIP off, or a debugger on the process while unlocked.
- An attacker with the unlocked Mac **and** your fingerprint / login password.
- Memory zeroing is best-effort once a value has been shown or typed.
- The login Keychain item is pinned to the cdhash of the build that created it: the first launch
  of each new Release build asks for the login password once (Always Allow). Debug builds use a
  file in their sandbox container instead and hold a separate vault.

## i18n / accessibility

- 224 catalog keys, 210 translated to Vietnamese, 8 identical in both languages, 6 proper nouns.
  Interpolation specifiers checked to match between EN and VI by script.
- Verified by screenshot: sidebar, Settings, status bar, pickers in Vietnamese.
- Limit: the app menu bar (File/Edit/Item…) stays English — `.commands` sit outside the
  `WindowGroup`'s `\.locale` override, the same limit DKB Monitor has.
- Reveal/copy buttons carry `accessibilityLabel`s; the app uses system controls throughout.
