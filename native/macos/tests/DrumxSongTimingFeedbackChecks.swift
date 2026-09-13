import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private func feedback(_ offsets: [Double], start: Double = 10) -> DrumxSongTimingFeedback {
  var result = DrumxSongTimingFeedback()
  for (index, offset) in offsets.enumerated() {
    result.record(id: UInt64(index + 1), time: start + Double(index) * 0.1, offsetMS: offset)
  }
  return result
}

private func directionAndWarmup() {
  var result = DrumxSongTimingFeedback()
  check(result.state(at: 0).status == .gathering, "empty feedback has no tendency")
  result.record(id: 1, time: -0.04, offsetMS: -40)
  result.record(id: 2, time: 0.1, offsetMS: -40)
  check(result.state(at: 0.1).offsetMS == nil, "two matches do not claim a trend")
  result.record(id: 3, time: 0.2, offsetMS: -40)
  let early = result.state(at: 0.2)
  check(early.status == .rushing && early.offsetMS == -40, "negative captured offsets mean rushing")
  check(early.sampleCount == 3 && early.spreadMS == 0, "three consistent matches establish bias")
  let late = feedback([30, 35, 40]).state(at: 10.2)
  check(late.status == .dragging && late.offsetMS == 35, "positive offsets mean dragging")
  for offset in [-12.0, 0, 12] {
    check(feedback([offset, offset, offset]).state(at: 10.2).status == .centered,
      "inclusive twelve millisecond deadband is centered")
  }
  check(feedback([-12.01, -12.01, -12.01]).state(at: 10.2).status == .rushing,
    "earlier than deadband is rushing")
  check(feedback([12.01, 12.01, 12.01]).state(at: 10.2).status == .dragging,
    "later than deadband is dragging")
}

private func robustnessAndChords() {
  let robust = feedback([-40, -40, -40, 120]).state(at: 10.3)
  check(robust.status == .rushing && robust.offsetMS == -40 && robust.sampleCount == 3,
    "one stray late note cannot reverse a consistent early tendency")
  let uneven = feedback([-60, -60, 60, 60]).state(at: 10.3)
  check(uneven.status == .uneven && uneven.offsetMS == 0 && uneven.spreadMS == 60,
    "opposing large errors do not falsely claim centered timing")
  check(feedback([-40, -40, 120]).state(at: 10.2).status == .gathering,
    "outlier filtering still requires three retained matches")
  var chord = DrumxSongTimingFeedback()
  for id in 1...8 { chord.record(id: UInt64(id), time: 10, offsetMS: 20) }
  let state = chord.state(at: 10)
  check(state.sampleCount == 8 && state.status == .dragging, "equal-time notes across all eight pads survive")
  chord.record(id: 8, time: 10.1, offsetMS: -100)
  chord.record(id: 1, time: 10.1, offsetMS: -100)
  check(chord.state(at: 10.1) == state, "duplicate and replayed IDs cannot alter tendency")
  for id in 9...30 { chord.record(id: UInt64(id), time: 10.2, offsetMS: -20) }
  let replaced = chord.state(at: 10.2)
  check(replaced.sampleCount == 12 && replaced.status == .rushing,
    "only the latest twelve matched notes contribute")
}

private func songClockAndOrdering() {
  var result = feedback([30, 30, 30])
  let paused = result.state(at: 10.2)
  for _ in 0..<100 { check(result.state(at: 10.2) == paused, "a paused song clock preserves the trend") }
  check(result.state(at: 13.199).status == .dragging, "trend remains fresh before three seconds")
  let stale = result.state(at: 13.2)
  check(stale.status == .stale && stale.offsetMS == nil, "three seconds without matches clears the displayed offset")
  check(result.state(at: 15).status == .stale && result.state(at: 15).sampleCount == 0,
    "all samples expire after four seconds")
  result.record(id: 4, time: 14.3, offsetMS: -40)
  check(result.state(at: 14.3).status == .gathering, "fresh input after a gap starts a new window")
  result.record(id: 5, time: 14.4, offsetMS: -40)
  result.record(id: 6, time: 14.2, offsetMS: -40)
  let delayed = result.state(at: 14.4)
  check(delayed.status == .rushing && delayed.sampleCount == 3,
    "late delivery is ordered by original captured song time")
  result.record(id: 7, time: 9, offsetMS: 100)
  check(result.state(at: 14.4) == delayed, "old delayed input cannot refresh or contaminate recent feedback")
  check(result.state(at: 17.4).status == .stale, "late old input does not move the stale deadline")
  var future = feedback([30, 30, 30], start: 20)
  check(future.state(at: 19).sampleCount == 0, "future captures are not revealed early")
  future.reset()
  check(future.state(at: 19).status == .gathering, "reset removes stale song history")
  for id in 1...3 { future.record(id: UInt64(id), time: 0, offsetMS: 0) }
  check(future.state(at: 0).status == .centered, "new core run can reuse IDs after reset")
}

private func invalidInput() {
  var result = feedback([20, 20, 20])
  let original = result.state(at: 10.2)
  result.record(id: 4, time: .nan, offsetMS: 20)
  result.record(id: 4, time: .infinity, offsetMS: 20)
  result.record(id: 4, time: 10.2, offsetMS: .nan)
  result.record(id: 4, time: 10.2, offsetMS: -.infinity)
  result.record(id: 0, time: 10.2, offsetMS: -20)
  check(result.state(at: 10.2) == original, "invalid inputs cannot poison existing feedback")
  check(result.state(at: .nan).offsetMS == nil && result.state(at: .infinity).offsetMS == nil,
    "invalid read clock cannot expose a timing estimate")
  result.record(id: 4, time: 10.2, offsetMS: 20)
  check(result.state(at: 10.2).sampleCount == 4, "invalid input does not consume an ID")
}

@main
enum DrumxSongTimingFeedbackChecks {
  static func main() {
    directionAndWarmup()
    robustnessAndChords()
    songClockAndOrdering()
    invalidInput()
    var replacement = DrumxSongTimingFeedback()
    replacement.record(id: 1, time: 1, offsetMS: 20, eventID: 0)
    replacement.record(id: 2, time: 1.1, offsetMS: 20, eventID: 1)
    replacement.record(id: 3, time: 1.2, offsetMS: 20, eventID: 2)
    replacement.record(id: 4, time: 1.15, offsetMS: -5, eventID: 2)
    check(replacement.state(at: 1.2).sampleCount == 3,
      "a replacement hit cannot count its now-extra predecessor in timing")
    replacement.record(id: 5, time: 1.05, offsetMS: -5, eventID: 1)
    check(replacement.state(at: 1.2).status == .centered,
      "replacement corrections update the recent matched-hit tendency")
    print("Drumx song timing feedback: \(checks) checks passed.")
  }
}
