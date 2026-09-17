import DKBSecretCore
import Foundation
import LocalAuthentication
import Testing
@testable import DKB_Secret

@Suite struct ItemActionsTests {
    @Test func userCancellationIsRecognisedThroughTheUnderlyingChain() {
        let cancel = LAError(.userCancel)
        #expect(ItemActions.isUserCancellation(cancel))
        let wrapped = NSError(domain: "CryptoTokenKit", code: -2, userInfo: [NSUnderlyingErrorKey: cancel as NSError])
        #expect(ItemActions.isUserCancellation(wrapped))
        #expect(!ItemActions.isUserCancellation(LAError(.biometryLockout)))
        #expect(!ItemActions.isUserCancellation(VaultError.itemNotFound("x")))
    }
}
