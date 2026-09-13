import Foundation

@main
struct DrumxSongScoreCoreChecks {
  static func main() throws {
    guard let core = dx_core_create() else { fatalError("Missing timing core") }
    defer { dx_core_destroy(core) }
    var events = (1...40).map { DXSongEvent(pad: 1, time_seconds: Double($0)) }
    precondition(events.withUnsafeMutableBufferPointer { dx_core_load_song(core, 42, $0.baseAddress, 40) } != 0)
    var ledger = DrumxSongInputLedger()
    func receive(_ time: Double) {
      let result = dx_core_input(core, 1, time, 0.8)
      ledger.receive(id: result.id, eventID: Int(result.event_id), time: result.time_seconds,
        isExtra: result.judgment == Int32(DX_EXTRA.rawValue))
    }
    func score() -> DrumxSongScore {
      var notes: [DrumxSongScoredNote] = []
      for index in 0..<dx_core_event_count(core) {
        var event = DXEvent()
        precondition(dx_core_event(core, index, &event) != 0 && event.resolved != 0)
        notes.append(.init(id: Int(event.id), time: event.time_seconds, hit: event.hit != 0))
      }
      let score = DrumxSongScore(expectedNotes: 40, resolvedNotes: notes, extraTimes: ledger.extraTimes, completed: true)
      var snapshot = DXSnapshot(); dx_core_snapshot(core, &snapshot)
      precondition(score.isValid && score.matched == Int(snapshot.total.matched)
        && score.missed == Int(snapshot.total.missed) && score.extra == Int(snapshot.total.extra))
      return score
    }
    for second in 1...40 { receive(Double(second) + (second == 10 ? 0.02 : 0)) }
    dx_core_advance(core, 42.2)
    let initial = score()
    precondition(initial.points == 10_000 && initial.fullCombo)
    // Callback delivery is late, but the captured timestamp precedes the hit
    // originally credited to note 10. The native core demotes that former hit.
    receive(9.98)
    let corrected = score()
    precondition(corrected.points == 7_000 && corrected.extra == 1 && !corrected.fullCombo)
    precondition(ledger.extraTimes == [10.02])

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drumx-core-score-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = DrumxSongScoreStore(root: root), id = UUID(), player = UUID()
    let before = try store.record(.init(id: id, profileID: player, songID: "core-fixture", difficulty: "expert",
      revision: 1, score: initial))
    let after = try store.record(.init(id: id, profileID: player, songID: "core-fixture", difficulty: "expert",
      revision: 2, score: corrected))
    precondition(before.best.score.points == 10_000 && after.best.score.points == 7_000
      && after.playCount == 1 && !after.personalBest)
    print("Timing core song-score integration passed: delayed input corrects the saved score without another play")
  }
}
