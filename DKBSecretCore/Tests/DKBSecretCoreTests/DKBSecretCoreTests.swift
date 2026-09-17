import Testing
@testable import DKBSecretCore

@Test func packageLoads() {
    #expect(!DKBSecretCore.version.isEmpty)
}
