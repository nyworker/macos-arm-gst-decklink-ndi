import Foundation

struct Config: Codable {
    var deviceNumber: Int = 0
    var videoMode: String = "auto"
    var audioChannels: Int = 2
    var ndiName: String = "DeckLink NDI"
    var enableAudio: Bool = true
    var enableCC: Bool = true
    var enableSCTE35: Bool = false
    var queueMaxBuffers: Int = 2
    var queueLeaky: String = "downstream"
    var restartDelaySeconds: Double = 2.0
    var maxRestartAttempts: Int = 0     // 0 = unlimited
    var gstLaunchPath: String = "/opt/homebrew/bin/gst-launch-1.0"
    var logLevel: String = "info"
}

extension Config {
    /// Load from a JSON file, using snake_case key decoding.
    static func load(from path: String) throws -> Config {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Config.self, from: data)
    }
}
