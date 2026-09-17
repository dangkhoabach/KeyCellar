import AppKit
import Carbon.HIToolbox
import CryptoKit
import LocalAuthentication
import Security
import SwiftUI

// Phase 0 PoC. One file on purpose — this target is thrown away after the
// results are copied into docs/dkb-secret-build-plan.md.
//
// Run modes:
//   open "DKB Secret PoC.app"                       → window with buttons
//   ".../Contents/MacOS/DKB Secret PoC" --auto      → runs every check in order,
//                                                     prints to stdout, exits
// Both modes touch Touch ID; the human only has to put a finger on the sensor
// (and press Cancel once when asked).

@main
struct PoCApp: App {
    @NSApplicationDelegateAdaptor(PoCDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("DKB Secret PoC") {
            PoCView()
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}

final class PoCDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // T4: every window of the real app is capture-proof. Set here so the
        // human can verify with ⇧⌘4 that the PoC window renders black.
        for window in NSApp.windows { window.sharingType = .none }
        if CommandLine.arguments.contains("--auto") {
            Task { @MainActor in
                await PoCRunner.shared.runAll()
                exit(PoCRunner.shared.failed ? 1 : 0)
            }
        }
    }
}

struct PoCView: View {
    @State private var runner = PoCRunner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Run all") { Task { await runner.runAll() } }
                Button("Clear") { runner.lines.removeAll() }
                Spacer()
                Text("⇧⌘4 this window → should be black. ⌥⌘S anywhere → hotkey line below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(runner.lines.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}

@MainActor @Observable
final class PoCRunner {
    static let shared = PoCRunner()

    var lines: [String] = []
    var failed = false

    private let service = "com.dangkhoabach.dkb-secret.poc"
    private let account = "vault-master-key"
    private let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    private let info = Data("dkb-secret.poc".utf8)

    func log(_ s: String) {
        lines.append(s)
        print(s)
        fflush(stdout)
    }

    func pass(_ name: String, _ detail: String = "") { log("PASS  \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
    func fail(_ name: String, _ detail: String) { failed = true; log("FAIL  \(name) — \(detail)") }

    func runAll() async {
        log("=== DKB Secret PoC — \(Date()) ===")
        log("sandbox: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil ? "ON" : "OFF (no APP_SANDBOX_CONTAINER_ID)")")
        log("Secure Enclave available: \(SecureEnclave.isAvailable)")

        await checkSecureEnclaveAndKeychain()
        checkDataProtectionKeychain()
        await checkClipboard()
        checkHotKey()
        checkIdle()
        checkScreenLockObserver()
        log("=== done — failed: \(failed) ===")
    }

    // MARK: 0.2 Secure Enclave + HPKE + login Keychain

    private func checkSecureEnclaveAndKeychain() async {
        // Persistence across launches: reuse the blob if a previous run stored one.
        let key: SecureEnclave.P256.KeyAgreement.PrivateKey
        switch keychainRead() {
        case .success(let blob):
            do {
                key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob)
                pass("0.2 persist", "loaded SE key blob (\(blob.count) B) stored by a previous launch")
            } catch {
                fail("0.2 persist", "blob from Keychain could not be loaded: \(error)"); return
            }
        case .failure(let status) where status.code == errSecItemNotFound:
            var cfError: Unmanaged<CFError>?
            guard let ac = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &cfError
            ) else { fail("0.2 SE access control", "\(cfError!.takeRetainedValue())"); return }
            do {
                key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: ac)
                pass("0.2 SE key + userPresence", "created, blob \(key.dataRepresentation.count) B")
            } catch { fail("0.2 SE key + userPresence", "\(error)"); return }
            let status = keychainAdd(key.dataRepresentation)
            guard status == errSecSuccess else { fail("0.2 login Keychain add", "OSStatus \(status)"); return }
            pass("0.2 login Keychain add", "errSecSuccess (first launch — relaunch to verify persistence)")
        case .failure(let status):
            fail("0.2 login Keychain read", "OSStatus \(status.code)"); return
        }

        // Seal needs only the public key → must never prompt.
        let plaintext = Data("poc-secret-\(Int.random(in: 1000...9999))".utf8)
        let sealed: (enc: Data, ct: Data)
        do {
            var sender = try HPKE.Sender(recipientKey: key.publicKey, ciphersuite: suite, info: info)
            sealed = (sender.encapsulatedKey, try sender.seal(plaintext))
            pass("0.2 HPKE seal", "no prompt expected")
        } catch { fail("0.2 HPKE seal", "\(error)"); return }

        // Open → Secure Enclave must demand Touch ID. Off the main actor so the
        // window keeps painting while the system sheet is up.
        log("      → Touch ID prompt expected now (accept it)")
        let blob = key.dataRepresentation
        let suite = self.suite, info = self.info
        let result = await Task.detached { () -> Result<(String, Double, Double), Error> in
            let ctx = LAContext()
            ctx.localizedReason = "DKB Secret PoC decrypt"
            ctx.touchIDAuthenticationAllowableReuseDuration = 60
            do {
                let k = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob, authenticationContext: ctx)
                let t0 = Date()
                var r1 = try HPKE.Recipient(privateKey: k, ciphersuite: suite, info: info, encapsulatedKey: sealed.enc)
                let pt = try r1.open(sealed.ct)
                let first = Date().timeIntervalSince(t0)
                let t1 = Date()
                var r2 = try HPKE.Recipient(privateKey: k, ciphersuite: suite, info: info, encapsulatedKey: sealed.enc)
                _ = try r2.open(sealed.ct)
                let second = Date().timeIntervalSince(t1)
                return .success((String(decoding: pt, as: UTF8.self), first, second))
            } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let (pt, first, second)):
            if pt == String(decoding: plaintext, as: UTF8.self) {
                pass("0.2 HPKE open via SE", String(format: "plaintext matches, %.1fs (includes your touch)", first))
            } else { fail("0.2 HPKE open via SE", "plaintext mismatch") }
            if second < 1.0 { pass("0.2 LAContext reuse", String(format: "second open %.2fs, no prompt", second)) }
            else { fail("0.2 LAContext reuse", String(format: "second open took %.1fs — prompted again", second)) }
        case .failure(let error):
            fail("0.2 HPKE open via SE", "\(error)")
        }

        // Cancel path: fresh context, human presses Cancel.
        log("      → Touch ID prompt again: press CANCEL this time")
        let cancel = await Task.detached { () -> String in
            let ctx = LAContext()
            ctx.localizedReason = "DKB Secret PoC — press Cancel"
            do {
                let k = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob, authenticationContext: ctx)
                var r = try HPKE.Recipient(privateKey: k, ciphersuite: suite, info: info, encapsulatedKey: sealed.enc)
                _ = try r.open(sealed.ct)
                return "opened (you accepted instead of cancelling)"
            } catch { return "error: \(error)" }
        }.value
        if cancel.hasPrefix("error") { pass("0.2 cancel", cancel) } else { log("SKIP  0.2 cancel — \(cancel)") }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    private func keychainAdd(_ data: Data) -> OSStatus {
        var q = baseQuery()
        q[kSecValueData as String] = data
        return SecItemAdd(q as CFDictionary, nil)
    }

    private func keychainRead() -> Result<Data, KeychainStatus> {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return .failure(KeychainStatus(code: status)) }
        return .success(data)
    }

    // Documented evidence for plan §3.1: the data-protection keychain needs a
    // Team-ID entitlement, so an ad-hoc build must get -34018 here.
    private func checkDataProtectionKeychain() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".dp",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data("x".utf8),
        ]
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            pass("0.2 DP keychain (ad-hoc)", "errSecMissingEntitlement -34018 as expected")
        } else {
            SecItemDelete(q as CFDictionary)
            log("NOTE  0.2 DP keychain (ad-hoc) — unexpected OSStatus \(status) (0 would mean DP keychain works without a Team ID)")
        }
    }

    // MARK: 0.3 side APIs

    private func checkClipboard() async {
        let pb = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pb.clearContents()
        pb.setString("poc-clipboard-secret", forType: .string)
        pb.setString("", forType: concealed)
        let count = pb.changeCount
        let hasConcealed = pb.types?.contains(concealed) == true
        hasConcealed ? pass("0.3 clipboard concealed type", "present; check your clipboard manager did NOT record it")
                     : fail("0.3 clipboard concealed type", "type missing")
        try? await Task.sleep(for: .seconds(3))
        if pb.changeCount == count {
            pb.clearContents()
            pass("0.3 clipboard auto-clear", "cleared after 3s, changeCount unchanged")
        } else {
            pass("0.3 clipboard auto-clear", "changeCount moved (you copied something) → left untouched, correct")
        }
    }

    private func checkHotKey() {
        var hotKeyRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x444B4253), id: 1) // "DKBS"
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in PoCRunner.shared.pass("0.3 hotkey fired", "⌥⌘S received") }
            return noErr
        }, 1, &spec, nil, nil)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        status == noErr ? pass("0.3 hotkey register", "⌥⌘S registered in sandbox — press it (also with another app in front)")
                        : fail("0.3 hotkey register", "OSStatus \(status)")
    }

    private func checkIdle() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        idle >= 0 ? pass("0.3 idle seconds", String(format: "%.1fs since last input", idle))
                  : fail("0.3 idle seconds", "negative value \(idle)")
    }

    private func checkScreenLockObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in PoCRunner.shared.pass("0.3 screen lock notification", "received") }
        }
        pass("0.3 screen lock observer", "registered — lock the screen (⌃⌘Q) to see it fire")
    }
}

struct KeychainStatus: Error { let code: OSStatus }
