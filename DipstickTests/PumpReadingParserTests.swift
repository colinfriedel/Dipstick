//
//  PumpReadingParserTests.swift
//  DipstickTests
//

import CoreGraphics
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
        #expect(reading?.confidence == .priceFits)
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
            #expect(reading?.confidence == .priceFits)
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

    @Test func voterNeedsMoreFramesWithoutAPrice() {
        var voter = PumpReadingVoter()
        let reading = Parser.parse(["60.06", "9.768"])
        #expect(reading?.confidence == .priceFits)
        for _ in 1..<PumpReadingVoter.fitsFramesNeeded {
            #expect(voter.add(reading) == nil)
        }
        #expect(isTenTenFill(voter.add(reading)))
    }

    @Test func voterNeverAcceptsAMerelyPlausiblePrice() {
        var voter = PumpReadingVoter()
        let reading = Parser.parse(["73.01", "10.555"])
        #expect(reading?.confidence == .priceInferred)
        for _ in 0..<10 { #expect(voter.add(reading) == nil) }
    }

    @Test func smallFillsAreRead() {
        // 1.311 gal at $5.179 (pump9), and a top-off under a gallon.
        #expect(Parser.parse(["6.79", "1.311"])?.gallons == 1.311)
        #expect(Parser.parse(["3.41", "0.658"])?.gallons == 0.658)
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
        #expect(isTenTenFill(voter.add(good)))  // second agreeing frame
    }

    // MARK: Decimal point not read

    /// The Chevron photo in private/pump-photos: "Sale $ 73.87" read as "7387".
    @Test func totalWithItsPointMissed() {
        let reading = Parser.parse(["Cash Customers Please Pay First", "DCL 030-1", "Sale $", "Gallons", "7387", "10.555"])
        #expect(reading?.gallons == 10.555)
        #expect(reading?.total == 73.87)
        #expect(reading?.pricePerGallon == 6.999)
    }

    @Test func gallonsWithItsPointMissed() {
        let reading = Parser.parse(["60.06", "9768"])
        #expect(reading?.gallons == 9.768)
        #expect(reading?.total == 60.06)
    }

    @Test func bothPointsMissedNeedsARecentPrice() {
        #expect(Parser.parse(["6006", "9768"]) == nil)
        #expect(isTenTenFill(Parser.parse(["6006", "9768"], expectedPrice: 6.10)))
        #expect(Parser.parse(["6006", "9768"], expectedPrice: 4.00) == nil)
    }

    @Test func photoReaderPrefersCheckedThenAgreement() {
        let likely = Parser.parse(["60.06", "9.768"])!
        let other = Parser.parse(["60.06", "9.786"])!
        let checked = Parser.parse(["60.06", "9.768", "6.149"])!
        #expect(PumpPhotoReader.best(of: [other, likely, likely]) == likely)
        #expect(PumpPhotoReader.best(of: [likely, likely, checked]) == checked)
        #expect(PumpPhotoReader.best(of: []) == nil)
    }

    @Test func scanFrameMapsOntoTheAspectFilledPhoto() {
        // A 4:3 portrait photo (3000×4000) filling a 400×800 screen: scaled
        // to 600×800, so 100 pt is cut off each side.
        let crop = PumpPhotoReader.crop(for: CGRect(x: 100, y: 300, width: 200, height: 200),
                                        in: CGSize(width: 400, height: 800),
                                        photoSize: CGSize(width: 3000, height: 4000), margin: 0)
        #expect(abs(crop.minX - 200.0 / 600) < 0.0001)
        #expect(abs(crop.width - 200.0 / 600) < 0.0001)
        #expect(abs(crop.minY - 300.0 / 800) < 0.0001)
        #expect(abs(crop.height - 200.0 / 800) < 0.0001)
        // The margin grows it, but never past the photo's edges.
        let grown = PumpPhotoReader.crop(for: CGRect(x: 0, y: 0, width: 400, height: 800),
                                         in: CGSize(width: 400, height: 800),
                                         photoSize: CGSize(width: 3000, height: 4000))
        #expect(grown.minY == 0 && grown.maxY == 1)
    }

    @Test func nineTenthsPriceSettlesAMisreadLastDigit() {
        #expect(Parser.nineTenthsPrice(gallons: 10.555, total: 73.87) == 6.999)
        #expect(Parser.nineTenthsPrice(gallons: 10.555, total: 73.81) == nil)
        #expect(Parser.nineTenthsPrice(gallons: 9.768, total: 60.06) == 6.149)
        // Both "73.81" and "73.87" read in the same frame: the one an x.xx9
        // price explains wins.
        let reading = Parser.parse(["73.81", "73.87", "10.555"])
        #expect(reading?.total == 73.87)
        #expect(reading?.confidence == .priceFits)
        // And across versions of a photo, even when outvoted.
        let fits = Parser.parse(["73.87", "10.555"])!
        let otherwise = Parser.parse(["73.01", "10.555"])!
        #expect(otherwise.confidence == .priceInferred)
        #expect(PumpPhotoReader.best(of: [otherwise, otherwise, fits]) == fits)
    }

    @Test func misreadSegmentDigitIsCorrected() {
        // Every read of the Chevron photo's "$73.87" saw the last 7 as a 1.
        let reading = Parser.parse(["Sale $", "73.81", "Gallons", "10.555"])
        #expect(reading?.total == 73.87)
        #expect(reading?.pricePerGallon == 6.999)
        #expect(reading?.confidence == .priceFitsCorrected)
        // A leading 7 read as 1 ($13.87 would be $1.31/gal).
        #expect(Parser.parse(["13.87", "10.555"])?.total == 73.87)
        // A total that already fits is left alone.
        #expect(Parser.parse(["73.87", "10.555"])?.confidence == .priceFits)
    }

    @Test func correctionOnlyWhenExactlyOneFixFits() {
        #expect(Parser.correctedTotal(gallons: 10.555, total: 73.81, expectedPrice: nil)?.total == 73.87)
        // Nothing to fix toward: no single-digit change fits.
        #expect(Parser.correctedTotal(gallons: 10.555, total: 73.01, expectedPrice: nil) == nil)
    }

    @Test func readPointBeatsAGuessedOne() {
        // "2026" could be $20.26, but the total that kept its point wins.
        let reading = Parser.parse(["OCT 18 2026", "60.06", "9.768"])
        #expect(isTenTenFill(reading))
    }
}
