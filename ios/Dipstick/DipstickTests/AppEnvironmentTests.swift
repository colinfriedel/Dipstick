import Foundation
import Testing
@testable import Dipstick

@MainActor
struct AppEnvironmentTests {

    @Test func normalizedURLAddsSchemeWhenMissing() {
        #expect(AppEnvironment.normalizedURL("mymac.local:8081")?.absoluteString == "http://mymac.local:8081")
    }

    @Test func normalizedURLKeepsAnExplicitScheme() {
        #expect(AppEnvironment.normalizedURL("https://api.example.com")?.absoluteString == "https://api.example.com")
    }

    @Test func normalizedURLTrimsWhitespace() {
        #expect(AppEnvironment.normalizedURL("  http://192.168.1.5:8081  ")?.host == "192.168.1.5")
    }

    @Test func normalizedURLRejectsEmptyOrGarbage() {
        #expect(AppEnvironment.normalizedURL(nil) == nil)
        #expect(AppEnvironment.normalizedURL("") == nil)
        #expect(AppEnvironment.normalizedURL("   ") == nil)
    }
}
