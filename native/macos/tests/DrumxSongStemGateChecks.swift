import Foundation

private final class CoreGate {
  let core: OpaquePointer
  var ledger = DrumxSongInputLedger()
  var deadlines: [Int: Double] = [:]

  init(_ targets: [(Int, Double)]) {
    guard let core = dx_core_create() else { fatalError("Could not create timing core") }
    self.core = core
    load(targets)
  }
  deinit { dx_core_destroy(core) }

  func load(_ targets: [(Int, Double)]) {
    var source = targets.map { DXSongEvent(pad: Int32($0.0), time_seconds: $0.1) }
    precondition(source.withUnsafeMutableBufferPointer {
      dx_core_load_song(core, 6, $0.baseAddress, Int32($0.count))
    } != 0)
    ledger = DrumxSongInputLedger()
    var chart: [DrumxSongGateTarget] = []
    for index in 0..<dx_core_event_count(core) {
      var event = DXEvent(); precondition(dx_core_event(core, index, &event) != 0)
      chart.append(.init(id: Int(event.id), pad: Int(event.pad), time: event.time_seconds))
    }
    deadlines = DrumxSongStemGate.missDeadlines(targets: chart)
  }
  func advance(_ time: Double) { dx_core_advance(core, time) }
  @discardableResult func hit(_ pad: Int, _ time: Double) -> DXHitResult {
    let result = dx_core_input(core, Int32(pad), time, 0.8)
    ledger.receive(id: result.id, eventID: Int(result.event_id), time: result.time_seconds,
      isExtra: result.judgment == Int32(DX_EXTRA.rawValue))
    return result
  }
  var resolved: [DrumxSongScoredNote] {
    var notes: [DrumxSongScoredNote] = []
    for index in 0..<dx_core_event_count(core) {
      var event = DXEvent(); precondition(dx_core_event(core, index, &event) != 0)
      if event.resolved != 0 { notes.append(.init(id: Int(event.id), time: event.time_seconds, hit: event.hit != 0)) }
    }
    return notes
  }
  var muted: Bool {
    DrumxSongStemGate.isMuted(resolvedNotes: resolved, hitTimes: ledger.creditedHitTimes, missDeadlines: deadlines)
  }
}

@main enum DrumxSongStemGateChecks {
  static var checks = 0
  static func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
  }
  static func near(_ value: Double?, _ expected: Double, _ message: String) {
    check(value.map { abs($0 - expected) < 1e-12 } ?? false, message)
  }
  static func main() {
    let targets: [DrumxSongGateTarget] = [.init(id: 0, pad: 1, time: 1), .init(id: 1, pad: 2, time: 2)]
    let deadlines = DrumxSongStemGate.missDeadlines(targets: targets)
    func gate(_ notes: [DrumxSongScoredNote], _ hitTimes: [Int: Double] = [:],
              _ deadlines: [Int: Double] = deadlines) -> Bool {
      DrumxSongStemGate.isMuted(resolvedNotes: notes, hitTimes: hitTimes, missDeadlines: deadlines)
    }
    let miss = DrumxSongScoredNote(id: 0, time: 1, hit: false)
    let hit = DrumxSongScoredNote(id: 1, time: 2, hit: true)
    near(deadlines[0], 1.125, "Ordinary miss uses the full matching window")
    near(deadlines[1], 2.125, "Another pad does not shorten the first pad's deadline")
    check(!gate([]), "The intro starts audible before any judgment")
    check(!gate([], [0: 1, 1: 2, 999: 50]), "Stale or unrelated captured times cannot affect an empty chart snapshot")
    check(gate([miss]), "A resolved miss closes the recorded-drum family")
    check(!gate([miss, hit], [1: 1.98]), "A later captured match reopens recorded drums")
    check(!gate([hit, miss], [1: 1.98]), "Array order cannot replace captured-time ordering")
    check(gate([.init(id: 1, time: 2, hit: false), .init(id: 0, time: 1, hit: true)], [0: 1.1]),
      "An older hit arriving last cannot reopen a more recent miss")
    check(!gate([.init(id: 0, time: 1, hit: true)], [0: 1.02]), "Correcting a miss removes its stale mute event")

    let midpoint = DrumxSongStemGate.missDeadlines(targets: [
      .init(id: 2, pad: 2, time: 1.2), .init(id: 1, pad: 1, time: 1.1), .init(id: 0, pad: 1, time: 1)])
    near(midpoint[0], 1.05, "Fast same-pad notes expire at their midpoint")
    near(midpoint[1], 1.225, "Last same-pad note retains its full window")
    near(midpoint[2], 1.325, "Independent pad keeps its own deadline")
    check(!gate([miss, .init(id: 1, time: 1.1, hit: true)], [1: 1.1], midpoint),
      "A rapid roll hit after the earlier midpoint reopens the gate")

    let tieDeadlines = DrumxSongStemGate.missDeadlines(targets: [
      .init(id: 0, pad: 1, time: 1), .init(id: 1, pad: 2, time: 1.1)])
    let tiedHit = DrumxSongScoredNote(id: 1, time: 1.1, hit: true)
    check(gate([miss, tiedHit], [1: 1.125], tieDeadlines), "A miss wins an exact tie after a hit")
    check(gate([tiedHit, miss], [1: 1.125], tieDeadlines), "A miss wins an exact tie before a hit")
    check(!gate([miss, tiedHit], [1: 1.125 + 0.1e-9], tieDeadlines),
      "Distinct captured times are not rounded into a tie")
    check(gate([hit], [:]), "A matched note without its captured time fails closed")
    check(gate([hit], [1: .nan]), "Nonfinite captures fail closed")
    check(gate([hit], [1: 4]), "An impossible credited capture fails closed")
    check(gate([miss], [:], [:]), "A missing authoritative deadline fails closed")
    check(gate([miss], [:], [0: 0.9]), "A deadline cannot precede its chart target")
    check(gate([miss, miss]), "Duplicate resolved IDs fail closed")
    check(DrumxSongStemGate.missDeadlines(targets: targets, missWindow: .nan).isEmpty,
      "Invalid windows cannot create deadline maps")
    check(DrumxSongStemGate.missDeadlines(targets: [.init(id: 0, pad: 8, time: 1)]).isEmpty,
      "Unsupported pads cannot create deadline maps")
    check(DrumxSongStemGate.missDeadlines(targets: [targets[0], targets[0]]).isEmpty,
      "Duplicate chart identities are rejected")
    check(DrumxSongStemGate.missDeadlines(targets: [targets[0], .init(id: 1, pad: 1, time: 1 + 0.5e-9)]).isEmpty,
      "Same-pad duplicate epsilon matches the native chart validator")

    let rest = CoreGate([(1, 1), (2, 2)])
    check(!rest.muted && rest.resolved.isEmpty, "Real core intro starts audible")
    rest.advance(1.125)
    check(!rest.muted && rest.resolved.isEmpty, "A target remains unresolved at its exact deadline")
    rest.advance(1.125 + 0.5e-9)
    check(!rest.muted && rest.resolved.isEmpty, "Native one-nanosecond expiry tolerance is preserved")
    rest.advance(1.125 + 2e-9)
    check(rest.muted, "A real core miss closes after the matching deadline")
    rest.advance(1.7)
    check(rest.muted, "An ordinary rest does not reset a mute")
    check(rest.hit(6, 1.75).judgment == Int32(DX_EXTRA.rawValue) && rest.muted,
      "An overhit never reopens recorded drums")
    rest.hit(2, 2)
    check(!rest.muted, "The next real matched note reopens recorded drums")
    check(rest.hit(7, 2.2).judgment == Int32(DX_EXTRA.rawValue) && !rest.muted,
      "An overhit never closes recorded drums either")
    rest.advance(6)
    check(!rest.muted, "A completed played outro stays audible")
    rest.load([(1, 1), (2, 2)])
    rest.advance(6)
    check(rest.muted, "An all-missed outro stays muted")
    rest.load([(1, 1), (2, 2)])
    check(!rest.muted && rest.ledger.creditedHitTimes.isEmpty, "Restart clears old judgments and opens the intro")

    let chord = CoreGate([(1, 1), (2, 1)])
    chord.hit(2, 1)
    check(!chord.muted, "A played chord part initially stays audible")
    chord.advance(1.126)
    check(chord.muted, "An expired unplayed chord sibling closes the entire drum family")
    chord.hit(1, 0.99)
    check(!chord.muted, "Delayed captured chord hit repairs the expired miss and reopens")
    chord.load([(1, 1), (2, 1)])
    chord.hit(1, 0.99); chord.hit(2, 1.01); chord.advance(1.3)
    check(!chord.muted, "An all-hit chord remains audible after both windows end")

    let rapid = CoreGate([(1, 1), (1, 1.1)])
    rapid.advance(1.05 + 0.5e-9)
    check(rapid.resolved.isEmpty, "Shortened native deadline retains the epsilon boundary")
    rapid.advance(1.05 + 2e-9)
    check(rapid.muted, "Shortened native deadline actually closes a missed roll target")
    rapid.hit(1, 1.1)
    check(!rapid.muted, "Following fast roll hit reopens after the real midpoint deadline")

    let reordered = CoreGate([(1, 1), (2, 1)])
    reordered.hit(2, 1.125 + 0.5e-9)
    reordered.advance(1.126)
    check(!reordered.muted, "A valid boundary hit captured just after a sibling deadline is latest")
    reordered.hit(2, 0.99)
    near(reordered.ledger.creditedHitTimes[1], 0.99, "Earlier replacement updates the credited capture accessor")
    check(reordered.muted, "Earlier replacement cannot resurrect the demoted later hit's audible state")
    check(reordered.ledger.extraTimes.count == 1, "The demoted later input becomes an ignored-for-gating extra")
    let immediate = CoreGate([(1, 1), (2, 1)])
    immediate.hit(2, 0.99); immediate.hit(2, 1.125 + 0.5e-9); immediate.advance(1.126)
    check(immediate.muted == reordered.muted, "Delivery order produces the same final gate for the same captured inputs")
    reordered.hit(1, 0.98)
    check(!reordered.muted, "A late captured correction removes the final miss without a stale latch")

    print("\(checks) recorded-drum gate checks passed, including real timing-core delayed capture and midpoint deadlines")
  }
}
