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
                            position: Double = 0, mode: DrumxSongAudioMode = .practice) throws {
    try transport.start(audio, position: position, audioLead: 0, countdown: silentCountdown, mode: mode)
    transport.setVolume(0)
    check(transport.isRunning, "the real AVAudioEngine starts")
    check(transport.epoch + position > DrumxIO.hostNowSeconds() + 3500,
      "all scheduled audio remains far in the future")
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
    check(transport.stemVolumes == [1, 0, 1, 0, 0, 0, 1],
      "actual player nodes suppress all numbered drums while preserving backing without any hits")
    transport.setMode(.reference)
    check(transport.stemVolumes == [1, 1, 1, 1, 1, 1, 1], "live reference mode restores the actual drum nodes")
    check(transport.isRunning && transport.epoch == originalEpoch, "changing the mix neither restarts nor shifts playback")
    transport.setMode(.practice)
    check(transport.stemVolumes == [1, 0, 1, 0, 0, 0, 1] && transport.epoch == originalEpoch,
      "returning to practice preserves timeline and backing node gains")
    transport.stop()
    check(!transport.isRunning && transport.stemVolumes.isEmpty, "stop releases the engine and all stem nodes")
    transport.setMode(.reference)
    check(transport.stemVolumes.isEmpty, "changing mode while stopped cannot revive stale nodes")
    try startSilently(transport, prepared, position: 0.5, mode: .practice)
    check(transport.stemVolumes == [1, 0, 1, 0, 0, 0, 1], "resume rebuilds nodes with recorded drums still off")
    transport.stop()
    try startSilently(transport, prepared, position: 0.5, mode: .reference)
    check(transport.stemVolumes == [1, 1, 1, 1, 1, 1, 1], "reference selection survives a stop and resume")

    for fullAudio in [Optional<DrumxSongPreparedAudio>.none, prepared] {
      let preview = try DrumxSongPreparedAudio.preparePreview(fixture, fullAudio: fullAudio)
      check(preview.audio.stems == stems, "direct and reused previews preserve original manifest stem identities")
      check(preview.playbackStart == 0.25 && abs(preview.duration - 0.65) < 0.00001,
        "stem metadata does not alter the authored preview excerpt")
      try startSilently(transport, preview.audio, position: preview.playbackStart, mode: .reference)
      check(transport.stemVolumes == [1, 1, 1, 1, 1, 1, 1], "reference previews include every recorded instrument")
    }

    let combined = try DrumxSongPreparedAudio.prepare(song(stems: ["song", "drums"], files: Array(files.prefix(2))))
    try startSilently(transport, combined)
    check(transport.stemVolumes == [1, 0], "combined drum recordings are muted as well as numbered recordings")
    for name in ["song", "guitar"] {
      let mixed = try DrumxSongPreparedAudio.prepare(song(stems: [name], files: [files[0]]))
      try startSilently(transport, mixed)
      check(transport.stemVolumes == [1], "a single mixed recording stays audible even with a misleading filename")
    }
    let drumsOnly = try DrumxSongPreparedAudio.prepare(song(stems: ["drums"], files: [files[1]]))
    try startSilently(transport, drumsOnly)
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
