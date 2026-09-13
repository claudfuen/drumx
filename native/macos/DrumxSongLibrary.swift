import Foundation
import AVFoundation
import Darwin

private extension CodingUserInfoKey {
  static let drumxSongSummary = CodingUserInfoKey(rawValue: "drumxSongSummary")!
}

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
  let noteCount: Int
  let instrumentCount: Int?
  let intensity: DrumxSongIntensity?

  private enum CodingKeys: String, CodingKey { case difficulty, notes, noteCount, instrumentCount, intensity }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    difficulty = try values.decode(String.self, forKey: .difficulty)
    intensity = try? values.decode(DrumxSongIntensity.self, forKey: .intensity)
    if decoder.userInfo[.drumxSongSummary] as? Bool == true {
      notes = []
      if let count = try values.decodeIfPresent(Int.self, forKey: .noteCount) {
        noteCount = count
      } else if values.contains(.notes) {
        // Legacy manifests remain browsable without materializing note structs.
        noteCount = try values.nestedUnkeyedContainer(forKey: .notes).count ?? 0
      } else { noteCount = 0 }
      instrumentCount = try values.decodeIfPresent(Int.self, forKey: .instrumentCount)
    } else {
      notes = try values.decodeIfPresent([DrumxSongNote].self, forKey: .notes) ?? []
      noteCount = notes.count
      instrumentCount = Set(notes.compactMap { $0.pad }).count
    }
  }
}

struct DrumxSongIntensity: Decodable, Equatable {
  let level: Int
  let source: String
  let version: Int
  let metrics: [String: Double]?
  var isCurrent: Bool {
    guard version == 1, (0...6).contains(level), ["authored", "estimated"].contains(source),
      let metrics, metrics.values.allSatisfy({ $0.isFinite }) else { return false }
    return ["noteCount", "activeSeconds", "averageNPS", "peakTwoSecondNPS", "handFootRatio", "demandScore"]
      .allSatisfy { metrics[$0] != nil }
  }
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
  let resolution: Int
  let tempos: [DrumxSongTempo]
  let timeSignatures: [DrumxSongTimeSignature]
  let audio: [DrumxSongAudio]
  let albumArtPath: String?
  let warnings: [String]
  let previewStartSeconds: Double?
  let previewEndSeconds: Double?
  /// Filled by the library reader, never trusted from imported metadata paths.
  var sourceManifestURL: URL? = nil

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, id, title, artist, album, charter, sourceFormat, durationSeconds,
      difficulties, selectedDifficulty, drumMode, charts, audio, albumArtPath, warnings,
      previewStartSeconds, previewEndSeconds, resolution, tempos, timeSignatures
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    id = try values.decode(String.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    artist = try values.decode(String.self, forKey: .artist)
    album = try values.decodeIfPresent(String.self, forKey: .album)
    charter = try values.decodeIfPresent(String.self, forKey: .charter)
    sourceFormat = try values.decode(String.self, forKey: .sourceFormat)
    durationSeconds = try values.decode(Double.self, forKey: .durationSeconds)
    difficulties = try values.decode([String].self, forKey: .difficulties)
    selectedDifficulty = try values.decode(String.self, forKey: .selectedDifficulty)
    drumMode = try values.decode(String.self, forKey: .drumMode)
    charts = try values.decode([DrumxSongChart].self, forKey: .charts)
    resolution = try values.decodeIfPresent(Int.self, forKey: .resolution) ?? 480
    if decoder.userInfo[.drumxSongSummary] as? Bool == true {
      tempos = []; timeSignatures = []
    } else {
      tempos = try values.decodeIfPresent([DrumxSongTempo].self, forKey: .tempos) ?? []
      timeSignatures = try values.decodeIfPresent([DrumxSongTimeSignature].self, forKey: .timeSignatures) ?? []
    }
    audio = try values.decode([DrumxSongAudio].self, forKey: .audio)
    albumArtPath = try values.decodeIfPresent(String.self, forKey: .albumArtPath)
    warnings = try values.decode([String].self, forKey: .warnings)
    previewStartSeconds = try values.decodeIfPresent(Double.self, forKey: .previewStartSeconds)
    previewEndSeconds = try values.decodeIfPresent(Double.self, forKey: .previewEndSeconds)
  }

  func noteCount(for difficulty: String) -> Int {
    charts.first { $0.difficulty == difficulty }?.noteCount ?? 0
  }
  func instrumentCount(for difficulty: String) -> Int? {
    charts.first { $0.difficulty == difficulty }?.instrumentCount
  }
  func intensity(for difficulty: String) -> DrumxSongIntensity? {
    guard let rating = charts.first(where: { $0.difficulty == difficulty })?.intensity,
      rating.isCurrent else { return nil }
    return rating
  }

  func notes(for difficulty: String) -> [DrumxSongNote] {
    (charts.first { $0.difficulty == difficulty }?.notes ?? []).filter {
      $0.pad != nil && $0.timeSeconds.isFinite
    }.sorted {
      $0.timeSeconds == $1.timeSeconds ? $0.pad! < $1.pad! : $0.timeSeconds < $1.timeSeconds
    }
  }
}

struct DrumxSongPreviewRange {
  let start: Double
  let end: Double
  var duration: Double { end - start }

  init?(song: DrumxSong, audioDuration: Double) {
    guard audioDuration.isFinite, audioDuration > 0.2 else { return nil }
    if let authored = song.previewStartSeconds, authored.isFinite,
      authored >= 0, authored < audioDuration - 0.2 { start = authored }
    else { start = audioDuration * 0.4 }
    if let authored = song.previewEndSeconds, authored.isFinite, authored > start,
      authored - start >= 0.2 { end = min(audioDuration, start + 18, authored) }
    else { end = min(audioDuration, start + 18) }
  }
}

final class DrumxSongPreparationCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var process: Process?

  func cancel() {
    lock.lock(); cancelled = true; let current = process; lock.unlock()
    if let current { terminate(current) }
  }
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func attach(_ next: Process) throws {
    lock.lock(); defer { lock.unlock() }
    guard !cancelled else { throw CancellationError() }
    process = next
  }
  func detach(_ previous: Process) {
    lock.lock(); defer { lock.unlock() }
    if process === previous { process = nil }
  }
  func didStart(_ current: Process) { if isCancelled { terminate(current) } }
  private func terminate(_ current: Process) {
    guard current.isRunning else { return }
    current.terminate()
    // Bound cancellation even when a decoder does not cooperate with SIGTERM.
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35) {
      if current.isRunning { Darwin.kill(current.processIdentifier, SIGKILL) }
    }
  }
}

struct DrumxSongPreparedPreview {
  let audio: DrumxSongPreparedAudio
  let playbackStart: Double
  let playbackEnd: Double
  let sourceStart: Double
  var duration: Double { playbackEnd - playbackStart }
}

enum DrumxSongLibrary {
  static let readingQueue = DispatchQueue(label: "org.drumx.song-library-reading", qos: .userInitiated)
  private static let repairQueue = DispatchQueue(label: "org.drumx.song-index-repair", qos: .utility)
  private static let repairLock = NSLock()
  private static var repairAttempted = false
  static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Drumx/Songs", isDirectory: true)
  }
  static var registeredDirectories: [URL] {
    (UserDefaults.standard.stringArray(forKey: "drumx.songs.directories") ?? []).map { URL(fileURLWithPath: $0) }
  }
  static func registerDirectory(_ url: URL) {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    var paths = registeredDirectories.map { $0.path }
    if !paths.contains(path) { paths.append(path) }
    UserDefaults.standard.set(paths, forKey: "drumx.songs.directories")
  }
  static func repairIndexIfNeeded(_ songs: [DrumxSong], completion: @escaping (Result<Int, Error>) -> Void) {
    guard songs.contains(where: { song in song.difficulties.contains { song.intensity(for: $0) == nil } }) else { return }
    repairLock.lock()
    let shouldRepair = !repairAttempted
    repairAttempted = true
    repairLock.unlock()
    guard shouldRepair else { return }
    repairQueue.async {
      let result = Result { () throws -> Int in
        guard let script = importerURL(), let python = executable("python3") else {
          throw DrumxSongError.message("The song index repair needs its importer and Python 3.")
        }
        let output = try run(python, arguments: [script.path, "--rebuild-index", "--library", root.path])
        guard let data = output.data(using: .utf8),
          let report = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return report["updated"] as? Int ?? 0
      }
      DispatchQueue.main.async { completion(result) }
    }
  }

  static func read(at directory: URL? = nil) -> (songs: [DrumxSong], errors: [String]) {
    let folders = (try? FileManager.default.contentsOfDirectory(at: directory ?? root,
      includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    var songs: [DrumxSong] = [], errors: [String] = []
    for folder in folders {
      let manifest = folder.appendingPathComponent("song.json")
      guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
      do {
        let info = folder.appendingPathComponent("song-info.json")
        let song: DrumxSong
        if FileManager.default.fileExists(atPath: info.path),
          let summary = try? readSummary(info, manifest: manifest) {
          song = summary
        } else {
          song = try readSummary(manifest, manifest: manifest)
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

  private static func readSummary(_ url: URL, manifest: URL) throws -> DrumxSong {
    let decoder = JSONDecoder(); decoder.userInfo[.drumxSongSummary] = true
    var song = try decoder.decode(DrumxSong.self, from: Data(contentsOf: url))
    try validateMetadata(song)
    song.sourceManifestURL = manifest
    return song
  }

  private static func validateMetadata(_ song: DrumxSong) throws {
    let available = Set(song.charts.filter { $0.noteCount > 0 }.map { $0.difficulty })
    guard song.schemaVersion == 1, !song.id.isEmpty,
      song.durationSeconds.isFinite, song.durationSeconds > 0,
      !song.difficulties.isEmpty, Set(song.difficulties).isSubset(of: available),
      song.charts.allSatisfy({ $0.noteCount >= 0 && ($0.instrumentCount.map { (0...8).contains($0) } ?? true) })
    else { throw DrumxSongError.message("Unsupported or empty song metadata") }
  }

  /// Call off the main thread only when playing. A library of thousands of songs
  /// retains metadata; only the selected song materializes its full drum charts.
  static func loadFull(_ summary: DrumxSong) throws -> DrumxSong {
    guard let manifest = summary.sourceManifestURL else {
      throw DrumxSongError.message("This song has no chart manifest. Add its song directory again.")
    }
    var song = try JSONDecoder().decode(DrumxSong.self, from: Data(contentsOf: manifest))
    try validateMetadata(song)
    guard song.id == summary.id, Set(summary.difficulties).isSubset(of: Set(song.difficulties)),
      song.charts.allSatisfy({ chart in chart.notes.allSatisfy {
        $0.pad != nil && $0.timeSeconds.isFinite && $0.durationSeconds.isFinite
          && $0.durationSeconds >= 0 && (1...127).contains($0.velocity)
      } }) else {
      throw DrumxSongError.message("The song's drum charts are missing or inconsistent. Add its directory again to refresh them.")
    }
    song.sourceManifestURL = manifest
    return song
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
  static func run(_ executable: URL, arguments: [String],
                  cancellation: DrumxSongPreparationCancellation? = nil,
                  timeout: TimeInterval? = nil) throws -> String {
    let process = Process(), pipe = Pipe(), deadline = DrumxSongPreparationCancellation()
    process.executableURL = executable; process.arguments = arguments
    process.standardOutput = pipe; process.standardError = pipe
    try cancellation?.attach(process); try deadline.attach(process)
    defer { cancellation?.detach(process); deadline.detach(process) }
    try process.run()
    cancellation?.didStart(process)
    let timeoutWork = DispatchWorkItem { deadline.cancel() }
    if let timeout { DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork) }
    defer { timeoutWork.cancel() }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if cancellation?.isCancelled == true { throw CancellationError() }
    if deadline.isCancelled { throw DrumxSongError.message("Audio preparation timed out. Try this song again.") }
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
    if scan { arguments.append(contentsOf: ["--scan", "--reference"]) }
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
  let stems: [String]

  init(files: [AVAudioFile], duration: Double, stems: [String]? = nil) {
    self.files = files; self.duration = duration
    self.stems = stems ?? Array(repeating: "", count: files.count)
  }

  private struct PreviewSource: Codable, Equatable {
    let path: String
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(path: String) throws {
      var info = stat()
      guard stat(path, &info) == 0 else {
        throw DrumxSongError.message("Missing audio: \(URL(fileURLWithPath: path).lastPathComponent). Refresh its song directory.")
      }
      self.path = path; size = Int64(info.st_size)
      modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
      modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
      changedSeconds = Int64(info.st_ctimespec.tv_sec)
      changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }
  }

  private struct PreviewSourceInfo: Codable {
    let version: Int
    let sources: [PreviewSource]
    let duration: Double
    let cacheKey: String

    func matches(_ current: [PreviewSource]) -> Bool {
      version == 1 && sources == current && duration.isFinite && duration > 0
        && UUID(uuidString: cacheKey) != nil
    }
  }

  /// Browsing decodes only the audible excerpt, never every complete song that
  /// the selection passes over. Full WAV caches and native formats are reused.
  static func preparePreview(_ song: DrumxSong, fullAudio: DrumxSongPreparedAudio? = nil,
                             cancellation: DrumxSongPreparationCancellation? = nil) throws -> DrumxSongPreparedPreview {
    func cancelled() throws {
      if cancellation?.isCancelled == true { throw CancellationError() }
    }
    try cancelled()
    guard !song.audio.isEmpty else { throw DrumxSongError.message("This chart has no preview audio.") }
    var readable = fullAudio?.files ?? []
    if fullAudio == nil {
      for (index, stem) in song.audio.enumerated() {
        let original = URL(fileURLWithPath: stem.path)
        if let direct = try? AVAudioFile(forReading: original) { readable.append(direct); continue }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: original.path) {
          let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
          let modified = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
          let cached = DrumxSongLibrary.root.appendingPathComponent(song.id)
            .appendingPathComponent("audio-cache/\(index)-\(size)-\(modified).wav")
          if let file = try? AVAudioFile(forReading: cached) { readable.append(file) }
        }
      }
    }
    if readable.count == song.audio.count {
      let audio = fullAudio ?? DrumxSongPreparedAudio(files: readable,
        duration: readable.map { Double($0.length) / $0.processingFormat.sampleRate }.max() ?? 0,
        stems: song.audio.map(\.stem))
      guard let range = DrumxSongPreviewRange(song: song, audioDuration: audio.duration) else {
        throw DrumxSongError.message("This audio is too short to preview.")
      }
      return DrumxSongPreparedPreview(audio: audio, playbackStart: range.start,
        playbackEnd: range.end, sourceStart: range.start)
    }
    guard let ffmpeg = DrumxSongLibrary.executable("ffmpeg") else {
      throw DrumxSongError.message("This audio needs FFmpeg for preview. Install it with brew install ffmpeg.")
    }
    let cache = DrumxSongLibrary.root.appendingPathComponent(song.id).appendingPathComponent("preview-cache")
    let sourceInfoURL = cache.appendingPathComponent("source-info.json")
    let sources = try song.audio.map { try PreviewSource(path: $0.path) }
    let savedInfo = (try? Data(contentsOf: sourceInfoURL)).flatMap { try? JSONDecoder().decode(PreviewSourceInfo.self, from: $0) }
    var duration = song.durationSeconds
    let sourceInfo: PreviewSourceInfo
    if let savedInfo, savedInfo.matches(sources) {
      // A warm selection performs only file stat and cached WAV reads. Verified
      // duration is retained until source bytes may have changed; no ffprobe.
      duration = savedInfo.duration
      sourceInfo = savedInfo
    } else {
      if let ffprobe = DrumxSongLibrary.executable("ffprobe") {
      var durations: [Double] = []
      for stem in song.audio {
        try cancelled()
        let value = try DrumxSongLibrary.run(ffprobe, arguments: ["-v", "error", "-show_entries",
          "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", stem.path], cancellation: cancellation, timeout: 8)
        if let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), seconds.isFinite, seconds > 0 {
          durations.append(seconds)
        }
      }
      if let actual = durations.max() { duration = actual }
      }
      sourceInfo = PreviewSourceInfo(version: 1, sources: sources, duration: duration, cacheKey: UUID().uuidString)
      try cancelled()
      try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
      try JSONEncoder().encode(sourceInfo).write(to: sourceInfoURL, options: .atomic)
    }
    guard let range = DrumxSongPreviewRange(song: song, audioDuration: duration) else {
      throw DrumxSongError.message("This audio is too short to preview.")
    }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    var files: [AVAudioFile] = []
    var stems: [String] = []
    for (index, stem) in song.audio.enumerated() {
      try cancelled()
      let original = URL(fileURLWithPath: stem.path)
      let cached = cache.appendingPathComponent("\(sourceInfo.cacheKey)-\(index)-\(Int(range.start * 1000))-\(Int(range.duration * 1000)).wav")
      if !FileManager.default.fileExists(atPath: cached.path) {
        let temporary = cache.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try DrumxSongLibrary.run(ffmpeg, arguments: ["-nostdin", "-v", "error", "-ss", String(range.start),
          "-i", original.path, "-t", String(range.duration), "-vn", "-ac", "2", "-ar", "48000",
          "-c:a", "pcm_s16le", temporary.path], cancellation: cancellation, timeout: 15)
        if !FileManager.default.fileExists(atPath: cached.path) {
          try FileManager.default.moveItem(at: temporary, to: cached)
        }
      }
      let file = try AVAudioFile(forReading: cached)
      if file.length > 0 { files.append(file); stems.append(stem.stem) }
    }
    try cancelled()
    let clipDuration = files.map { Double($0.length) / $0.processingFormat.sampleRate }.max() ?? 0
    guard !files.isEmpty, clipDuration > 0.2 else { throw DrumxSongError.message("This song's preview contains no audio.") }
    return DrumxSongPreparedPreview(audio: DrumxSongPreparedAudio(files: files, duration: clipDuration, stems: stems),
      playbackStart: 0, playbackEnd: min(range.duration, clipDuration), sourceStart: range.start)
  }

  /// Native AVFoundation formats are used directly. Ogg Vorbis and Opus stems
  /// are decoded once into a private WAV cache, never added to the repository.
  static func prepare(_ song: DrumxSong, cancellation: DrumxSongPreparationCancellation? = nil) throws -> DrumxSongPreparedAudio {
    guard !song.audio.isEmpty else {
      throw DrumxSongError.message("This chart has no audio. Import its complete song folder, including the song or instrument stems.")
    }
    var files: [AVAudioFile] = []
    for (index, stem) in song.audio.enumerated() {
      if cancellation?.isCancelled == true { throw CancellationError() }
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
          "-vn", "-ac", "2", "-ar", "48000", "-c:a", "pcm_s16le", temporary.path], cancellation: cancellation, timeout: 90)
        if !FileManager.default.fileExists(atPath: cached.path) {
          try FileManager.default.moveItem(at: temporary, to: cached)
        }
      }
      files.append(try AVAudioFile(forReading: cached))
    }
    if cancellation?.isCancelled == true { throw CancellationError() }
    return DrumxSongPreparedAudio(files: files,
      duration: files.map { Double($0.length) / $0.processingFormat.sampleRate }.max() ?? 0,
      stems: song.audio.map(\.stem))
  }
}

/// One host-clock epoch drives every stem and scoring. Drawing only reads time.
/// Reported output latency is an estimate, not a measured physical calibration.
final class DrumxSongAudioTransport {
  private var engine: AVAudioEngine?
  private var nodes: [AVAudioPlayerNode] = []
  private var stems: [String] = []
  private var observer: NSObjectProtocol?
  private let gainQueue = DispatchQueue(label: "org.drumx.song-stem-gains", qos: .userInteractive)
  private let gainQueueKey = DispatchSpecificKey<Bool>()
  private var gainRamp: DispatchSourceTimer?
  private var gainRevision = 0
  private(set) var mode: DrumxSongAudioMode = .performance
  private(set) var performanceMuted = false
  private(set) var epoch: Double = 0
  private(set) var outputLatency: Double = 0
  var onInterrupted: ((String) -> Void)?
  var isRunning: Bool { engine?.isRunning == true }
  var stemVolumes: [Float] { onGainQueue { nodes.map(\.volume) } }
  func setVolume(_ value: Float) { engine?.mainMixerNode.outputVolume = min(1, max(0, value)) }

  init() { gainQueue.setSpecific(key: gainQueueKey, value: true) }

  private func onGainQueue<T>(_ action: () -> T) -> T {
    DispatchQueue.getSpecific(key: gainQueueKey) == true ? action() : gainQueue.sync(execute: action)
  }

  func setMode(_ mode: DrumxSongAudioMode) {
    guard self.mode != mode else { return }
    self.mode = mode
    updateStemGains()
  }

  func setPerformanceMuted(_ muted: Bool) {
    guard performanceMuted != muted else { return }
    performanceMuted = muted
    updateStemGains()
  }

  private func updateStemGains() {
    let targets = DrumxSongStemMix(stems: stems, mode: mode, performanceMuted: performanceMuted).gains
    let activeNodes = nodes
    onGainQueue {
      cancelGainRampOnQueue()
      guard !activeNodes.isEmpty else { return }
      let starts = activeNodes.map(\.volume)
      guard starts != targets else { return }
      let revision = gainRevision
      let started = DispatchTime.now().uptimeNanoseconds
      let timer = DispatchSource.makeTimerSource(queue: gainQueue)
      timer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(250))
      timer.setEventHandler { [weak self] in
        guard let self, self.gainRevision == revision else { return }
        // Twelve milliseconds avoids an abrupt waveform discontinuity. Every
        // drum stem uses the same ramp fraction; scheduling and epoch stay put.
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let fraction = min(1, Float(elapsed) / 12_000_000)
        for index in activeNodes.indices {
          activeNodes[index].volume = fraction == 1 ? targets[index]
            : starts[index] + (targets[index] - starts[index]) * fraction
        }
        if fraction == 1 { self.cancelGainRampOnQueue() }
      }
      gainRamp = timer
      timer.resume()
    }
  }

  /// Called only on gainQueue. Its revision also invalidates already-enqueued
  /// timer callbacks when a hit reverses a miss ramp or playback stops.
  private func cancelGainRampOnQueue() {
    gainRevision += 1
    gainRamp?.cancel(); gainRamp = nil
  }

  func start(_ prepared: DrumxSongPreparedAudio, position: Double,
             audioLead: Double, countdown: Double, mode: DrumxSongAudioMode = .performance,
             performanceMuted: Bool = false) throws {
    stop()
    guard prepared.stems.count == prepared.files.count else {
      throw DrumxSongError.message("The song's audio files do not match their stem metadata. Reimport the song.")
    }
    stems = prepared.stems
    self.mode = mode; self.performanceMuted = performanceMuted
    let mix = DrumxSongStemMix(stems: stems, mode: mode, performanceMuted: performanceMuted)
    let next = AVAudioEngine()
    for (index, file) in prepared.files.enumerated() {
      let node = AVAudioPlayerNode()
      node.volume = mix.gains[index]
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
    onGainQueue { cancelGainRampOnQueue() }
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    nodes.forEach { $0.stop() }; nodes.removeAll()
    stems.removeAll()
    engine?.stop(); engine = nil
  }

  deinit { stop() }
}
