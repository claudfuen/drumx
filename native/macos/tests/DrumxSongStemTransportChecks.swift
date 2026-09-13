import Foundation
import AVFoundation

@main
struct DrumxSongStemTransportChecks {
  static var checks = 0
  // Scheduling is far in the future, then the master is silenced immediately.
  // These checks inspect real audio nodes without playing anything to the user.
  static let silentCountdown: Double = 3600

  static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("Song stem transport check failed: \(message)") }
  }

  static func writeTone(to url: URL, frequency: Double) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
    buffer.frameLength = buffer.frameCapacity
    for frame in 0..<Int(buffer.frameLength) {
      let sample = Float(sin(Double(frame) * frequency * 2 * .pi / 48000)) * 0.1
      for channel in 0..<Int(format.channelCount) {
        buffer.floatChannelData![channel][frame] = sample
      }
    }
    var settings = format.settings
    settings[AVLinearPCMIsNonInterleaved] = false
    let file = try AVAudioFile(forWriting: url, settings: settings)
    try file.write(from: buffer)
  }

  static func song(stems: [String], files: [URL]) throws -> DrumxSong {
    let object: [String: Any] = ["schemaVersion": 1, "id": "stem-transport-" + UUID().uuidString,
      "title": "Original synthetic stem fixture", "artist": "Drumx checks",
      "sourceFormat": "chart", "durationSeconds": 1, "difficulties": ["expert"],
      "selectedDifficulty": "expert", "drumMode": "pro", "warnings": [],
      "charts": [["difficulty": "expert", "notes": [
        ["timeSeconds": 0.4, "durationSeconds": 0, "lane": "snare", "velocity": 100]
      ]]], "audio": zip(stems, files).map { ["stem": $0.0, "path": $0.1.path] },
      "previewStartSeconds": 0.25, "previewEndSeconds": 0.9]
    return try JSONDecoder().decode(DrumxSong.self, from: JSONSerialization.data(withJSONObject: object))
  }

  static func startSilently(_ transport: DrumxSongAudioTransport, _ audio: DrumxSongPreparedAudio,
                            position: Double = 0, mode: DrumxSongAudioMode = .performance,
                            performanceMuted: Bool = false) throws {
    try transport.start(audio, position: position, audioLead: 0, countdown: silentCountdown,
      mode: mode, performanceMuted: performanceMuted)
    transport.setVolume(0)
    check(transport.isRunning, "the real AVAudioEngine starts")
    check(transport.epoch + position > DrumxIO.hostNowSeconds() + 3500,
      "all scheduled audio remains far in the future")
  }

  static func waitForGains(_ transport: DrumxSongAudioTransport, _ expected: [Float], _ message: String) {
    let deadline = Date().addingTimeInterval(0.5)
    while transport.stemVolumes != expected && Date() < deadline { Thread.sleep(forTimeInterval: 0.002) }
    check(transport.stemVolumes == expected, message)
  }

  static func main() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("drumx-stem-transport-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    // The backing file is deliberately named drums.wav and the drum recordings
    // have opaque cache-like names. Transport must follow manifest identity.
    let names = ["drums.wav", "0-2048-123456.wav", "voice.wav", "3-2048-123456.wav",
      "1-2048-123456.wav", "2-2048-123456.wav", "guitar.wav"]
    let files = names.map { root.appendingPathComponent($0) }
    for (index, file) in files.enumerated() {
      try writeTone(to: file, frequency: Double(200 + index * 100))
    }
    let stems = ["song", "drums_1", "vocals", "drums_4", "drums_2", "drums_3", "guitar"]
    let fixture = try song(stems: stems, files: files)
    let prepared = try DrumxSongPreparedAudio.prepare(fixture)
    check(prepared.stems == stems, "native preparation retains every ordered manifest stem")
    check(prepared.files.map(\.url) == files, "native preparation uses the fixture files without changing their identity")
    check(abs(prepared.duration - 1) < 0.00001, "preparation retains the complete audio timeline")

    let audibleSource = prepared.files[1]
    let readBuffer = AVAudioPCMBuffer(pcmFormat: audibleSource.processingFormat, frameCapacity: 1024)!
    try audibleSource.read(into: readBuffer)
    check((0..<Int(readBuffer.frameLength)).contains { abs(readBuffer.floatChannelData![0][$0]) > 0.05 },
      "the suppressed drum fixture contains real nonzero audio")
    audibleSource.framePosition = 0

    let transport = DrumxSongAudioTransport()
    defer { transport.stop() }
    try startSilently(transport, prepared)
    let originalEpoch = transport.epoch
    let audible: [Float] = [1, 1, 1, 1, 1, 1, 1]
    let gated: [Float] = [1, 0, 1, 0, 0, 0, 1]
    check(transport.stemVolumes == audible && transport.mode == .performance && !transport.performanceMuted,
      "actual player nodes begin with recorded drums audible in follow-my-playing mode")
    transport.setPerformanceMuted(true)
    waitForGains(transport, gated, "a miss silences every recorded drum node while backing remains audible")
    check(transport.epoch == originalEpoch && transport.isRunning, "a miss changes gains without changing the playback clock")
    transport.setPerformanceMuted(false)
    waitForGains(transport, audible, "a correct hit restores all four recorded drum nodes")
    transport.setPerformanceMuted(true)
    waitForGains(transport, gated, "later misses close the gate again")
    transport.setMode(.reference)
    waitForGains(transport, audible, "always-on mode restores the actual drum nodes")
    check(transport.performanceMuted, "switching modes preserves the underlying performance gate")
    check(transport.isRunning && transport.epoch == originalEpoch, "changing the mix neither restarts nor shifts playback")
    transport.setMode(.performance)
    waitForGains(transport, gated, "returning to performance restores its existing muted gate")
    transport.setMode(.practice)
    transport.setPerformanceMuted(false)
    waitForGains(transport, gated, "a correct hit cannot override explicitly-off recordings")
    transport.setMode(.performance)
    waitForGains(transport, audible, "returning from off to performance uses the current open gate")
    transport.setPerformanceMuted(true)
    Thread.sleep(forTimeInterval: 0.004)
    let intermediate = transport.stemVolumes
    check(intermediate[0] == 1 && intermediate[2] == 1 && intermediate[6] == 1,
      "gain ramps leave all backing nodes unchanged")
    check([1, 3, 4, 5].allSatisfy { intermediate[$0] == intermediate[1] && (0...1).contains(intermediate[$0]) },
      "all numbered drums share a bounded ramp fraction")
    transport.setPerformanceMuted(false)
    waitForGains(transport, audible, "a hit can reverse an in-progress miss ramp")
    Thread.sleep(forTimeInterval: 0.03)
    check(transport.stemVolumes == audible && transport.epoch == originalEpoch,
      "cancelled miss ramps cannot later overwrite restored gains or shift playback")
    transport.setPerformanceMuted(true)
    transport.stop()
    check(!transport.isRunning && transport.stemVolumes.isEmpty, "stop releases the engine and all stem nodes")
    transport.setMode(.reference)
    check(transport.stemVolumes.isEmpty, "changing mode while stopped cannot revive stale nodes")
    try startSilently(transport, prepared, position: 0.5, mode: .performance, performanceMuted: true)
    Thread.sleep(forTimeInterval: 0.03)
    check(transport.stemVolumes == gated, "resume retains the closed performance gate and cancels old-node ramps")
    transport.stop()
    try startSilently(transport, prepared, position: 0.5, mode: .reference, performanceMuted: true)
    check(transport.stemVolumes == audible, "always-on selection survives a stop and resume regardless of the gate")

    for fullAudio in [Optional<DrumxSongPreparedAudio>.none, prepared] {
      let preview = try DrumxSongPreparedAudio.preparePreview(fixture, fullAudio: fullAudio)
      check(preview.audio.stems == stems, "direct and reused previews preserve original manifest stem identities")
      check(preview.playbackStart == 0.25 && abs(preview.duration - 0.65) < 0.00001,
        "stem metadata does not alter the authored preview excerpt")
      try startSilently(transport, preview.audio, position: preview.playbackStart, mode: .reference, performanceMuted: true)
      check(transport.stemVolumes == audible, "reference previews include every instrument even if performance was muted")
    }

    let combined = try DrumxSongPreparedAudio.prepare(song(stems: ["song", "drums"], files: Array(files.prefix(2))))
    try startSilently(transport, combined)
    check(transport.stemVolumes == [1, 1], "combined drum recordings start audible")
    transport.setPerformanceMuted(true)
    waitForGains(transport, [1, 0], "combined drum recordings follow the same gate as numbered recordings")
    for name in ["song", "guitar"] {
      let mixed = try DrumxSongPreparedAudio.prepare(song(stems: [name], files: [files[0]]))
      try startSilently(transport, mixed, performanceMuted: true)
      check(transport.stemVolumes == [1], "a single mixed recording stays audible even with a misleading filename")
    }
    let drumsOnly = try DrumxSongPreparedAudio.prepare(song(stems: ["drums"], files: [files[1]]))
    try startSilently(transport, drumsOnly, mode: .practice)
    check(transport.stemVolumes == [0], "a drum-only recording keeps a running silent timeline in practice")

    for invalidStems in [Array(stems.dropLast()), stems + ["drums"]] {
      let invalid = DrumxSongPreparedAudio(files: prepared.files, duration: prepared.duration, stems: invalidStems)
      do {
        try transport.start(invalid, position: 0, audioLead: 0, countdown: silentCountdown)
        check(false, "mismatched file metadata must be rejected")
      } catch {
        check(error.localizedDescription.contains("stem metadata"), "mismatched metadata reports a specific recovery error")
      }
      check(!transport.isRunning && transport.stemVolumes.isEmpty, "rejected metadata leaves no prior playback or stale nodes")
    }
    print("\(checks) song stem transport checks passed with real AVAudioPlayerNode gains; no audio played.")
  }
}
