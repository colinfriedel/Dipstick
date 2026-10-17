//
//  ThemeTests.swift
//  DipstickTests
//

import SwiftUI
import Testing
import UIKit
@testable import Dipstick

@MainActor
struct ThemeTests {
    @Test func bundledFontsAreRegistered() {
        for name in ["ChakraPetch-Medium", "ChakraPetch-SemiBold", "ShareTechMono-Regular"] {
            #expect(UIFont(name: name, size: 17) != nil, "\(name) didn't load")
        }
    }

    @Test func tokensAdaptToAppearance() {
        let ground = UIColor(Theme.ground)
        let dark = ground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let light = ground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(dark != light)
    }

    @Test func hexStringParsing() {
        #expect(Color(hexString: "#FF6A2B") != nil)
        #expect(Color(hexString: "ff6a2b") != nil)
        #expect(Color(hexString: "nope") == nil)
        #expect(Color(hexString: "#12345") == nil)
    }
}

@MainActor
struct ColorHexTests {
    @Test func hexRoundTrips() {
        for hex in VehicleFormView.swatches {
            #expect(Color(hexString: hex)?.hexString == hex)
        }
    }
}
