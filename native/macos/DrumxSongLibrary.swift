import Foundation
import AVFoundation

struct DrumxSongNote: Decodable {
  let timeSeconds: Double
  let durationSeconds: Double
  let lane: String
  let velocity: Int

  var pad: Int? {
    ["hihat": 0, "snare": 1, "kick": 2, "tom1": 3, "tom2": 4,
     "tom3": 5, "crash": 6, "ride": 7][lane]
  }
}

struct DrumxSongChart: Decodable {
  let difficulty: String
  let notes: [DrumxSongNote]
}

struct DrumxSongAudio: Decodable {
  let stem: String
  let path: String
}

struct DrumxSongVisualNote {
  let time: Double
  let pad: Int
}

struct DrumxSongChartTiming {
  let lead: Double
  let duration: Double
  let notes: [DrumxSongVisualNote]

  init(song: DrumxSong, difficulty: String, audioDuration: Double) {
    let selected = song.notes(for: difficulty)
    let lead = max(0, -(selected.first?.timeSeconds ?? 0))
    self.lead = lead
    duration = max(song.durationSeconds, audioDuration,
      (selected.last?.timeSeconds ?? 0) + 2) + lead
    notes = selected.map { DrumxSongVisualNote(time: $0.timeSeconds + lead, pad: $0.pad!) }
  }
}

/// Captured input is mapped using the segment in which it actually occurred.
/// Paused strikes cannot score, while delayed pre-pause MIDI still can.
struct DrumxSongClock {
  private struct Segment {
    let epoch: Double
    let start: Double
    var end: Double?
  }
  private var segments: [Segment] = []

  mutating func begin(epoch: Double, at hostTime: Double) {
    stop(at: hostTime)
    segments.append(Segment(epoch: epoch, start: hostTime, end: nil))
  }
  mutating func stop(at hostTime: Double) {
    guard let index = segments.indices.last, segments[index].end == nil else { return }
    segments[index].end = hostTime
  }
  func songTime(capturedAt hostTime: Double, offsetMS: Double) -> Double? {
    guard hostTime.isFinite, offsetMS.isFinite,
      let segment = segments.last(where: { hostTime >= $0.start && hostTime <= ($0.end ?? .infinity) })
    else { return nil }
    return hostTime - segment.epoch - offsetMS / 1000
  }
}

struct DrumxSong: Decodable {
  let schemaVersion: Int
  let id: String
  let title: String
  let artist: String
  let album: String?
  let charter: String?
  let sourceFormat: String
  let durationSeconds: Double
  let difficulties: [String]
  let selectedDifficulty: String
  let drumMode: String
  let charts: [DrumxSongChart]
  let audio: [DrumxSongAudio]
  let albumArtPath: String?
  let warnings: [String]

  func notes(for difficulty: String) -> [DrumxSongNote] {
    (charts.first { $0.difficulty == difficulty }?.notes ?? []).filter {
      $0.pad != nil && $0.timeSeconds.isFinite
    }.sorted {
      $0.timeSeconds == $1.timeSeconds ? $0.pad! < $1.pad! : $0.timeSeconds < $1.timeSeconds
    }
  }
}

enum DrumxSongLibrary {
  static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Drumx/Songs", isDirectory: true)
  }

  static func read() -> (songs: [DrumxSong], errors: [String]) {
    let folders = (try? FileManager.default.contentsOfDirectory(at: root,
      includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    var songs: [DrumxSong] = [], errors: [String] = []
    for folder in folders {
      let manifest = folder.appendingPathComponent("song.json")
      guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
      do {
        let song = try JSONDecoder().decode(DrumxSong.self, from: Data(contentsOf: manifest))
        guard song.schemaVersion == 1, song.durationSeconds.isFinite,
              song.durationSeconds > 0, !song.charts.isEmpty else {
          throw DrumxSongError.message("Unsupported or empty song manifest")
        }
        songs.append(song)
      } catch { errors.append("\(folder.lastPathComponent): \(error.localizedDescription)") }
    }
    return (songs.sorted {
      $0.artist.localizedStandardCompare($1.artist) == .orderedSame
        ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
        : $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
    }, errors)
  }

  static func executable(_ name: String) -> URL? {
    let paths = [Bundle.main.resourceURL?.appendingPathComponent(name).path,
      "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
      .compactMap { $0 }
    return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
      .map { URL(fileURLWithPath: $0) }
  }

  static func importerURL() -> URL? {
    let candidates = [Bundle.main.resourceURL?.appendingPathComponent("import_song.py"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts/import_song.py")].compactMap { $0 }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
  }

  /// Process output is drained while the subprocess runs, including a directory
  /// import containing many songs. A full pipe must never stall the import.
  static func run(_ executable: URL, arguments: [String]) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = executable; process.arguments = arguments
    process.standardOutput = pipe; process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw DrumxSongError.message(String(output.suffix(1800)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return output
  }

  static func importSource(_ url: URL, scan: Bool) throws -> String {
    guard let script = importerURL(), let python = executable("python3") else {
      throw DrumxSongError.message("The song importer needs Python 3. Rebuild Drumx with its importer resource, then install Python 3 if needed.")
    }
    var arguments = [script.path, url.path, "--library", root.path]
    if scan { arguments.append("--scan") }
    let output = try run(python, arguments: arguments)
    guard scan, let data = output.data(using: .utf8),
      let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "Song imported." }
    let imported = (report["imported"] as? [String])?.count ?? 0
    let errors = report["errors"] as? [[String: String]] ?? []
    let duplicates = (report["skipped"] as? [[String: String]])?.count ?? 0
    var message = "Directory scan complete. \(imported) songs imported"
    if duplicates > 0 { message += ", \(duplicates) duplicates skipped" }
    if !errors.isEmpty {
      message += ", \(errors.count) could not import. "
      message += errors.prefix(2).map { item in
        "\(URL(fileURLWithPath: item["path"] ?? "Song").lastPathComponent): \(item["error"] ?? "unsupported chart")"
      }.joined(separator: " ")
    } else { message += "." }
    return message
  }
}

enum DrumxSongError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let text) = self { return text.isEmpty ? "The song could not be loaded." : text }
    return nil
  }
}

struct DrumxSongPreparedAudio {
  static let preparationQueue = DispatchQueue(label: "org.drumx.song-audio-preparation", qos: .userInitiated)
  let files: [AVAudioFile]
  let duration: Double

  /// Native AVFoundation formats are used directly. Ogg Vorbis and Opus stems
  /// are decoded once into a private WAV cache, never added to the repository.
  static func prepare(_ song: DrumxSong) throws -> DrumxSongPreparedAudio {
    guard !song.audio.isEmpty else {
      throw DrumxSongError.message("This chart has no audio. Import its complete song folder, including the song or instrument stems.")
    }
    var files: [AVAudioFile] = []
    for (index, stem) in song.audio.enumerated() {
      let original = URL(fileURLWithPath: stem.path)
      guard FileManager.default.fileExists(atPath: original.path) else {
        throw DrumxSongError.message("Missing audio: \(original.lastPathComponent). Reimport the complete song folder.")
      }
      if let direct = try? AVAudioFile(forReading: original) {
        files.append(direct); continue
      }
      guard let ffmpeg = DrumxSongLibrary.executable("ffmpeg") else {
        throw DrumxSongError.message("\(original.pathExtension.uppercased()) audio needs FFmpeg. Install it with Homebrew (brew install ffmpeg), then play this song again.")
      }
      let cache = DrumxSongLibrary.root.appendingPathComponent(song.id, isDirectory: true)
        .appendingPathComponent("audio-cache", isDirectory: true)
      try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
      let attributes = try FileManager.default.attributesOfItem(atPath: original.path)
      let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
      let modified = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
      let cached = cache.appendingPathComponent("\(index)-\(size)-\(modified).wav")
      if !FileManager.default.fileExists(atPath: cached.path) {
        let temporary = cache.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try DrumxSongLibrary.run(ffmpeg, arguments: ["-nostdin", "-v", "error", "-i", original.path,
          "-vn", "-ac", "2", "-ar", "48000", "-c:a", "pcm_s16le", temporary.path])
        if !FileManager.default.fileExists(atPath: cached.path) {
          try FileManager.default.moveItem(at: temporary, to: cached)
        }
      }
      files.append(try AVAudioFile(forReading: cached))
    }
    return DrumxSongPreparedAudio(files: files,
      duration: files.map { Double($0.length) / $0.processingFormat.sampleRate }.max() ?? 0)
  }
}

/// One host-clock epoch drives every stem and scoring. Drawing only reads time.
/// Reported output latency is an estimate, not a measured physical calibration.
final class DrumxSongAudioTransport {
  private var engine: AVAudioEngine?
  private var nodes: [AVAudioPlayerNode] = []
  private var observer: NSObjectProtocol?
  private(set) var epoch: Double = 0
  private(set) var outputLatency: Double = 0
  var onInterrupted: ((String) -> Void)?
  var isRunning: Bool { engine?.isRunning == true }

  func start(_ prepared: DrumxSongPreparedAudio, position: Double,
             audioLead: Double, countdown: Double) throws {
    stop()
    let next = AVAudioEngine()
    for file in prepared.files {
      let node = AVAudioPlayerNode()
      next.attach(node); next.connect(node, to: next.mainMixerNode, format: file.processingFormat)
      let frame = min(file.length, AVAudioFramePosition(max(0, position - audioLead) * file.processingFormat.sampleRate))
      if frame < file.length {
        guard file.length - frame <= Int64(UInt32.max) else {
          throw DrumxSongError.message("This audio file is too long for the song player.")
        }
        node.scheduleSegment(file, startingFrame: frame,
          frameCount: AVAudioFrameCount(file.length - frame), at: nil)
      }
      nodes.append(node)
    }
    next.mainMixerNode.outputVolume = 0.8
    next.prepare(); try next.start()
    let output = next.outputNode
    outputLatency = max(0, output.presentationLatency + output.latency + next.mainMixerNode.latency)
    let firstPresentation = DrumxIO.hostNowSeconds() + max(countdown, outputLatency + 0.1)
    epoch = firstPresentation - position
    let renderTime = firstPresentation + max(0, audioLead - position) - outputLatency
    let time = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: renderTime))
    for node in nodes { node.play(at: time) }
    engine = next
    observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
      object: next, queue: .main) { [weak self] _ in
        self?.onInterrupted?("Audio output changed. Resume when your headphones or speakers are ready.")
      }
  }

  func stop() {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    nodes.forEach { $0.stop() }; nodes.removeAll()
    engine?.stop(); engine = nil
  }

  deinit { stop() }
}
