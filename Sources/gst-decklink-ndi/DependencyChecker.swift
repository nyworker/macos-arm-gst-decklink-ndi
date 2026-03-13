import Foundation

enum DependencyError: Error, CustomStringConvertible {
    case missingExecutable(String)
    case versionTooOld(String, found: String, required: String)
    case missingElement(String)

    var description: String {
        switch self {
        case .missingExecutable(let path):
            return "Required executable not found: \(path)"
        case .versionTooOld(let name, let found, let required):
            return "\(name) version \(found) is below required \(required)"
        case .missingElement(let name):
            return "Required GStreamer element not found: \(name)"
        }
    }
}

struct DependencyChecker {
    let config: Config

    func run() throws {
        try checkGstLaunch()
        try checkElement("decklinkvideosrc")
        try checkElement("ndisink")
        try checkElement("ndisinkcombiner")
        if config.enableAudio {
            try checkElement("decklinkaudiosrc")
        }
        if config.enableCC {
            try checkElement("ccextractor")
        }
        checkNDISDK()
        checkBlackmagic()
    }

    // MARK: - Private

    private func checkGstLaunch() throws {
        let path = config.gstLaunchPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw DependencyError.missingExecutable(path)
        }

        let output = runCommand(path, args: ["--version"]) ?? ""
        // Parse "GStreamer Tools version 1.28.0" or similar
        if let versionString = parseVersion(from: output) {
            let parts = versionString.split(separator: ".").compactMap { Int($0) }
            if parts.count >= 2 {
                let major = parts[0], minor = parts[1]
                if major < 1 || (major == 1 && minor < 20) {
                    throw DependencyError.versionTooOld(
                        "gst-launch-1.0",
                        found: versionString,
                        required: "1.20"
                    )
                }
            }
            log(dep, "gst-launch-1.0 version \(versionString) ✓")
        } else {
            log(dep, level: .default, "gst-launch-1.0 found (version string not parsed)")
        }
    }

    private func checkElement(_ name: String) throws {
        let inspectPath = config.gstLaunchPath
            .replacingOccurrences(of: "gst-launch-1.0", with: "gst-inspect-1.0")
        let output = runCommand(inspectPath, args: [name])
        if output == nil || output!.contains("No such element") || output!.isEmpty {
            throw DependencyError.missingElement(name)
        }
        log(dep, "GStreamer element '\(name)' ✓")
    }

    private func checkNDISDK() {
        let searchPaths: [String] = [
            "/Library/NDI SDK for Apple/lib/macOS/libndi_newtek.dylib",
            "/opt/homebrew/lib/libndi_newtek.dylib",
        ]
        // Also check DYLD_LIBRARY_PATH entries
        var allPaths = searchPaths
        if let dyldPaths = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"] {
            for dir in dyldPaths.split(separator: ":") {
                allPaths.append("\(dir)/libndi_newtek.dylib")
            }
        }

        for path in allPaths {
            if FileManager.default.fileExists(atPath: path) {
                log(dep, "NDI SDK found at \(path) ✓")
                return
            }
        }

        log(dep, level: .error,
            "NDI SDK (libndi_newtek.dylib) not found. " +
            "Download from: https://ndi.video/for-developers/ndi-sdk/ " +
            "— install the 'NDI SDK for Apple' package.")
    }

    private func checkBlackmagic() {
        let bmPath = "/Library/Application Support/Blackmagic Design"
        if FileManager.default.fileExists(atPath: bmPath) {
            log(dep, "Blackmagic Desktop Video found ✓")
        } else {
            log(dep, level: .error,
                "Blackmagic Desktop Video does not appear to be installed at '\(bmPath)'. " +
                "Download from: https://www.blackmagicdesign.com/support/family/capture-and-playback")
        }
    }

    // MARK: - Helpers

    /// Run a command, return combined stdout+stderr, or nil on launch failure.
    @discardableResult
    private func runCommand(_ path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseVersion(from text: String) -> String? {
        // Match e.g. "version 1.28.0" or "1.28.0_1"
        let pattern = #"(\d+\.\d+\.\d+)"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }
}
