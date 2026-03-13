import OSLog

let pipeline = Logger(subsystem: "com.gst-decklink-ndi", category: "pipeline")
let restart  = Logger(subsystem: "com.gst-decklink-ndi", category: "restart")
let dep      = Logger(subsystem: "com.gst-decklink-ndi", category: "dependency")
let siglog   = Logger(subsystem: "com.gst-decklink-ndi", category: "signal")

/// When true, duplicate all log messages to stderr for interactive use.
/// Set once at startup before any async work; access is inherently serialised.
nonisolated(unsafe) var isVerboseLogging = false

func log(_ logger: Logger, level: OSLogType = .info, _ message: String) {
    logger.log(level: level, "\(message, privacy: .public)")
    if isVerboseLogging {
        let prefix: String
        switch level {
        case .error:   prefix = "[ERROR]"
        case .fault:   prefix = "[FAULT]"
        case .debug:   prefix = "[DEBUG]"
        default:       prefix = "[INFO] "
        }
        fputs("\(prefix) \(message)\n", stderr)
    }
}
