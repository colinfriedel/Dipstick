//
//  PumpReadingParserTests.swift
//  DipstickTests
//

import Testing
@testable import Dipstick

@MainActor
struct PumpReadingParserTests {
    private typealias Parser = PumpReadingParser

    /// The 10/10/26 RSX fill-up: 9.768 gal, $60.06, $6.149/gal.
    private func isTenTenFill(_ reading: Parser.Reading?) -> Bool {
        guard let reading else { return false }
        return reading.gallons == 9.768 && reading.total == 60.06 && abs(reading.pricePerGallon - 6.149) < 0.0005
    }

    @Test func typicalDisplayWithLabelsOnTheirOwnLines() {
        let reading = Parser.parse(["TOTAL SALE", "$ 60.06", "GALLONS", "9.768", "PRICE PER GALLON", "6.149"])
        #expect(isTenTenFill(reading))
        #expect(reading?.confidence == .checked)
    }

    @Test func labelsOnTheSameLineAsNumbers() {
        let reading = Parser.parse(["$60.06 SALE", "9.768GAL", "6.149 /GAL"])
        #expect(isTenTenFill(reading))
    }

    @Test func misreadSegmentDigitsAreFixed() {
        // A segment "8" read as "B", "0" as "O".
        let reading = Parser.parse(["6O.06", "9.76B", "6.149"])
        #expect(isTenTenFill(reading))
        #expect(reading?.confidence == .checked)
    }

    @Test func dollarSignReadAsSDoesNotCorruptTheTotal() {
        #expect(isTenTenFill(Parser.parse(["S60.06", "9.768", "6.149"])))
    }

    @Test func nineTenthsPrice() {
        let reading = Parser.parse(["60.06", "9.768", "6.14 9/10"])
        #expect(isTenTenFill(reading))
        #expect(reading?.confidence == .checked)
    }

    @Test func distractingNumbersAreIgnored() {
        let reading = Parser.parse([
            "PUMP 4", "REGULAR 87", "CAR WASH 12.00", "PREMIUM 6.649",
            "TOTAL SALE $60.06", "GALLONS 9.768", "PRICE 6.149",
        ])
        #expect(isTenTenFill(reading))
    }

    @Test func priceOnASeparateSignIsInferred() {
        let reading = Parser.parse(["SALE", "60.06", "GALLONS", "9.768"])
        #expect(reading?.gallons == 9.768)
        #expect(reading?.total == 60.06)
        #expect(reading?.pricePerGallon == 6.149)
        #expect(reading?.confidence == .priceInferred)
    }

    @Test func mainScreenWithGallonsAndTotalOnly() {
        // The usual case: the pump's main screen, no price shown.
        for lines in [
            ["TOTAL SALE", "$ 60.06", "GALLONS", "9.768"],
            ["$60.06", "9.768"],
            ["SALE $60.06", "9.768 GAL", "PUMP 4", "REGULAR 87"],
        ] {
            let reading = Parser.parse(lines, expectedPrice: 6.21)
            #expect(isTenTenFill(reading), "\(lines)")
            #expect(reading?.confidence == .priceInferred)
        }
    }

    @Test func implausiblePriceForThisCarIsRejected() {
        // A dropped leading digit: "0.768" gal would mean $78/gal.
        #expect(Parser.parse(["60.06", "0.768"], expectedPrice: 6.21) == nil)
        // A misread total: $16.06 / 9.768 = $1.64/gal, far below this car's $6.21.
        #expect(Parser.parse(["16.06", "9.768"], expectedPrice: 6.21) == nil)
        // Without history, only the broad $1.50–12 range applies.
        #expect(Parser.parse(["16.06", "9.768"]) != nil)
    }

    @Test func voterNeedsSixFramesWithoutAPrice() {
        var voter = PumpReadingVoter()
        let reading = Parser.parse(["60.06", "9.768"])
        for _ in 1..<PumpReadingVoter.priceInferredFramesNeeded {
            #expect(voter.add(reading) == nil)
        }
        #expect(isTenTenFill(voter.add(reading)))
    }

    @Test func checkedReadingBeatsALikelyOne() {
        // A misread "9.168" could imply a plausible price on its own, but the
        // displayed price only agrees with the correct gallons.
        let reading = Parser.parse(["60.06", "9.168", "9.768", "6.149"])
        #expect(isTenTenFill(reading))
        #expect(reading?.confidence == .checked)
    }

    @Test func nothingUsefulReturnsNil() {
        #expect(Parser.parse([]) == nil)
        #expect(Parser.parse(["THANK YOU", "PUMP 4", "87"]) == nil)
    }

    @Test func voterNeedsRepeatedAgreement() {
        var voter = PumpReadingVoter()
        let good = Parser.parse(["60.06", "9.768", "6.149"])
        let misread = Parser.parse(["60.06", "9.768", "6.148"])  // fails the check → likely

        #expect(voter.add(good) == nil)
        #expect(voter.add(misread) == nil)
        #expect(voter.add(good) == nil)
        #expect(isTenTenFill(voter.add(good)))  // third agreeing frame
    }
}
