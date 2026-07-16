import XCTest
@testable import FFMpegasusCore

final class FFprobeDecodingTests: XCTestCase {
    func testFFprobeJSONDecoding() throws {
        let json = """
        {
          "streams": [
            {
              "codec_name": "h264",
              "codec_type": "video",
              "width": 1920,
              "height": 1080,
              "avg_frame_rate": "30000/1001"
            },
            {
              "codec_name": "aac",
              "codec_type": "audio"
            }
          ],
          "format": {
            "duration": "123.456"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FFprobeResponse.self, from: json)
        let metadata = response.videoMetadata()

        XCTAssertEqual(metadata.duration, 123.456, accuracy: 0.0001)
        XCTAssertEqual(metadata.width, 1920)
        XCTAssertEqual(metadata.height, 1080)
        XCTAssertEqual(metadata.videoCodec, "h264")
        XCTAssertEqual(metadata.audioCodec, "aac")
        XCTAssertEqual(metadata.frameRate ?? 0, 29.970, accuracy: 0.001)
    }

    func testFFprobeRotationMetadataDecoding() throws {
        let json = """
        {
          "streams": [
            {
              "codec_name": "h264",
              "codec_type": "video",
              "width": 1920,
              "height": 1080,
              "side_data_list": [
                {
                  "rotation": -90
                }
              ]
            }
          ],
          "format": {
            "duration": "10.0"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FFprobeResponse.self, from: json)
        let metadata = response.videoMetadata()

        XCTAssertEqual(metadata.rotationDegrees, 270)
    }
}
