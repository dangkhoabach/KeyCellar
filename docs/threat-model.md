# KeyCellar — Threat model

What the vault defends against, and how. Code comments refer to these entries as
"threat model T1" to "T9". The [security audit](security-audit-v1.md) records how each
protection was checked in the shipped build.

| # | Threat | Protection |
|---|---|---|
| T1 | The disk, a Time Machine backup or the database file is taken and read offline on another machine | Every secret value in SQLite is **HPKE ciphertext** sealed to a Secure Enclave key of **this Mac**. The key never leaves the Secure Enclave, so the data is meaningless anywhere else. |
| T2 | Another process of the same user reads the SQLite file and the key blob | The Secure Enclave key blob sits in the **login Keychain** with an ACL for this app only; any other process makes macOS ask for the login password. Even with the blob, the Secure Enclave still demands Touch ID, naming the process that asks, so the user sees it. |
| T3 | Someone sits down at the Mac while it is unlocked | The vault auto-locks (idle, sleep, screen lock). Every **reveal, copy and export** goes through HPKE decryption, so the **Secure Enclave demands Touch ID or the login password**. The hardware enforces it; the app cannot forget the check. |
| T4 | Screenshots, screen recording, screen sharing | `NSWindow.sharingType = .none` on every window and panel. Values are hidden by default, and a revealed value hides itself again after 30 seconds (configurable). |
| T5 | A clipboard manager records a copied secret | The pasteboard entry carries `org.nspasteboard.ConcealedType`, and it is cleared after 45 seconds (configurable) unless something else has been copied since. |
| T6 | A secret leaves the Mac by accident | The sandboxed app has **no network entitlement**, so it cannot send anything even with a bug. The Secure Enclave key cannot be exported. |
| T7 | The Mac is lost, broken, replaced or its Secure Enclave is reset | Because of T1 the data is bound to this Mac's chip, so an **encrypted, passphrase-protected backup** (`.dkbsecret`) is the only way back. Make one before storing real secrets. |
| T8 | A secret ends up in a log, a crash report, a temporary file or `UserDefaults` | No value is ever logged. `SecretBytes` zeroes its memory when released. Plaintext exists only while a value is revealed or copied. |
| T9 | Ciphertext blobs are swapped between fields or items (an attacker who can write the database) | The HPKE `info` is bound to the blob's id, so a blob moved to another place fails to open. |

## Not defended against

- Malware running as root, SIP turned off, or a debugger attached while the vault is
  unlocked.
- A system-wide keylogger.
- Someone who has **both** the unlocked Mac **and** your fingerprint or login password.
- Memory zeroing is best effort: Swift `String` and SwiftUI copy data through several
  buffers outside the app's control.
