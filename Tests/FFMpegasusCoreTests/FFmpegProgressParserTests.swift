import XCTest
@testable import FFMpegasusCore

final class FFmpegProgressParserTests: XCTestCase {
    func testParsesOutTimeTimestamp() {
        let progress = FFmpegProgressParser().parse("""
        frame=12
        out_time=00:01:02.500000
        progress=continue
        """)

        XCTAssertEqual(progress?.outTime ?? 0, 62.5, accuracy: 0.0001)
        XCTAssertEqual(progress?.progress, "continue")
    }

    func testParsesOutTimeMicroseconds() {
        let progress = FFmpegProgressParser().parse("""
        out_time_ms=2500000
        progress=end
        """)

        XCTAssertEqual(progress?.outTime ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(progress?.progress, "end")
    }
}
