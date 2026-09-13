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

    var imported = 0
    for path in CommandLine.arguments.dropFirst() {
      let song = try JSONDecoder().decode(DrumxSong.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
      for difficulty in song.difficulties { replay(song, difficulty: difficulty); imported += 1 }
      print("Verified \(song.title) by \(song.artist): \(song.difficulties.joined(separator: ", "))")
    }
    print("\(checks) song checks passed; \(imported) imported difficulty charts replayed.")
  }
}
