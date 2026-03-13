import ArgumentParser
import Foundation

@main
struct GstDecklinkNDI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gst-decklink-ndi",
        abstract: "Capture DeckLink video+audio and stream as NDI via GStreamer.",
        version: "1.0.0"
    )

    // MARK: - Options

    @Option(help: "DeckLink device number (0-based).")
    var device: Int = 0

    @Option(help: "GStreamer video mode (auto, 1080p30, 1080i60, 720p60, …).")
    var mode: String = "auto"

    @Option(name: .long, help: "NDI stream name.")
    var ndiName: String = "DeckLink NDI"

    @Option(name: .shortAndLong, help: "Path to JSON config file.")
    var config: String?

    @Flag(name: .long, help: "Disable audio capture.")
    var noAudio: Bool = false

    @Flag(name: .long, help: "Disable closed-caption extraction.")
    var noCC: Bool = false

    @Flag(name: .long, help: "Enable SCTE-35 best-effort extraction (logs limitation notice).")
    var scte35: Bool = false

    @Option(name: .long, help: "Seconds to wait before restarting on failure.")
    var restartDelay: Double = 2.0

    @Option(name: .long, help: "Maximum restart attempts (0 = unlimited).")
    var maxRestarts: Int = 0

    @Flag(name: .shortAndLong, help: "Echo log messages to stderr.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Print the pipeline command and exit without running.")
    var dryRun: Bool = false

    // MARK: - Entry point

    mutating func run() async throws {
        // 1. Set global verbose flag.
        isVerboseLogging = verbose

        // 2. Load config from file (if provided), then overlay CLI flags.
        var cfg: Config
        if let configPath = config {
            do {
                cfg = try Config.load(from: configPath)
                log(dep, "Loaded config from \(configPath)")
            } catch {
                fputs("[ERROR] Failed to load config '\(configPath)': \(error)\n", stderr)
                throw ExitCode.failure
            }
        } else {
            cfg = Config()
        }

        // CLI flags override file values.
        cfg.deviceNumber = device
        cfg.videoMode    = mode
        cfg.ndiName      = ndiName
        if noAudio { cfg.enableAudio = false }
        if noCC    { cfg.enableCC    = false }
        if scte35  { cfg.enableSCTE35 = true }
        cfg.restartDelaySeconds = restartDelay
        cfg.maxRestartAttempts  = maxRestarts

        // 3. Build runner (needed for both dry-run and real run).
        let runner = PipelineRunner(config: cfg)

        // 4. Dry-run: print command and exit immediately (no dep check needed).
        if dryRun {
            if cfg.enableSCTE35 {
                fputs("[NOTICE] --scte35: output-vanc=true added; SCTE cues will NOT reach NDI (no GStreamer SCTE-104 parser).\n", stderr)
            }
            let args = await runner.buildArguments()
            print("\(cfg.gstLaunchPath) \(args.joined(separator: " "))")
            return
        }

        // 5. SCTE-35 limitation notice (real run).
        if cfg.enableSCTE35 {
            fputs("""
            [NOTICE] --scte35 is best-effort only.
              decklinkvideosrc output-vanc=true extracts VANC data as GstMeta,
              but GStreamer has no SCTE-104 parser or SCTE-35 converter element.
              SCTE cues will NOT be forwarded to the NDI stream.
              Full SCTE-35 support requires a custom GStreamer plugin using the
              DeckLink C SDK VANC callbacks.\n
            """, stderr)
        }

        // 6. Dependency check (non-fatal for warnings).
        let checker = DependencyChecker(config: cfg)
        do {
            try checker.run()
        } catch {
            fputs("[FATAL] Dependency check failed: \(error)\n", stderr)
            throw ExitCode.failure
        }

        // 7. Install signal handlers (real run only).
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT,  SIG_IGN)

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler {
            log(siglog, "Received SIGTERM — stopping…")
            Task { await runner.stop() }
        }
        sigterm.resume()

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            log(siglog, "Received SIGINT — stopping…")
            Task { await runner.stop() }
        }
        sigint.resume()

        // 8. Run.
        log(pipeline, "Starting NDI stream '\(cfg.ndiName)' from DeckLink device \(cfg.deviceNumber)…")
        try await runner.run()
        log(pipeline, "Exited.")
    }
}

