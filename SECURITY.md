# Security policy

## Reporting a vulnerability

Please report security issues privately, not in a public issue:

- **GitHub:** Security tab → **Report a vulnerability** on this repository, or
- **Contact form** on [dangkhoabach.vn](https://dangkhoabach.vn), asking for a private channel.

Include the app version (Settings), your macOS version, your Mac model (Apple silicon or Intel
with T2) and the steps to reproduce. You will get a reply within a week. Please give a fix the
chance to ship before you disclose the issue publicly.

## Supported versions

Only the latest release gets security fixes. The app has no network access and does not update
itself: download the new version from
[apps.dangkhoabach.vn/dkb-secret](https://apps.dangkhoabach.vn/dkb-secret).

## Scope

In scope, measured against [docs/threat-model.md](docs/threat-model.md):

- A way to read a secret value without Touch ID or the login password, from the database, the
  Keychain item, memory, a log or a crash report.
- Any network access, or any entitlement beyond App Sandbox and user-selected files in a
  Release build.
- A window, panel or sheet that shows a secret in a screenshot or screen share.
- Weaknesses in the `.dkbsecret` backup format (PBKDF2 and AES-GCM) or in how recovery codes
  are stored.
- A Debug-only switch reachable in a Release build.

Out of scope, as the threat model states:

- Malware running as root, SIP turned off, or a debugger attached while the vault is unlocked.
- Someone who has both the unlocked Mac and your fingerprint or login password.
- Copies of a revealed value that SwiftUI or the system make outside the app's control.
