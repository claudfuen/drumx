import Foundation

@main
struct DrumxSongChecks {
  static var checks = 0

  static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("Song check failed: \(message)") }
  }

  static func replay(_ song: DrumxSong, difficulty: String) {
    let timing = DrumxSongChartTiming(song: song, difficulty: difficulty, audioDuration: 0)
    guard let core = dx_core_create() else { fatalError("core allocation failed") }
    defer { dx_core_destroy(core) }
    var events = timing.notes.map { DXSongEvent(pad: Int32($0.pad), time_seconds: $0.time) }
    let loaded = events.withUnsafeMutableBufferPointer {
      dx_core_load_song(core, timing.duration, $0.baseAddress, Int32($0.count))
    }
    check(loaded == 1, "\(song.title) \(difficulty) loads all notes")
    check(dx_core_event_count(core) == Int32(events.count), "no notes dropped")
    for event in events {
      let hit = dx_core_input(core, event.pad, event.time_seconds, 0.8)
      check(hit.judgment == Int32(DX_CENTERED.rawValue), "exact captured note matches, pad\(event.pad)")
    }
    dx_core_advance(core, timing.duration + 1)
    var snapshot = DXSnapshot(); dx_core_snapshot(core, &snapshot)
    check(snapshot.finished == 1, "full duration ends")
    check(snapshot.total.matched == Int32(events.count), "all difficulties retain every drum target")
    check(snapshot.total.missed == 0 && snapshot.total.extra == 0, "perfect replay is clean")
    check(abs(snapshot.total.hit_rate_percent - 100) < 0.0001, "perfect replay has100 percent hit rate")
    check(abs(snapshot.total.timing_accuracy_percent - 100) < 0.0001, "perfect replay has100 percent timing")
    let reloaded = events.withUnsafeMutableBufferPointer {
      dx_core_load_song(core, timing.duration, $0.baseAddress, Int32($0.count))
    }
    check(reloaded == 1, "restart resets full chart")
    dx_core_advance(core, timing.duration + 1); dx_core_snapshot(core, &snapshot)
    check(snapshot.total.missed == Int32(events.count), "silent replay records all misses")
  }

  static func main() throws {
    var clock = DrumxSongClock()
    clock.begin(epoch: 102, at: 101.875)
    check(clock.songTime(capturedAt: 100, offsetMS: 0) == nil, "initial count-in cannot score")
    check(clock.songTime(capturedAt: 101.9, offsetMS: 0)! < 0, "ordinary initial early window is retained")
    check(abs(clock.songTime(capturedAt: 103.020, offsetMS: 20)! - 1) < 0.000001, "calibration uses captured time")
    clock.stop(at: 112)
    check(clock.songTime(capturedAt: 112.01, offsetMS: 0) == nil, "paused strike cannot score")
    clock.begin(epoch: 190.4, at: 200.4)
    check(clock.songTime(capturedAt: 200.2, offsetMS: 0) == nil, "resume countdown cannot amend prior notes")
    check(abs(clock.songTime(capturedAt: 200.5, offsetMS: 0)! - 10.1) < 0.000001, "resume continues chart position")
    check(abs(clock.songTime(capturedAt: 111.95, offsetMS: 0)! - 9.95) < 0.000001, "delayed pre-pause MIDI retains original epoch")
    clock.stop(at: 205)
    check(clock.songTime(capturedAt: 205.01, offsetMS: 0) == nil, "second pause closes its segment")
    check(clock.songTime(capturedAt: .nan, offsetMS: 0) == nil, "invalid captures rejected")
    check(clock.songTime(capturedAt: 203, offsetMS: .infinity) == nil, "invalid calibration rejected")

    let lanes = ["hihat", "snare", "kick", "tom1", "tom2", "tom3", "crash", "ride"]
    let noteObjects: [[String: Any]] = lanes.enumerated().map { index, lane in
      ["timeSeconds": Double(index) * 0.5 - 0.75, "durationSeconds": 0, "lane": lane, "velocity": 100]
    }
    let object: [String: Any] = ["schemaVersion": 1, "id": "timing-fixture", "title": "Timing fixture",
      "artist": "Drumx", "sourceFormat": "chart", "durationSeconds": 7.0,
      "difficulties": ["easy", "medium", "hard", "expert"], "selectedDifficulty": "expert",
      "resolution": 480, "tempos": [["tick": 0, "timeSeconds": -0.75, "bpm": 120]],
      "timeSignatures": [["tick": 0, "numerator": 4, "denominator": 4]],
      "drumMode": "pro", "charts": ["easy", "medium", "hard", "expert"].map {
        ["difficulty": $0, "notes": noteObjects] as [String: Any]
      }, "audio": [], "warnings": []]
    let fixture = try JSONDecoder().decode(DrumxSong.self, from: JSONSerialization.data(withJSONObject: object))
    let timing = DrumxSongChartTiming(song: fixture, difficulty: "expert", audioDuration: 9)
    check(timing.lead == 0.75, "negative chart delay is preserved by a shared shift")
    check(timing.notes[0].time == 0, "first negative-offset target is playable")
    check(timing.duration == 9.75, "audio duration retains entire ending plus chart lead")
    check(Set(timing.notes.map { $0.pad }) == Set(0..<8), "all8 instruments map")
    for difficulty in fixture.difficulties { replay(fixture, difficulty: difficulty) }

    let libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("drumx-song-checks-" + UUID().uuidString)
    let fixtureFolder = libraryRoot.appendingPathComponent("timing-fixture")
    try FileManager.default.createDirectory(at: fixtureFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: libraryRoot) }
    let manifest = fixtureFolder.appendingPathComponent("song.json")
    let info = fixtureFolder.appendingPathComponent("song-info.json")
    let fullData = try JSONSerialization.data(withJSONObject: object)
    var summaryObject = object
    summaryObject["charts"] = fixture.difficulties.map {
      ["difficulty": $0, "noteCount": 8, "instrumentCount": 8] as [String: Any]
    }
    try fullData.write(to: manifest)
    try JSONSerialization.data(withJSONObject: summaryObject).write(to: info)
    let summaryLibrary = DrumxSongLibrary.read(at: libraryRoot)
    check(summaryLibrary.errors.isEmpty && summaryLibrary.songs.count == 1, "lightweight metadata is listed")
    let summary = summaryLibrary.songs[0]
    check(summary.charts.allSatisfy { $0.notes.isEmpty }, "library retains no chart note arrays")
    check(summary.tempos.isEmpty && summary.timeSignatures.isEmpty, "library summaries never retain musical grid maps")
    check(summary.noteCount(for: "expert") == 8, "summary note counts stay accurate")
    check(summary.instrumentCount(for: "expert") == 8, "summary instrument counts stay accurate")
    check(summary.intensity(for: "expert") == nil, "legacy ratings remain honestly pending")
    let ratingMetrics: [String: Double] = ["noteCount": 8, "activeSeconds": 4, "averageNPS": 1,
      "peakTwoSecondNPS": 2, "handFootRatio": 0, "demandScore": 1.2]
    func songWithRating(_ rating: [String: Any]) throws -> DrumxSong {
      var rated = object
      rated["charts"] = [["difficulty": "expert", "notes": noteObjects, "intensity": rating]]
      return try JSONDecoder().decode(DrumxSong.self, from: JSONSerialization.data(withJSONObject: rated))
    }
    let authoredRating: [String: Any] = ["level": 6, "source": "authored", "version": 1, "metrics": ratingMetrics]
    let ratedSong = try songWithRating(authoredRating)
    check(ratedSong.intensity(for: "expert")?.level == 6, "authored six-tier rating is available without calculation")
    check(ratedSong.intensity(for: "expert")?.source == "authored", "authored and estimated provenance is retained")
    for invalid: [String: Any] in [
      ["level": 7, "source": "authored", "version": 1, "metrics": ratingMetrics],
      ["level": 3, "source": "estimated", "version": 0, "metrics": ratingMetrics],
      ["level": 3, "source": "unknown", "version": 1, "metrics": ratingMetrics],
      ["level": 3, "source": "estimated", "version": 1]
    ] {
      let invalidSong = try songWithRating(invalid)
      check(invalidSong.intensity(for: "expert") == nil, "outdated or incomplete ratings remain pending for repair")
    }
    check(summary.sourceManifestURL?.resolvingSymlinksInPath().path == manifest.resolvingSymlinksInPath().path,
      "full manifest location comes from library path")
    let lazyFull = try DrumxSongLibrary.loadFull(summary)
    check(lazyFull.notes(for: "expert").count == 8, "full notes load on demand")
    check(lazyFull.charts.count == 4, "difficulty switching retains all selected song charts")
    check(lazyFull.resolution == 480 && lazyFull.tempos.count == 1 && lazyFull.timeSignatures.count == 1,
      "musical grid metadata loads only with the selected full chart")
    try Data("not chart JSON".utf8).write(to: manifest)
    check(DrumxSongLibrary.read(at: libraryRoot).songs.count == 1, "browsing sidecar never reads full chart content")
    do { _ = try DrumxSongLibrary.loadFull(summary); check(false, "corrupt lazy chart must fail") }
    catch { check(true, "corrupt lazy chart fails safely") }
    var missingCharts = object; missingCharts["charts"] = []
    try JSONSerialization.data(withJSONObject: missingCharts).write(to: manifest)
    do { _ = try DrumxSongLibrary.loadFull(summary); check(false, "missing drum charts must fail") }
    catch { check(true, "missing drum charts fail safely") }
    try fullData.write(to: manifest); try FileManager.default.removeItem(at: info)
    let legacy = DrumxSongLibrary.read(at: libraryRoot)
    check(legacy.songs.count == 1 && legacy.errors.isEmpty, "legacy manifest remains browsable")
    check(legacy.songs[0].charts.allSatisfy { $0.notes.isEmpty }, "legacy metadata reader skips note structs")
    check(legacy.songs[0].tempos.isEmpty && legacy.songs[0].timeSignatures.isEmpty, "legacy browsing skips full tempo and meter arrays")
    check(legacy.songs[0].noteCount(for: "easy") == 8, "legacy note counts need no eager note decode")

    let fallbackPreview = DrumxSongPreviewRange(song: fixture, audioDuration: 100)!
    check(fallbackPreview.start == 40 && fallbackPreview.end == 58, "preview defaults to middle excerpt capped18 seconds")
    var previewObject = object
    previewObject["previewStartSeconds"] = 0; previewObject["previewEndSeconds"] = 9
    var previewSong = try JSONDecoder().decode(DrumxSong.self, from: JSONSerialization.data(withJSONObject: previewObject))
    let authoredPreview = DrumxSongPreviewRange(song: previewSong, audioDuration: 100)!
    check(authoredPreview.start == 0 && authoredPreview.end == 9, "authored preview accepts zero and finite end")
    previewObject["previewStartSeconds"] = 300; previewObject["previewEndSeconds"] = 400
    previewSong = try JSONDecoder().decode(DrumxSong.self, from: JSONSerialization.data(withJSONObject: previewObject))
    let outOfBoundsPreview = DrumxSongPreviewRange(song: previewSong, audioDuration: 100)!
    check(outOfBoundsPreview.start == 40 && outOfBoundsPreview.end == 58, "out-of-bounds preview falls back against actual audio")
    check(DrumxSongPreviewRange(song: previewSong, audioDuration: 0.1) == nil, "too-short audio has no invalid preview")
    check(DrumxSongPreviewRange(song: previewSong, audioDuration: .infinity) == nil, "preview rejects an invalid audio duration")
    let cancelled = DrumxSongPreparationCancellation()
    check(!cancelled.isCancelled, "preview preparation begins active")
    cancelled.cancel(); check(cancelled.isCancelled, "selection cancellation closes preparation")

    let cancelledMarker = libraryRoot.appendingPathComponent("must-not-launch")
    do {
      _ = try DrumxSongLibrary.run(URL(fileURLWithPath: "/usr/bin/touch"),
        arguments: [cancelledMarker.path], cancellation: cancelled)
      check(false, "pre-cancelled process cannot launch")
    } catch is CancellationError { check(true, "pre-cancelled process throws cancellation") }
    check(!FileManager.default.fileExists(atPath: cancelledMarker.path), "pre-cancellation prevents process side effects")
    let runningCancellation = DrumxSongPreparationCancellation(), cancellationStart = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { runningCancellation.cancel() }
    do {
      _ = try DrumxSongLibrary.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], cancellation: runningCancellation)
      check(false, "running process must stop on selection cancellation")
    } catch is CancellationError { check(true, "running process returns cancellation") }
    check(Date().timeIntervalSince(cancellationStart) < 2, "cancelled decoder releases preparation queue within two seconds")
    let timeoutStart = Date()
    do {
      _ = try DrumxSongLibrary.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1)
      check(false, "a decoder timeout cannot report success")
    } catch { check(error.localizedDescription.contains("timed out"), "timeout presents its meaningful reason") }
    check(Date().timeIntervalSince(timeoutStart) < 2, "timeout releases preparation queue within two seconds")
    let processOutput = try DrumxSongLibrary.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["process-output"])
    check(processOutput == "process-output", "normal process output is retained")
    do {
      _ = try DrumxSongLibrary.run(URL(fileURLWithPath: "/bin/ls"), arguments: [cancelledMarker.path])
      check(false, "failed processes cannot report success")
    } catch { check(error.localizedDescription.contains("must-not-launch"), "failed process diagnostics are retained") }

    var imported = 0
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--library-read", arguments.count >= 2 {
      let directory = URL(fileURLWithPath: arguments[1]), started = Date()
      let collection = DrumxSongLibrary.read(at: directory)
      check(collection.songs.allSatisfy { $0.charts.allSatisfy { $0.notes.isEmpty } }, "large library holds metadata only")
      print("Read \(collection.songs.count) song summaries in \(String(format: "%.3f", Date().timeIntervalSince(started))) seconds; \(collection.errors.count) errors; zero eager note arrays.")
      arguments.removeFirst(2)
    }
    while arguments.first == "--preview-check", arguments.count >= 2 {
      let manifest = URL(fileURLWithPath: arguments[1])
      let song = try JSONDecoder().decode(DrumxSong.self, from: Data(contentsOf: manifest))
      let started = Date(), preview = try DrumxSongPreparedAudio.preparePreview(song)
      check(preview.duration > 0 && preview.duration <= 18.001, "real preview is bounded")
      check(!preview.audio.files.isEmpty && preview.sourceStart >= 0, "real preview has synchronized playable audio")
      print("Prepared \(String(format: "%.2f", preview.duration))-second preview of \(song.title) at \(String(format: "%.2f", preview.sourceStart))s in \(String(format: "%.3f", Date().timeIntervalSince(started))) seconds, \(preview.audio.files.count) stems.")
      let warmStart = Date(), warmPreview = try DrumxSongPreparedAudio.preparePreview(song)
      check(warmPreview.sourceStart == preview.sourceStart && warmPreview.duration == preview.duration,
        "warm cache retains exact authored range and audio duration")
      print("Warm preview prepared in \(String(format: "%.3f", Date().timeIntervalSince(warmStart))) seconds.")
      arguments.removeFirst(2)
    }
    for path in arguments {
      let song = try JSONDecoder().decode(DrumxSong.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
      for difficulty in song.difficulties { replay(song, difficulty: difficulty); imported += 1 }
      print("Verified \(song.title) by \(song.artist): \(song.difficulties.joined(separator: ", "))")
    }
    print("\(checks) song checks passed; \(imported) imported difficulty charts replayed.")
  }
}
