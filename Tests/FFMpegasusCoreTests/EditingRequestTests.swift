import XCTest
@testable import FFMpegasusCore

final class EditingRequestTests: XCTestCase {
    func testDurationCalculationWithoutTrims() throws {
        let plan = try TrimPlan(sourceDuration: 30, removeStartSeconds: 0, removeEndSeconds: 0)

        XCTAssertEqual(plan.startTime, 0)
        XCTAssertEqual(plan.outputDuration, 30)
    }

    func testFirstSecondsRemovalCalculation() throws {
        let plan = try TrimPlan(sourceDuration: 30, removeStartSeconds: 5, removeEndSeconds: 0)

        XCTAssertEqual(plan.startTime, 5)
        XCTAssertEqual(plan.outputDuration, 25)
    }

    func testLastSecondsRemovalCalculation() throws {
        let plan = try TrimPlan(sourceDuration: 30, removeStartSeconds: 0, removeEndSeconds: 7)

        XCTAssertEqual(plan.startTime, 0)
        XCTAssertEqual(plan.outputDuration, 23)
    }

    func testCombinedTrimCalculation() throws {
        let plan = try TrimPlan(sourceDuration: 30, removeStartSeconds: 4, removeEndSeconds: 6)

        XCTAssertEqual(plan.startTime, 4)
        XCTAssertEqual(plan.outputDuration, 20)
    }

    func testInvalidTrimValues() {
        XCTAssertThrowsError(try TrimPlan(sourceDuration: 30, removeStartSeconds: -1, removeEndSeconds: 0)) { error in
            XCTAssertEqual(error as? EditingValidationError, .negativeTrimValue)
        }

        XCTAssertThrowsError(try TrimPlan(sourceDuration: 30, removeStartSeconds: 20, removeEndSeconds: 10)) { error in
            XCTAssertEqual(error as? EditingValidationError, .emptyResult)
        }

        XCTAssertThrowsError(try TrimPlan(sourceDuration: 0, removeStartSeconds: 0, removeEndSeconds: 0)) { error in
            XCTAssertEqual(error as? EditingValidationError, .invalidSourceDuration)
        }
    }
}
