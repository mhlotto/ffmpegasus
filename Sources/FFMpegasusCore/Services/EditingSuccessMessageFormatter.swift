import Foundation

enum EditingSuccessMessageFormatter {
    static func compressionSuccessMessage(inputURL: URL, outputURL: URL, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines: [String] = []
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
            let delta = (Double(inputSize) - Double(outputSize)) / Double(inputSize) * 100
            if delta >= 0 {
                lines.append(String(format: "Reduced by: %.1f%%", delta))
            } else {
                lines.append(String(format: "Output is %.1f%% larger than the original.", abs(delta)))
            }
        }
        lines.append("Saved: \(outputURL.path)")
        return lines.joined(separator: "\n")
    }

    static func transformSuccessMessage(request: VideoTransformRequest, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines = [
            "Rotation: \(request.rotation.title)",
            "Horizontal flip: \(request.flipHorizontal ? "Yes" : "No")",
            "Vertical flip: \(request.flipVertical ? "Yes" : "No")"
        ]
        if let dimensions = try? request.outputDimensions() {
            lines.append("Output: \(dimensions.width)x\(dimensions.height)")
        }
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("Saved: \(request.outputURL.path)")
        return lines.joined(separator: "\n")
    }

    static func editPlanSuccessMessage(plan: VideoEditPlan, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines = ["Applied:"]
        lines += editPlanAppliedLines(plan: plan).map { "- \($0)" }
        if let dimensions = try? plan.outputDimensions() {
            lines.append("")
            lines.append("Output:")
            lines.append("\(dimensions.width)x\(dimensions.height)")
        }
        if (try? plan.executionStrategy()) == .reencode {
            lines.append("H.264")
        }
        if let duration = try? plan.outputDuration() {
            lines.append(String(format: "Duration: %.1f seconds", duration))
        }
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("")
        lines.append("Saved:")
        lines.append(plan.outputURL.path)
        return lines.joined(separator: "\n")
    }

    static func speedSuccessMessage(request: VideoSpeedRequest, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines = [
            "Speed: \(request.speed.filenameLabel)",
            String(format: "Original duration: %.1f seconds", request.sourceDuration)
        ]
        if let expected = try? request.expectedDuration() {
            lines.append(String(format: "Output duration: %.1f seconds", expected))
        }
        lines.append("Video: H.264")
        lines.append("Audio: \(request.keepsAudio ? "AAC" : "Removed")")
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("Saved: \(request.outputURL.path)")
        return lines.joined(separator: "\n")
    }

    static func frameExportSuccessMessage(request: FrameExportRequest, imageInfo: FrameImageInfo, outputSize: UInt64?) -> String {
        var lines = [
            "Time: \(FrameExportTimestamp.displayTime(request.timestampSeconds))",
            "Format: \(request.format.title)",
            "Dimensions: \(imageInfo.dimensions.width)x\(imageInfo.dimensions.height)"
        ]
        if let outputSize {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("")
        lines.append("Saved:")
        lines.append(request.outputURL.path)
        return lines.joined(separator: "\n")
    }

    static func intervalFrameExportSuccessMessage(request: IntervalFrameExportRequest, result: IntervalFrameExportResult) -> String {
        [
            "Format: \(request.format.title)",
            "Interval: \(FrameExportTimestamp.compactSeconds(request.interval.seconds)) seconds",
            "Range: \(FrameExportTimestamp.displayTime(request.range.startSeconds)) to \(FrameExportTimestamp.displayTime(request.range.endSeconds))",
            "Images created: \(result.imageCount)",
            "Dimensions: \(result.dimensions.width)x\(result.dimensions.height)",
            "",
            "Saved to:",
            request.outputDirectoryURL.path
        ].joined(separator: "\n")
    }

    private static func editPlanAppliedLines(plan: VideoEditPlan) -> [String] {
        var lines: [String] = []
        if let trim = plan.trim {
            if trim.removeStartSeconds > 0 {
                lines.append(String(format: "Removed first %.3g seconds", trim.removeStartSeconds))
            }
            if trim.removeEndSeconds > 0 {
                lines.append(String(format: "Removed last %.3g seconds", trim.removeEndSeconds))
            }
        }
        if let transform = plan.transform {
            if transform.rotation != .none {
                lines.append("Rotated \(transform.rotation.title)")
            }
            if transform.flipHorizontal {
                lines.append("Flipped horizontally")
            }
            if transform.flipVertical {
                lines.append("Flipped vertically")
            }
        }
        if let resize = plan.resize {
            lines.append("Resized to \(resize.resolution.title)")
        }
        if let compression = plan.compression {
            lines.append("Compressed with \(compression.quality.title)")
        }
        if let speed = plan.speed {
            lines.append("Changed speed to \(speed.filenameLabel)")
        }
        if plan.audioMode == .remove {
            lines.append("Removed audio")
        }
        return lines.isEmpty ? ["No changes"] : lines
    }
}
