import XCTest
@testable import FFMpegasusCore

final class TrimSecondsParserTests: XCTestCase {
    func testParsesZero() {
        XCTAssertEqual(TrimSecondsParser.parse("0"), 0)
    }

    func testParsesWholeSeconds() {
        XCTAssertEqual(TrimSecondsParser.parse("5"), 5)
    }

    func testParsesDecimalSeconds() {
        XCTAssertEqual(TrimSecondsParser.parse("2.5"), 2.5)
    }

    func testParsesLeadingAndTrailingWhitespace() {
        XCTAssertEqual(TrimSecondsParser.parse("  2.5\n"), 2.5)
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(TrimSecondsParser.parse(""))
        XCTAssertNil(TrimSecondsParser.parse("   "))
    }

    func testRejectsNonNumericInput() {
        XCTAssertNil(TrimSecondsParser.parse("abc"))
    }

    func testRejectsNegativeInput() {
        XCTAssertNil(TrimSecondsParser.parse("-1"))
    }
}
