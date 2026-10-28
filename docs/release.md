# Releasing KeyCellar

Everything runs on this Mac. There is no Apple Developer Program, no notarization and no
update feed — `scripts/release.sh` is the whole process. The DMG it produces is universal
(Apple silicon + Intel) and can be handed to other people; see "Distributing" below.

## One-time setup

1. `./scripts/create-signing-cert.sh` — creates the self-signed "DKB Secret Local Signing"
   certificate in the login Keychain and points `Local.xcconfig` at it. A release refuses to
   build ad-hoc.
2. `brew install create-dmg`.

## Cutting a release

```bash
./scripts/release.sh          # tests → version prompt → Release build → verify → DMG
./scripts/install-local.sh    # copies release-output/<version>/KeyCellar.app to /Applications
```

`release.sh` runs both test suites, asks for the version (written into
`KeyCellarApp/Info.plist`, both `CFBundleShortVersionString` and `CFBundleVersion`), builds Release, then checks the signature, Hardened Runtime
that the entitlements are exactly App Sandbox + user-selected files (nothing else may ship)
and that the binary contains both arm64 and x86_64. Output:
`release-output/<version>/KeyCellar-<version>.dmg` and the `.app`.

The version must be `MAJOR.MINOR.PATCH` and not lower than the current one. If anything fails
after the version was written, `Info.plist` is restored, so a failed run never leaves a
version behind that was never released.

## Build settings worth knowing

Set on the targets in `KeyCellar.xcodeproj` (open the project to change them):

- `CODE_SIGN_STYLE = Manual`, no team: the app is built and installed on this Mac only, with
  no Apple Developer Program. No provisioning profile is involved, so nothing
  can expire. The identity itself comes from `Local.xcconfig`.
- `ENABLE_HARDENED_RUNTIME` is `YES` for Release only. Xcode 16+ Debug builds link the app
  through a generated `<App>.debug.dylib`, and Hardened Runtime's library validation rejects
  that dylib under any non-Apple identity, so a Debug build (and the test host) signed with
  the self-signed certificate would abort at launch.
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Release: Xcode otherwise injects
  `get-task-allow` (debugger attach) into every Manual-signed build, and a vault's Release
  build must not carry it (security audit #5).
- `KeyCellarApp.entitlements` is App Sandbox + user-selected files and deliberately nothing
  else — no `com.apple.security.network.client` (threat model T6). Adding network
  access is a threat-model change, not a one-line edit; `release.sh` fails if any other key
  ships.
- `SWIFT_EMIT_LOC_STRINGS = YES`: the compiler must emit the exact runtime keys (`%lld` vs
  `%@`) for interpolated SwiftUI strings, or hand-written catalog entries never match.

## First launch of a new build

macOS pins the login Keychain item holding the enclave key blob to the cdhash of the build
that created it (`partition_id`). A new build therefore triggers one dialog:

> KeyCellar wants to access key "com.dangkhoabach.dkb-secret" in your keychain.

Enter the login password and choose **Always Allow**. This happens once per installed build,
never per launch. Deny would leave the vault unable to open (the app shows an alert and quits;
relaunch and allow).

Debug builds never see this: they keep a separate vault (`dkb-secret-debug.db` + a file-backed
key blob) in the sandbox container.

## Before trusting it with real secrets

1. Install the Release build, unlock with Touch ID.
2. Settings › Backup › **Export Now…** with a passphrase you have written down **outside this
   Mac**. Without it a backup cannot be opened, and the vault itself cannot be moved off this
   Mac's Secure Enclave any other way.
3. Add a handful of real items, export again, and prove the round trip: run a Debug build with
   `--reset-debug-vault`, Import… the file (Replace), check the items and their history.
4. Choose a backup folder outside the Mac (external disk or iCloud Drive — the file is
   encrypted) and set the schedule to Weekly.
5. Turn on notifications for KeyCellar in System Settings › Notifications so expiry reminders
   can be shown.

## Distributing

Requirements on the user's Mac: macOS 14 or later and a Secure Enclave — any Apple silicon
Mac, or an Intel Mac with the T2 chip (2018 and later). Without one the app explains that and
quits at launch.

The app is signed with a self-signed certificate, so Gatekeeper treats it as from an
unidentified developer. On macOS 15 and later the first launch needs **System Settings ›
Privacy & Security › Open Anyway** (right-click › Open no longer bypasses it); on macOS 14
right-click › Open works. Every new build also triggers the login-Keychain dialog described
above once ("Always Allow"). Both go away only with an Apple Developer Program membership
(Developer ID + notarization; a Team ID also moves the Keychain item off the per-build cdhash
partition).

Backups only move forward: a `.dkbsecret` made by 1.0.1 or later that holds recovery codes
does not import into 1.0.0, which does not know that kind (the reverse works). Update the
other Mac first.

There is no in-app update check (no network entitlement). Announce new versions where the
DMG is published; users replace the app in `/Applications`. Their vault lives in the app's
container and the enclave key in the login Keychain, so replacing the app keeps the data.

## Tag and GitHub release

Once the DMG is on the download page, tag the commit that set the version (never a later
commit) and publish a GitHub release from that tag:

```bash
git tag v<version> <commit>
git push origin v<version>
```

On github.com/dangkhoabach/KeyCellar/releases/new pick that tag, title it
`KeyCellar <version>` and write the English release notes, then an Install paragraph
(**Open Anyway** on first launch and replacing the app in `/Applications` for an installed
copy) and the DMG's SHA-256. Attach the same `KeyCellar-<version>.dmg` that went to the
download page, not a rebuild, and check that the SHA-256 GitHub shows for the asset matches.
Older versions get no GitHub release. The GitHub release is for people who find the app
through the repository.

## Rotating the signing certificate

If "DKB Secret Local Signing" is ever deleted from the Keychain, run
`scripts/create-signing-cert.sh` again. The vault data is not affected — the enclave key does
not depend on the certificate — but the next build asks for the login password once more.
