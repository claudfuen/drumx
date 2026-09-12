import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private func record(
  _ feedback: inout DrumxHitFeedback, pad: Int = 0, judgment: Int? = 1,
  velocity: Double = 0.8, offset: Double = 0, time: Double = 10, reveal: Bool = true
) {
  feedback.record(
    pad: pad, judgment: judgment, velocity: velocity, offsetMS: offset, at: time,
    revealJudgment: reveal)
}

private func independentEvents() {
  var feedback = DrumxHitFeedback()
  for pad in 0..<3 { record(&feedback, pad: pad) }
  check(feedback.pulses.map(\.pad) == [0, 1, 2], "all simultaneous kit strikes survive")
  check(Set(feedback.pulses.map(\.id)).count == 3, "chord members have independent identities")
  record(&feedback, time: 10.025)
  check(feedback.pulses.count == 4, "a rapid same-pad repeat does not overwrite the earlier pulse")
  check(feedback.pulses.first?.startedAt == 10 && feedback.pulses.last?.startedAt == 10.025,
    "rapid hits retain distinct receipt times")
}

private func disclosure() {
  var feedback = DrumxHitFeedback()
  for judgment in 1...3 {
    record(&feedback, judgment: judgment, offset: -35)
    check(feedback.pulses.last?.kind == .matched, "centered, early, and late share matched feedback")
    check(feedback.pulses.last?.offsetMS == -35, "matched feedback retains signed timing")
  }
  record(&feedback, judgment: 4, offset: 80)
  check(feedback.pulses.last?.kind == .extra, "revealed extra is distinct from a match")
  check(feedback.pulses.last?.offsetMS == 0, "extra does not invent an offset to an expected note")
  for judgment: Int? in [nil, 0, 5, -1, 999] {
    record(&feedback, judgment: judgment, offset: 80)
    check(feedback.pulses.last?.kind == .strike, "ungraded input receives neutral acknowledgment")
  }
  for judgment: Int? in [nil, 0, 1, 2, 3, 4, 5] {
    record(&feedback, judgment: judgment, offset: -80, reveal: false)
    check(feedback.pulses.last?.kind == .strike && feedback.pulses.last?.offsetMS == 0,
      "hidden feedback exposes neither judgment nor timing offset")
  }
  let count = feedback.pulses.count
  feedback.prune(at: 10.1)
  check(feedback.pulses.count == count, "time advancement never manufactures miss feedback")
}

private func lifetime() {
  var feedback = DrumxHitFeedback()
  record(&feedback)
  let pulse = feedback.pulses[0]
  check(pulse.progress(at: 10) == 0, "animation starts at zero")
  check(abs((pulse.progress(at: 10.21) ?? -1) - 0.5) < 0.000001, "animation age uses the receipt clock")
  check(pulse.progress(at: 9.99) == nil, "future pulse is not drawn early")
  check(pulse.progress(at: 10 + DrumxHitFeedback.duration) == nil, "exact expiry is not drawable")
  check(pulse.progress(at: .nan) == nil && pulse.progress(at: .infinity) == nil,
    "invalid animation clock produces no draw state")
  record(&feedback, pad: 1, time: 10.3)
  feedback.prune(at: 10.42)
  check(feedback.pulses.count == 1 && feedback.pulses[0].pad == 1,
    "pruning expires only the old member of a burst")
  record(&feedback, pad: 2, time: 11)
  check(feedback.pulses.count == 1 && feedback.pulses[0].pad == 2,
    "new input also removes expired animations")
  feedback.prune(at: 11 + DrumxHitFeedback.duration)
  check(feedback.pulses.isEmpty, "last animation is removed at its boundary")
}

private func invalidInputAndBounds() {
  var feedback = DrumxHitFeedback()
  record(&feedback)
  let original = feedback.pulses
  record(&feedback, pad: -1)
  record(&feedback, pad: 3)
  record(&feedback, velocity: .nan)
  record(&feedback, velocity: .infinity)
  record(&feedback, offset: .nan)
  record(&feedback, offset: -.infinity)
  record(&feedback, time: .nan)
  record(&feedback, time: .infinity)
  feedback.prune(at: .nan)
  feedback.prune(at: .infinity)
  check(feedback.pulses == original, "invalid input cannot corrupt or remove existing feedback")
  record(&feedback, velocity: -0.5)
  check(feedback.pulses.last?.velocity == 0, "finite low velocity clamps to zero")
  record(&feedback, velocity: 1.5)
  check(feedback.pulses.last?.velocity == 1, "finite high velocity clamps to one")

  feedback.reset()
  for _ in 0..<DrumxHitFeedback.maxPulses { record(&feedback) }
  let evictedID = feedback.pulses[0].id
  record(&feedback, pad: 2, judgment: 4)
  check(feedback.pulses.count == 48, "storage stays bounded when the buffer fills")
  check(!feedback.pulses.contains { $0.id == evictedID }, "oldest received pulse is evicted first")
  check(feedback.pulses.last?.pad == 2 && feedback.pulses.last?.kind == .extra,
    "fresh feedback survives capacity eviction")
  for index in 0..<10_000 { record(&feedback, pad: index % 3) }
  check(feedback.pulses.count == 48 && Set(feedback.pulses.map(\.id)).count == 48,
    "sustained bursts retain bounded distinct recent events")
  let lastID = feedback.pulses.last!.id
  feedback.reset()
  check(feedback.pulses.isEmpty, "reset clears every animation")
  feedback.prune(at: 10.1)
  check(feedback.pulses.isEmpty, "time advancement after reset cannot replay old feedback")
  record(&feedback)
  check(feedback.pulses.count == 1 && feedback.pulses[0].id > lastID,
    "next take does not reuse a previous animation identity")
}

@main
enum DrumxHitFeedbackChecks {
  static func main() {
    independentEvents()
    disclosure()
    lifetime()
    invalidInputAndBounds()
    print("Drumx hit feedback: \(checks) checks passed.")
  }
}
