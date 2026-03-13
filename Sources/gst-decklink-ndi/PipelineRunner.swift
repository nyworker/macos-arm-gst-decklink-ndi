import Foundation

actor PipelineRunner {
    private let config: Config
    private var process: Process?
    private var shouldStop = false
    private var restartCount = 0

    init(config: Config) {
        self.config = config
    }

    // MARK: - Public API

    /// Build the gst-launch-1.0 argument list from current config.
    func buildArguments() -> [String] {
        var args: [String] = ["-e"]

        let dev    = config.deviceNumber
        let mode   = config.videoMode
        let name   = config.ndiName
        let qmax   = config.queueMaxBuffers
        let qleaky = config.queueLeaky

        if config.enableAudio {
            // Mode B / C: combiner + video + audio
            args += [
                "ndisinkcombiner", "name=combiner",
                "!", "ndisink", "ndi-name=\(name)", "sync=false",
            ]

            // Video branch
            var vidProps = "decklinkvideosrc device-number=\(dev) mode=\(mode)"
            if config.enableCC  { vidProps += " output-cc=true" }
            if config.enableSCTE35 { vidProps += " output-vanc=true" }
            args += vidProps.split(separator: " ").map(String.init)
            args += [
                "!", "queue", "max-size-buffers=\(qmax)", "leaky=\(qleaky)",
                "!", "combiner.video",
            ]

            // Audio branch
            let channels = config.audioChannels
            args += [
                "decklinkaudiosrc", "device-number=\(dev)",
                "!", "queue", "max-size-buffers=\(qmax)", "leaky=\(qleaky)",
                "!", "audioconvert",
                "!", "audio/x-raw,format=F32LE,rate=48000,channels=\(channels)",
                "!", "combiner.audio",
            ]
        } else {
            // Mode A: video only, direct to ndisink
            var vidProps = "decklinkvideosrc device-number=\(dev) mode=\(mode)"
            if config.enableCC     { vidProps += " output-cc=true" }
            if config.enableSCTE35 { vidProps += " output-vanc=true" }
            args += vidProps.split(separator: " ").map(String.init)
            args += [
                "!", "queue", "max-size-buffers=\(qmax)", "leaky=\(qleaky)",
                "!", "ndisink", "ndi-name=\(name)", "sync=false",
            ]
        }

        return args
    }

    /// Run the pipeline, restarting on failure per config.
    func run() async throws {
        shouldStop = false
        restartCount = 0

        while !shouldStop {
            let args = buildArguments()
            log(pipeline, "Launching: \(config.gstLaunchPath) \(args.joined(separator: " "))")

            let exitCode = try await launchAndWait(args: args)

            guard !shouldStop else {
                log(pipeline, "Pipeline stopped by request (exit \(exitCode)).")
                break
            }

            handleExit(exitCode: exitCode)

            let max = config.maxRestartAttempts
            if max > 0 && restartCount >= max {
                log(restart, level: .error,
                    "Reached maximum restart attempts (\(max)). Exiting.")
                break
            }

            restartCount += 1
            let delay = config.restartDelaySeconds
            log(restart, "Restarting in \(delay)s (attempt \(restartCount)\(max > 0 ? "/\(max)" : ""))…")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// Signal the running pipeline to stop.
    func stop() async {
        shouldStop = true
        guard let proc = process, proc.isRunning else { return }
        log(siglog, "Sending SIGTERM to pipeline (pid \(proc.processIdentifier))…")
        proc.terminate()

        // Wait up to 5 s, then SIGKILL.
        let pid = proc.processIdentifier
        for _ in 0 ..< 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !proc.isRunning { return }
        }
        if proc.isRunning {
            log(siglog, level: .error, "Pipeline did not exit; sending SIGKILL to \(pid).")
            kill(pid, SIGKILL)
        }
    }

    // MARK: - Private

    private func launchAndWait(args: [String]) async throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.gstLaunchPath)
        proc.arguments = args
        proc.environment = buildEnvironment()

        // Pipe stderr so we can forward it to os_log.
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        self.process = proc

        // Start async stderr reader.
        let stderrHandle = stderrPipe.fileHandleForReading
        let logTask = Task {
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                        log(pipeline, String(line))
                    }
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { p in
                logTask.cancel()
                continuation.resume(returning: p.terminationStatus)
            }
            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleExit(exitCode: Int32) {
        if exitCode == 0 {
            log(pipeline, "Pipeline exited cleanly (0).")
        } else {
            log(pipeline, level: .error, "Pipeline exited with code \(exitCode).")
        }
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Map logLevel → GST_DEBUG numeric level.
        let gstDebug: String
        switch config.logLevel.lowercased() {
        case "none":    gstDebug = "0"
        case "error":   gstDebug = "1"
        case "warning": gstDebug = "2"
        case "info":    gstDebug = "3"
        case "debug":   gstDebug = "5"
        case "trace":   gstDebug = "7"
        default:        gstDebug = "2"
        }
        env["GST_DEBUG"] = gstDebug

        // Preserve / set NDI SDK library path.
        let ndiLib = "/Library/NDI SDK for Apple/lib/macOS"
        if let existing = env["DYLD_LIBRARY_PATH"], !existing.isEmpty {
            if !existing.contains(ndiLib) {
                env["DYLD_LIBRARY_PATH"] = "\(ndiLib):\(existing)"
            }
        } else {
            env["DYLD_LIBRARY_PATH"] = ndiLib
        }

        return env
    }
}
