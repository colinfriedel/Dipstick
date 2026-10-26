//
//  ReceiptTests.swift
//  DipstickTests
//
//  Lines as text recognition reads the two sample receipts in
//  private/receipts (names, address and card details left out).
//

import CoreGraphics
import Foundation
import Testing
@testable import Dipstick

@MainActor
struct ReceiptTests {
    /// The Ace Hardware register receipt (photo).
    static let ace = [
        "THANK YOU FOR SHOPPING",
        "SAN RAMON ACE HARDWARE 19431",
        "10/20/26 11:27AM  682  SALE",
        "1004892  EA  $12.99 EA",
        "11 OZ BLASTER PENETRATING  SPR  $12.99",
        "502  3 EA  ,99  EA",
        "MISC HILLMAN FASTENERS  $2.97",
        "SUB-TOTAL:$  15,96  TAX:  1.56",
        "TOTAL:  $  17.52",
        "17.52",
        "BC AMT:",
        "BK CARD#:  XXXXXXXXXXXX0000",
        "AUTH:  000000  AMT: $  17.52",
        "Bank card  USD$  17.52",
        "Tell us about your experience",
        "today and Enter to win a $500",
    ]

    /// An Amazon order page (screenshot).
    static let amazon = [
        "Your Account › Your Orders › Order Details",
        "Order Details",
        "Order placed October 14, 2026  Order # 113-0000000-0000000  View invoice",
        "Ship to  Payment method  Order Summary",
        "Item(s) Subtotal:  $20.45",
        "Shipping & Handling:  $0.00",
        "Total before tax:  $20.45",
        "Estimated tax to be  $1.99",
        "collected:",
        "Grand Total:  $22.44",
        "Delivered October 15",
        "Your package was left near the front door or porch.",
        "Genuine Honda And Acura Brake Fluid Dot 3 (Pack Of 2)",
        "Return or replace items: Eligible through November 14, 2026",
        "$20.45",
    ]

    /// The same Amazon order on the phone's narrower page.
    static let amazonMobile = [
        "Delivery facilitated by Amazon",
        "See all tracking updates",
        "Hide details",
        "Genuine Honda And Acura Brak...",
        "Sold by: Crown Auto Group",
        "Return or replace items: Eligible",
        "through November 14, 2026",
        "$20.45",
        "View your item",
        "Get product support  Buy it again",
        "Track package  Return or replace items",
        "Leave seller feedback",
        "Write a product review",
        "Order summary",
        "Order placed October 14, 2026",
        "Order # 113-0000000-0000000",
        "Item(s) Subtotal:  $20.45",
        "Shipping & Handling:  $0.00",
        "Total before tax:  $20.45",
        "Estimated tax to be collected:  $1.99",
        "Grand Total:  $22.44",
    ]

    @Test func readsTheMobileOrderPage() {
        let r = ReceiptParser.parse(Self.amazonMobile)
        #expect(r.items.map(\.name) == ["Genuine Honda And Acura Brak"])
        #expect(r.items.first?.lineTotal == 20.45)
        #expect(r.checks)
    }

    @Test func packsBecomeQuantities() {
        #expect(ReceiptParser.parse(Self.amazon).items.first?.quantity == 2)
        #expect(ReceiptParser.packCount("Brake Pads 4-Pack") == 4)
        #expect(ReceiptParser.packCount("Spark plug set of 4") == 4)
        #expect(ReceiptParser.packCount("11 OZ BLASTER PENETRATING SPR") == nil)
    }

    @Test func readsARegisterReceiptWithSKUsAndQuantities() {
        let r = ReceiptParser.parse(Self.ace)
        #expect(r.items == [
            .init(name: "11 OZ BLASTER PENETRATING SPR", partNumber: "1004892", quantity: 1, lineTotal: 12.99),
            .init(name: "MISC HILLMAN FASTENERS", partNumber: "502", quantity: 3, lineTotal: 2.97),
        ])
        #expect(r.subtotal == 15.96 && r.tax == 1.56 && r.total == 17.52)
        #expect(r.checks)
    }

    @Test func readsAnOrderPage() {
        let r = ReceiptParser.parse(Self.amazon)
        #expect(r.items == [.init(name: "Genuine Honda And Acura Brake Fluid Dot 3 (Pack Of 2)", quantity: 2, lineTotal: 20.45)])
        #expect(r.subtotal == 20.45 && r.tax == 1.99 && r.shipping == 0 && r.total == 22.44)
        #expect(r.checks)
    }

    @Test func quantityFromPriceEachWhenItsDigitIsMissed() {
        // The simulator's read of the photo lost the "3" in "502 3 EA".
        var lines = Self.ace
        lines[5] = "502  EA  ,99 EA"
        let r = ReceiptParser.parse(lines)
        #expect(r.items.last?.quantity == 3)
        #expect(r.items.last?.partNumber == "502")
    }

    @Test func codeLineWithStrayMarks() {
        // The phone's read of the photo: a "/" and no quantity.
        var lines = Self.ace
        lines[3] = "1004892/ EA EA $12.99 EA"
        let r = ReceiptParser.parse(lines)
        #expect(r.items.count == 2)
        #expect(r.items.first?.partNumber == "1004892")
        #expect(r.checks)
        #expect(ReceiptParser.registerCode("11 OZ BLASTER PENETRATING SPR $12.99") == nil)
    }

    @Test func amountsIncludingCommaDecimals() {
        #expect(ReceiptParser.amounts(in: "SUB-TOTAL:$  15,96  TAX:  1.56") == [15.96, 1.56])
        #expect(ReceiptParser.amounts(in: "502  3 EA  ,99  EA") == [0.99])
        #expect(ReceiptParser.amounts(in: "Order total $1,234.56") == [1234.56])
        #expect(ReceiptParser.amounts(in: "Order # 113-2014536") == [])
    }

    @Test func checksCatchAMissedItem() {
        var r = ReceiptParser.parse(Self.ace)
        r.items.removeLast()
        #expect(!r.checks)
    }

    @Test func taxIsSplitByPrice() {
        let r = ReceiptParser.parse(Self.ace)
        // Just the fasteners: $2.97 of $15.96, so 18.6% of the $1.56 tax.
        let fasteners = ReceiptSplit.parts(of: r, chosen: [r.items[1].id], includeShipping: true)
        #expect(fasteners.count == 1)
        #expect(fasteners[0].total == 3.26 && fasteners[0].quantity == 3 && fasteners[0].partNumber == "502")
        // The receipt's price each, with the tax share kept separately.
        #expect(abs(fasteners[0].priceEach - 0.99) < 0.0001)
        #expect(abs(fasteners[0].taxShare - 0.29) < 0.0001)
        // Both: exactly the receipt's total.
        let both = ReceiptSplit.parts(of: r, chosen: Set(r.items.map(\.id)), includeShipping: true)
        #expect(abs(both.reduce(0) { $0 + $1.total } - 17.52) < 0.001)
    }

    @Test func shippingIsSplitOnlyWhenIncluded() {
        let item = ReceiptParser.Item(name: "Pads", lineTotal: 40)
        let other = ReceiptParser.Item(name: "Snacks", lineTotal: 10)
        let r = ReceiptParser.Receipt(items: [item, other], subtotal: 50, tax: 5, shipping: 10, total: 65)
        #expect(ReceiptSplit.parts(of: r, chosen: [item.id], includeShipping: true).first?.total == 52)
        #expect(ReceiptSplit.parts(of: r, chosen: [item.id], includeShipping: false).first?.total == 44)
    }

    @Test func tiltedPhotoStillPutsPricesOnTheirLines() {
        // A receipt turned 3°: the right column sits higher than the left.
        let tilt = 3.0 * .pi / 180
        func box(_ text: String, x: Double, y: Double) -> ReceiptParser.TextBox {
            let ry = y + x * tan(tilt)
            return .init(text: text, topLeft: CGPoint(x: x, y: ry + 0.01), topRight: CGPoint(x: x + 0.05, y: ry + 0.01),
                         bottomLeft: CGPoint(x: x, y: ry), bottomRight: CGPoint(x: x + 0.05, y: ry))
        }
        let lines = ReceiptParser.lines(from: [
            box("BRAKE CLEANER", x: 0.1, y: 0.50), box("$6.49", x: 0.8, y: 0.50),
            box("SUB-TOTAL", x: 0.1, y: 0.47), box("6.49", x: 0.8, y: 0.47),
            box("TOTAL", x: 0.1, y: 0.44), box("7.02", x: 0.8, y: 0.44),
        ], aspect: 1)
        #expect(lines == ["BRAKE CLEANER  $6.49", "SUB-TOTAL  6.49", "TOTAL  7.02"])
    }
}
