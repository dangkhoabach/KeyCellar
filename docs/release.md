# Releasing DKB Secret

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
./scripts/install-local.sh    # copies release-output/<version>/DKB Secret.app to /Applications
```

`release.sh` runs both test suites, asks for the version (written into `project.yml`, the
source of truth for `Info.plist`), builds Release, then checks the signature, Hardened Runtime
that the entitlements are exactly App Sandbox + user-selected files (nothing else may ship —
plan §3.2 D10) and that the binary contains both arm64 and x86_64. Output:
`release-output/<version>/DKB-Secret-<version>.dmg` and the `.app`.

The version must be `MAJOR.MINOR.PATCH` and not lower than the current one. If anything fails
after the version was written, `project.yml` is restored, so a failed run never leaves a
version behind that was never released.

## First launch of a new build

macOS pins the login Keychain item holding the enclave key blob to the cdhash of the build
that created it (`partition_id`, see plan D1). A new build therefore triggers one dialog:

> DKB Secret wants to access key "com.dangkhoabach.dkb-secret" in your keychain.

Enter the login password and choose **Always Allow**. This happens once per installed build,
never per launch. Deny would leave the vault unable to open (the app shows an alert and quits;
relaunch and allow).

Debug builds never see this: they keep a separate vault (`dkb-secret-debug.db` + a file-backed
key blob) in the sandbox container.

## Before trusting it with real secrets (plan Phase 10)

1. Install the Release build, unlock with Touch ID.
2. Settings › Backup › **Export Now…** with a passphrase you have written down **outside this
   Mac**. Without it a backup cannot be opened, and the vault itself cannot be moved off this
   Mac's Secure Enclave any other way.
3. Add a handful of real items, export again, and prove the round trip: run a Debug build with
   `--reset-debug-vault`, Import… the file (Replace), check the items and their history.
4. Choose a backup folder outside the Mac (external disk or iCloud Drive — the file is
   encrypted) and set the schedule to Weekly.
5. Turn on notifications for DKB Secret in System Settings › Notifications so expiry reminders
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

There is no in-app update check (no network entitlement). Announce new versions where the
DMG is published; users replace the app in `/Applications`. Their vault lives in the app's
container and the enclave key in the login Keychain, so replacing the app keeps the data.

## Rotating the signing certificate

If "DKB Secret Local Signing" is ever deleted from the Keychain, run
`scripts/create-signing-cert.sh` again. The vault data is not affected — the enclave key does
not depend on the certificate — but the next build asks for the login password once more.
