import AppKit
import KeyCellarCore
import Testing
@testable import KeyCellar

@MainActor
@Suite struct ClipboardServiceTests {
    private func makeService(clearAfter: Int = 45) -> (ClipboardService, NSPasteboard) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dkb-secret-test-\(UUID().uuidString)"))
        return (ClipboardService(pasteboard: pasteboard, clearAfterSeconds: { clearAfter }), pasteboard)
    }

    @Test func copyWritesTheStringAndTheConcealedMarker() {
        let (service, pasteboard) = makeService()
        service.copy(SecretBytes("s3cret"))
        #expect(pasteboard.string(forType: .string) == "s3cret")
        #expect(pasteboard.types?.contains(ClipboardService.concealedType) == true)
        #expect(service.remainingSeconds == 45)
    }

    @Test func clearsItselfAfterTheTimeout() async throws {
        let (service, pasteboard) = makeService(clearAfter: 1)
        service.copy(SecretBytes("s3cret"))
        try await Task.sleep(for: .milliseconds(1600))
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(service.remainingSeconds == nil)
    }

    @Test func leavesTheUsersOwnCopyAlone() async throws {
        let (service, pasteboard) = makeService(clearAfter: 1)
        service.copy(SecretBytes("s3cret"))
        pasteboard.clearContents()
        pasteboard.setString("mine", forType: .string)
        try await Task.sleep(for: .milliseconds(1600))
        #expect(pasteboard.string(forType: .string) == "mine")
        #expect(service.remainingSeconds == nil)
        service.clearIfStillOurs()
        #expect(pasteboard.string(forType: .string) == "mine")
    }

    @Test func clearIfStillOursWipesImmediately() {
        let (service, pasteboard) = makeService()
        service.copy(SecretBytes("s3cret"))
        service.clearIfStillOurs()
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(service.remainingSeconds == nil)
    }
}
