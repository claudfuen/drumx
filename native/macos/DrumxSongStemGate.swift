import Foundation

struct DrumxSongGateTarget {
  let id: Int
  let pad: Int
  let time: Double
}

/// Recorded drums start audible. Only authoritative chart judgments change the
/// gate: a credited hit opens it at the captured input time, and an expired miss
/// closes it at its native deadline. Extras do not participate. Recomputing the
/// latest judgment repairs delayed callbacks without retaining a stale latch.
enum DrumxSongStemGate {
  static let nativeEpsilon = 1e-9

  /// Prepare once from the same ordered chart targets loaded into the core.
  /// The next same-pad target shortens the window to their midpoint, exactly as
  /// dx_core_load_song does. The core resolves a miss only after deadline + 1ns;
  /// callers supply resolved notes, so this helper never expires notes itself.
  /// Invalid chart data yields no deadlines and cannot invent a valid gate map.
  static func missDeadlines(targets: [DrumxSongGateTarget],
                            missWindow: Double = 0.125) -> [Int: Double] {
    guard validWindow(missWindow), targets.count <= DrumxSongScore.maximumNotes,
      Set(targets.map(\.id)).count == targets.count,
      targets.allSatisfy({ (0..<DrumxSongScore.maximumNotes).contains($0.id)
        && (0..<8).contains($0.pad) && $0.time.isFinite && (0...7200).contains($0.time) }) else { return [:] }
    let ordered = targets.sorted { $0.time == $1.time ? $0.pad < $1.pad : $0.time < $1.time }
    var nextTimes = Array(repeating: Double.infinity, count: 8)
    var deadlines: [Int: Double] = [:]
    deadlines.reserveCapacity(targets.count)
    for target in ordered.reversed() {
      let next = nextTimes[target.pad]
      guard next - target.time > nativeEpsilon else { return [:] }
      deadlines[target.id] = min(target.time + missWindow, (target.time + next) / 2)
      nextTimes[target.pad] = target.time
    }
    return deadlines
  }

  /// At an exact timestamp tie, a miss wins regardless of array order. A partial
  /// chord therefore closes when its missing part expires; an all-hit chord
  /// remains audible. Missing or invalid authoritative data fails closed.
  static func isMuted(resolvedNotes: [DrumxSongScoredNote], hitTimes: [Int: Double],
                      missDeadlines: [Int: Double], missWindow: Double = 0.125) -> Bool {
    guard validWindow(missWindow), resolvedNotes.count <= DrumxSongScore.maximumNotes else { return true }
    var receivedIDs = Set<Int>()
    var latestTime = -Double.infinity
    var muted = false
    for note in resolvedNotes {
      guard (0..<DrumxSongScore.maximumNotes).contains(note.id), note.time.isFinite,
        (0...7200).contains(note.time), receivedIDs.insert(note.id).inserted,
        let deadline = missDeadlines[note.id], deadline.isFinite,
        deadline >= note.time, deadline <= note.time + missWindow + nativeEpsilon else { return true }
      let judgmentTime: Double
      if note.hit {
        guard let captured = hitTimes[note.id], captured.isFinite,
          abs(captured - note.time) <= missWindow + nativeEpsilon else { return true }
        judgmentTime = captured
      } else { judgmentTime = deadline }
      if judgmentTime > latestTime {
        latestTime = judgmentTime; muted = !note.hit
      } else if judgmentTime == latestTime && !note.hit { muted = true }
    }
    return muted
  }

  private static func validWindow(_ value: Double) -> Bool {
    value.isFinite && (0...1).contains(value)
  }
}
