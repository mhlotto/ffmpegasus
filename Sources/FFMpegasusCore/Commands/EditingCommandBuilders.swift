import Foundation

public extension VideoEditingService {
    func streamCopyArguments(for request: EditingRequest) throws -> [String] {
        let plan = try request.trimPlan()
        switch request.effectiveTrimExecutionMode {
        case .fast:
            return [
                "-y",
                "-nostdin",
                "-ss", TimeFormatting.ffmpegSeconds(plan.startTime),
                "-i", request.inputURL.path,
                "-t", TimeFormatting.ffmpegSeconds(plan.outputDuration),
                "-map", "0",
                "-c", "copy",
                "-progress", "pipe:1",
                "-nostats",
                request.outputURL.path
            ]
        case .accurate:
            guard request.hasVideoStream else { throw CompressionValidationError.missingVideoStream }
            let quality = try CompressionQualitySettings(crf: 20, preset: .medium)
            var arguments = [
                "-y",
                "-nostdin",
                "-ss", TimeFormatting.ffmpegSeconds(plan.startTime),
                "-i", request.inputURL.path,
                "-t", TimeFormatting.ffmpegSeconds(plan.outputDuration),
                "-map", "0:v:0"
            ]
            if request.hasAudioStream {
                arguments += ["-map", "0:a:0?"]
            }
            arguments += request.exportProfile.videoArguments(quality: quality)
            if request.hasAudioStream {
                arguments += request.exportProfile.audioArguments()
            }
            arguments += request.exportProfile.containerArguments
            arguments += ["-progress", "pipe:1", "-nostats", request.outputURL.path]
            return arguments
        }
    }

    func removeAudioArguments(for request: RemoveAudioRequest) -> [String] {
        [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v",
            "-c:v", "copy",
            "-an",
            "-progress", "pipe:1",
            "-nostats",
            request.outputURL.path
        ]
    }

    func command(ffmpegPath: String, request: EditingRequest) throws -> EditingCommand {
        switch request.method {
        case .streamCopy:
            EditingCommand(executablePath: ffmpegPath, arguments: try streamCopyArguments(for: request))
        }
    }

    func removeAudioCommand(ffmpegPath: String, request: RemoveAudioRequest) -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: removeAudioArguments(for: request))
    }

    func compressionArguments(for request: CompressionRequest) throws -> [String] {
        let quality = try request.qualitySettings()
        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.audioMode == .keep, request.hasAudioStream {
            arguments += ["-map", "0:a:0?"]
        }

        if let scaleFilter = try request.scaleFilter() {
            arguments += ["-vf", scaleFilter]
        }

        arguments += request.exportProfile.videoArguments(quality: quality)

        if request.audioMode == .keep, request.hasAudioStream {
            arguments += request.exportProfile.audioArguments()
        } else {
            arguments += ["-an"]
        }

        arguments += request.exportProfile.containerArguments
        arguments += ["-progress", "pipe:1", "-nostats", request.outputURL.path]
        return arguments
    }

    func compressionCommand(ffmpegPath: String, request: CompressionRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try compressionArguments(for: request))
    }

    func transformArguments(for request: VideoTransformRequest) throws -> [String] {
        guard request.hasVideoStream else { throw VideoTransformValidationError.missingVideoStream }
        let filterChain = try request.filterChain()
        guard !filterChain.contains("\""), !filterChain.contains("'") else {
            throw VideoTransformValidationError.invalidFilterChain
        }

        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.hasAudioStream {
            arguments += ["-map", "0:a:0?"]
        }

        let quality = try CompressionQualitySettings(crf: 20, preset: .medium)
        arguments += ["-vf", filterChain]
        arguments += request.exportProfile.videoArguments(quality: quality)

        if request.hasAudioStream {
            arguments += request.exportProfile.audioArguments()
        } else {
            arguments += ["-an"]
        }

        arguments += [
            "-metadata:s:v:0", "rotate=0"
        ]
        arguments += request.exportProfile.containerArguments
        arguments += ["-progress", "pipe:1", "-nostats", request.outputURL.path]

        return arguments
    }

    func transformCommand(ffmpegPath: String, request: VideoTransformRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try transformArguments(for: request))
    }

    func cropArguments(for request: CropRequest) throws -> [String] {
        try request.validate()
        let filterChain = try request.filterChain()
        guard !filterChain.contains("\""), !filterChain.contains("'") else {
            throw VideoTransformValidationError.invalidFilterChain
        }

        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.hasAudioStream {
            arguments += ["-map", "0:a:0?"]
        }

        let quality = try CompressionQualitySettings(crf: 20, preset: .medium)
        arguments += ["-vf", filterChain]
        arguments += request.exportProfile.videoArguments(quality: quality)

        if request.hasAudioStream {
            arguments += request.exportProfile.audioArguments()
        } else {
            arguments += ["-an"]
        }

        arguments += [
            "-metadata:s:v:0", "rotate=0"
        ]
        arguments += request.exportProfile.containerArguments
        arguments += ["-progress", "pipe:1", "-nostats", request.outputURL.path]

        return arguments
    }

    func cropCommand(ffmpegPath: String, request: CropRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try cropArguments(for: request))
    }

    func editPlanArguments(for plan: VideoEditPlan) throws -> [String] {
        try plan.validate()
        let trimPlan = try plan.trimPlan()
        let strategy = try plan.executionStrategy()
        var arguments = ["-y", "-nostdin"]

        if plan.trim != nil {
            arguments += ["-ss", TimeFormatting.ffmpegSeconds(trimPlan.startTime)]
        }

        arguments += ["-i", plan.inputURL.path]

        if plan.trim != nil {
            arguments += ["-t", TimeFormatting.ffmpegSeconds(trimPlan.outputDuration)]
        }

        switch strategy {
        case .streamCopy:
            arguments += ["-map", "0:v:0"]
            if plan.audioMode == .keep, plan.hasAudioStream {
                arguments += ["-map", "0:a:0?"]
                arguments += ["-c", "copy"]
            } else {
                arguments += ["-c:v", "copy", "-an"]
            }

        case .reencode:
            let quality = try plan.qualitySettings()
            arguments += ["-map", "0:v:0"]
            if plan.audioMode == .keep, plan.hasAudioStream {
                arguments += ["-map", "0:a:0?"]
            }
            if let filterChain = try plan.filterChain() {
                guard !filterChain.contains("\""), !filterChain.contains("'") else {
                    throw VideoTransformValidationError.invalidFilterChain
                }
                arguments += ["-vf", filterChain]
            }
            if let speed = plan.speed, plan.audioMode == .keep, plan.hasAudioStream {
                let audioFilter = try speed.audioTempoFilter()
                guard !audioFilter.contains("\""), !audioFilter.contains("'") else {
                    throw VideoSpeedValidationError.invalidSpeed
                }
                arguments += ["-af", audioFilter]
            }
            arguments += plan.exportProfile.videoArguments(quality: quality)
            if plan.audioMode == .keep, plan.hasAudioStream {
                arguments += plan.exportProfile.audioArguments()
            } else {
                arguments += ["-an"]
            }
            arguments += ["-metadata:s:v:0", "rotate=0"]
            arguments += plan.exportProfile.containerArguments
        }

        arguments += [
            "-progress", "pipe:1",
            "-nostats",
            plan.outputURL.path
        ]
        return arguments
    }

    func editPlanCommand(ffmpegPath: String, plan: VideoEditPlan) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try editPlanArguments(for: plan))
    }

    func speedArguments(for request: VideoSpeedRequest) throws -> [String] {
        try request.validateForExport()
        let videoFilter = request.speed.videoFilter()
        guard !videoFilter.contains("\""), !videoFilter.contains("'") else {
            throw VideoSpeedValidationError.invalidSpeed
        }

        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.keepsAudio {
            let audioFilter = try request.speed.audioTempoFilter()
            guard !audioFilter.contains("\""), !audioFilter.contains("'") else {
                throw VideoSpeedValidationError.invalidSpeed
            }
            arguments += ["-map", "0:a:0?"]
            arguments += ["-vf", videoFilter, "-af", audioFilter]
        } else {
            arguments += ["-vf", videoFilter]
        }

        let quality = try CompressionQualitySettings(crf: 20, preset: .medium)
        arguments += request.exportProfile.videoArguments(quality: quality)

        if request.keepsAudio {
            arguments += request.exportProfile.audioArguments()
        } else {
            arguments += ["-an"]
        }

        arguments += [
            "-metadata:s:v:0", "rotate=0"
        ]
        arguments += request.exportProfile.containerArguments
        arguments += ["-progress", "pipe:1", "-nostats", request.outputURL.path]
        return arguments
    }

    func speedCommand(ffmpegPath: String, request: VideoSpeedRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try speedArguments(for: request))
    }

    func frameExportArguments(for request: FrameExportRequest) throws -> [String] {
        try request.validate()
        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-ss", FrameExportTimestamp.ffmpegSeconds(request.timestampSeconds),
            "-map", "0:v:0",
            "-frames:v", "1"
        ]
        if request.format == .jpeg {
            guard let jpegQuality = request.jpegQuality else {
                throw FrameExportValidationError.invalidJPEGQuality
            }
            arguments += ["-q:v", String(jpegQuality.ffmpegValue)]
        }
        arguments += [
            "-an",
            "-sn",
            "-dn",
            request.outputURL.path
        ]
        return arguments
    }

    func frameExportCommand(ffmpegPath: String, request: FrameExportRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try frameExportArguments(for: request))
    }

    func intervalFrameExportArguments(for request: IntervalFrameExportRequest) throws -> [String] {
        try request.validate()
        let interval = FrameExportTimestamp.compactSeconds(request.interval.seconds)
        let filter = "setpts=PTS-STARTPTS,fps=1/\(interval):start_time=0"
        var arguments = [
            "-y",
            "-nostdin",
            "-ss", FrameExportTimestamp.ffmpegSeconds(request.range.startSeconds),
            "-i", request.inputURL.path,
            "-t", FrameExportTimestamp.ffmpegSeconds(request.range.duration),
            "-map", "0:v:0",
            "-vf", filter,
            "-start_number", "1"
        ]
        if request.format == .jpeg {
            guard let jpegQuality = request.jpegQuality else {
                throw FrameExportValidationError.invalidJPEGQuality
            }
            arguments += ["-q:v", String(jpegQuality.ffmpegValue)]
        }
        arguments += [
            "-an",
            "-sn",
            "-dn",
            "-progress", "pipe:1",
            "-nostats",
            request.outputPattern.path
        ]
        return arguments
    }

    func intervalFrameExportCommand(ffmpegPath: String, request: IntervalFrameExportRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try intervalFrameExportArguments(for: request))
    }

    func gifExportArguments(for request: GIFExportRequest) throws -> [String] {
        try request.validate()
        let filter = try request.filterComplex()
        guard !filter.contains("\""), !filter.contains("'") else {
            throw GIFExportValidationError.invalidGIF
        }
        return [
            "-y",
            "-nostdin",
            "-ss", FrameExportTimestamp.ffmpegSeconds(request.range.startSeconds),
            "-i", request.inputURL.path,
            "-t", FrameExportTimestamp.ffmpegSeconds(request.range.duration),
            "-filter_complex", filter,
            "-loop", request.loopMode.ffmpegLoopValue,
            "-an",
            "-sn",
            "-dn",
            "-progress", "pipe:1",
            "-nostats",
            request.outputURL.path
        ]
    }

    func gifExportCommand(ffmpegPath: String, request: GIFExportRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try gifExportArguments(for: request))
    }
}
