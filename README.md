# DKB Secret

A personal, native macOS vault for API keys, passwords, SSH keys, `.env` sets
and secure notes. One user, one Mac, no account, no server, no sync.

The full design — threat model, decisions, data model and the phase-by-phase
checklist — is in [`docs/dkb-secret-build-plan.md`](docs/dkb-secret-build-plan.md).

## How secrets are protected (short version)

- The vault's master key is a P-256 key generated **inside the Secure Enclave**
  with a `userPresence` access control. It never leaves the chip; its opaque
  blob is the only thing stored in the login Keychain.
- Every secret value is sealed with CryptoKit **HPKE** to that key and stored
  as ciphertext in SQLite. Reading one back goes through the Secure Enclave,
  which itself demands Touch ID (or the login password) — the app cannot skip
  that check.
- The app is sandboxed with **no network entitlement**, every window is
  capture-proof (`sharingType = .none`), and copied secrets are marked
  concealed and cleared from the clipboard on a timer.
- Because the data is bound to this Mac's Secure Enclave, an encrypted,
  passphrase-protected backup (`.dkbsecret`) is a required feature, not an
  extra.

## Tech stack

- **Swift 6 + SwiftUI**, macOS 14+.
- **`DKBSecretCore`** — headless Swift package (Foundation + GRDB only):
  models, SQLite storage, Secure Enclave / HPKE sealing, vault service, tests.
- **`DKBSecretApp`** — the app target: SwiftUI views, `MenuBarExtra`, the
  AppKit glue for window behaviour, clipboard, hotkey, auto-lock.
- **`xcodegen`** generates the `.xcodeproj` from `project.yml` — the project
  file itself isn't committed.

## Project structure

```
project.yml                     xcodegen spec (targets, entitlements, Info.plist)
Local.xcconfig.example          copy to Local.xcconfig (gitignored): signing identity
DKBSecretApp/
  App/                          App/Scene setup, window management, navigation state
  UI/                           SwiftUI views
  Services/                     clipboard, auto-lock, hotkey (AppKit-side services)
  Resources/                    Assets, Localizable.xcstrings (EN/VI)
DKBSecretAppTests/              app-target tests
DKBSecretCore/
  Sources/DKBSecretCore/
    Models/  Data/  Crypto/  Domain/
  Tests/                        swift-testing suite
docs/                           build plan, release process, security audit
scripts/                        create-signing-cert.sh, release.sh, install-local.sh, generate-app-icon.swift
```

## Getting started

```bash
brew install xcodegen
cp Local.xcconfig.example Local.xcconfig   # or: ./scripts/create-signing-cert.sh
xcodegen generate
open DKBSecretNative.xcodeproj
```

Run the `DKBSecretApp` scheme from Xcode. `DKBSecretCore` can be tested
headlessly:

```bash
cd DKBSecretCore
swift test
```

## Features

- Five kinds: API keys (any token), logins, SSH keys, `.env` sets and secure notes, with
  projects, tags, favourites and environments; instant search over metadata only.
- Reveal and copy through Touch ID, values hidden again after 30 s, clipboard cleared after
  45 s (both configurable); rotation with a five-deep history and expiry reminders 14/7/1/0
  days ahead.
- Auto-lock on idle, sleep, screen lock or hide; menu bar quick search and a global shortcut
  (⌥⌘S by default) that works from any app.
- Encrypted `.dkbsecret` backups (PBKDF2 600k → AES-256-GCM), import by merge or replace,
  scheduled backups to a folder of your choice; `.env` import and export.
- English and Vietnamese.

## Signing and installing

There is no Apple Developer Program behind this app and none is needed: it is built and
installed on this Mac only. `scripts/create-signing-cert.sh` creates a self-signed code-signing
certificate; `scripts/release.sh` builds, verifies and packages a release and
`scripts/install-local.sh` puts it in /Applications. See `docs/release.md`, including why the
first launch of each new build asks for the login keychain password once.

Debug builds keep their own vault in the sandbox container and accept `--seed-sample-data`,
`--reset-debug-vault`, `DKB_START_UNLOCKED=1` and `DKB_ALLOW_CAPTURE=1` for development; none
of these exist in Release. The security audit of the shipped build is in
`docs/security-audit-v1.md`.
