import Foundation

private var checks = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() {
    fatalError("FAIL: \(message)")
  }
}

private let defaultMapping = [[42, 44, 46], [38, 40], [35, 36]]

private func settings(
  tempo: Double = 96, mode: Int = 0, live: Bool = true, bars: Int = 4,
  offset: Double = 0, input: String = "keyboard", mapping: [[Int]] = defaultMapping,
  version: String = "first-backbeat-v1", hands: Bool = true
) -> TakeSettings {
  TakeSettings(
    tempo: tempo, mode: mode, liveFeedback: live, bars: bars, calibrationMS: offset,
    inputIdentity: input, mapping: mapping, lessonVersion: version, handHints: hands)
}

private final class TestTake {
  let core: OpaquePointer
  init(tempo: Double = 96, mode: Int = 0, bars: Int = 4) {
    core = dx_core_create()!
    check(dx_core_reset(core, tempo, Int32(bars)) == 1, "test take configured")
    dx_core_set_guidance(core, Int32(mode))
  }
  deinit { dx_core_destroy(core) }
  var snapshot: DXSnapshot {
    var result = DXSnapshot()
    dx_core_snapshot(core, &result)
    return result
  }
  func play(offset: Double = 0.01, include: (DXEvent) -> Bool = { _ in true }) {
    for index in 0..<dx_core_event_count(core) {
      var event = DXEvent()
      _ = dx_core_event(core, index, &event)
      if include(event) {
        _ = dx_core_input(core, event.pad, event.time_seconds + offset, 0.8)
      }
    }
  }
  func finish() { dx_core_advance(core, dx_core_duration(core)) }
}

private func reviewChecks() {
  let empty = TestTake()
  empty.finish()
  let noHits = LessonReview(snapshot: empty.snapshot, completedNaturally: true)
  check(noHits.headline == "No matched hits yet", "no-hit review makes no timing claim")
  check(noHits.suggestedPad == nil, "no arbitrary timing diagnosis without hits")

  let few = TestTake()
  few.play(include: { $0.id < 3 })
  few.finish()
  let sparse = LessonReview(snapshot: few.snapshot, completedNaturally: true)
  check(!sparse.detail.contains("early") && !sparse.detail.contains("late"),
    "few matched hits do not establish a timing trend")

  let onlyHat = TestTake()
  onlyHat.play(include: { $0.pad == 0 })
  onlyHat.finish()
  let incompletePattern = LessonReview(snapshot: onlyHat.snapshot, completedNaturally: true)
  check(incompletePattern.headline.hasPrefix("Bring in"), "omissions guide next practice")
  check(incompletePattern.suggestedPad == 1 || incompletePattern.suggestedPad == 2,
    "missing limb is suggested instead of the more frequent hi-hat")

  let full = TestTake()
  full.play()
  full.finish()
  let good = LessonReview(snapshot: full.snapshot, completedNaturally: true)
  check(good.headline == "The phrase stayed together", "complete timing success stated precisely")
  check(good.detail.contains("timing band"), "success copy describes the measured timing outcome")

  let early = TestTake()
  early.play(offset: -0.04)
  early.finish()
  let earlyReview = LessonReview(snapshot: early.snapshot, completedNaturally: true)
  check(earlyReview.detail.contains("early"), "supported recent early tendency described")
  check(earlyReview.detail.contains("Listen for the click"), "timing feedback gives a practical next action")

  var stale = early.snapshot
  stale.bias.0.state = 5
  stale.bias.1.state = 5
  stale.bias.2.state = 5
  let staleReview = LessonReview(snapshot: stale, completedNaturally: true)
  check(!staleReview.detail.contains("tended"), "stale tendencies are not presented as current")

  let partial = TestTake()
  _ = dx_core_input(partial.core, 0, 0, 0.8)
  dx_core_finish(partial.core, 0.1)
  check(LessonReview(snapshot: partial.snapshot, completedNaturally: false).headline == "Take stopped",
    "partial result is explicitly labeled")
  check(LessonReview(snapshot: partial.snapshot, completedNaturally: true).headline == "Take stopped",
    "natural flag alone cannot turn a partial core result into a full take")
}

private func historyChecks(defaults: UserDefaults) {
  let history = LessonHistory(defaults: defaults, key: "history")
  let base = settings()
  let full = TestTake()
  full.play(offset: 0.02)
  full.finish()
  let id = UUID(), date = Date(timeIntervalSince1970: 1000)
  let stored = history.record(
    id: id, settings: base, snapshot: full.snapshot, completedNaturally: true, endedAt: date)
  check(stored?.matched == 48 && stored?.timingAccuracyPercent == 100,
    "complete natural take stored with honest denominator")
  check(history.attempts.count == 1, "one take recorded")
  check(history.best(matching: base)?.id == id, "personal best uses matching settings")
  check(history.best(matching: base, excluding: id) == nil, "caller can compare against previous takes")

  let restored = LessonHistory(defaults: defaults, key: "history")
  check(restored.attempts == history.attempts, "local history round trips through Codable")

  let variants = [
    settings(tempo: 90), settings(mode: 1), settings(live: false), settings(bars: 2),
    settings(offset: 1), settings(input: "midi:123"), settings(mapping: [[42], [38], [36]]),
    settings(version: "first-backbeat-v2"), settings(hands: false),
  ]
  for variant in variants {
    check(history.best(matching: variant) == nil, "different setting does not inherit a personal best")
  }
  check(settings(mapping: [[46, 42, 44, 42], [40, 38], [36, 35]]) == base,
    "mapping alias order and duplicate aliases do not split comparison groups")

  let stopped = TestTake()
  dx_core_finish(stopped.core, 1)
  check(history.record(id: UUID(), settings: base, snapshot: stopped.snapshot,
    completedNaturally: false) == nil, "partial take excluded")
  check(history.record(id: UUID(), settings: base, snapshot: stopped.snapshot,
    completedNaturally: true) == nil, "partial core result excluded even with a mistaken completion flag")
  let canceled = TestTake()
  dx_core_finish(canceled.core, -0.1)
  check(history.record(id: UUID(), settings: base, snapshot: canceled.snapshot,
    completedNaturally: false) == nil, "canceled count-in excluded")
  check(history.record(id: UUID(), settings: base, snapshot: full.snapshot,
    completedNaturally: false) == nil, "manual stop at phrase end remains ineligible")
  check(history.attempts.count == 1, "ineligible attempts do not enter history")

  let delayed = TestTake()
  delayed.finish()
  let delayedID = UUID()
  history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(1))
  check(history.attempts.last?.missed == 48, "initial delayed result can contain expired misses")
  delayed.play(offset: 0.005)
  history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(1))
  check(history.attempts.count == 2 && history.attempts.last?.matched == 48,
    "same UUID upsert replaces misses without adding another take")
  check(history.best(matching: base)?.id == delayedID,
    "equal percentage and hit rate use lower absolute error as tie-breaker")
  check(history.record(id: delayedID, settings: settings(live: false), snapshot: delayed.snapshot,
    completedNaturally: true) == nil, "late correction cannot change the take's comparison settings")

  let spam = TestTake()
  spam.play()
  _ = dx_core_input(spam.core, 0, 0.02, 0.8)
  spam.finish()
  let spamAttempt = history.record(id: UUID(), settings: base, snapshot: spam.snapshot,
    completedNaturally: true)
  check(spamAttempt?.extra == 1 && (spamAttempt?.timingAccuracyPercent ?? 100) < 100,
    "extra strikes lower personal-best accuracy")
  check(history.best(matching: base)?.id == delayedID, "primary percentage outranks lower timing error")

  _ = dx_core_input(delayed.core, 0, -0.08, 0.8)
  history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(1))
  check(history.attempts.count == 3, "a downward correction also updates the existing attempt")
  check(history.best(matching: base)?.id == id,
    "an earlier captured strike can lower a corrected result and change the personal best")

  var invalid = full.snapshot
  invalid.total.mean_offset_ms = .nan
  check(history.record(id: UUID(), settings: base, snapshot: invalid,
    completedNaturally: true) == nil, "non-finite signed timing rejected")
  invalid = full.snapshot
  invalid.total.mean_absolute_offset_ms = .infinity
  check(history.record(id: UUID(), settings: base, snapshot: invalid,
    completedNaturally: true) == nil, "non-finite absolute timing rejected")
  invalid = full.snapshot
  invalid.total.timing_accuracy_percent = .nan
  check(history.record(id: UUID(), settings: base, snapshot: invalid,
    completedNaturally: true) == nil, "non-finite source percentage rejected")
  invalid = full.snapshot
  invalid.elapsed_seconds = .infinity
  check(history.record(id: UUID(), settings: base, snapshot: invalid,
    completedNaturally: true) == nil, "non-finite song clock rejected")
  check(history.record(id: UUID(), settings: settings(offset: .nan), snapshot: full.snapshot,
    completedNaturally: true) == nil, "non-finite calibration rejected")
  check(history.record(id: UUID(), settings: base, snapshot: full.snapshot,
    completedNaturally: true, endedAt: Date(timeIntervalSinceReferenceDate: .infinity)) == nil,
    "non-finite record date rejected")
  check(history.record(id: UUID(), settings: settings(tempo: 90), snapshot: full.snapshot,
    completedNaturally: true) == nil, "stored tempo must match the core snapshot")
  check(history.record(id: UUID(), settings: settings(mode: 2), snapshot: full.snapshot,
    completedNaturally: true) == nil, "stored guidance must match the core snapshot")
  check(history.record(id: UUID(), settings: settings(bars: 2), snapshot: full.snapshot,
    completedNaturally: true) == nil, "stored bar count must match phrase duration")

  let bounded = LessonHistory(defaults: defaults, key: "bounded")
  let oldestID = UUID()
  for index in 0..<205 {
    bounded.record(id: index == 0 ? oldestID : UUID(), settings: base, snapshot: full.snapshot,
      completedNaturally: true, endedAt: date.addingTimeInterval(Double(index)))
  }
  check(bounded.attempts.count == 200, "history retains at most 200 attempts")
  check(!bounded.attempts.contains { $0.id == oldestID }, "oldest attempt removed at capacity")
  check(LessonHistory(defaults: defaults, key: "bounded").attempts.count == 200,
    "persisted history obeys the same capacity")
  defaults.set(Data("invalid json".utf8), forKey: "corrupt")
  check(LessonHistory(defaults: defaults, key: "corrupt").attempts.isEmpty,
    "corrupt local history does not prevent practice")
}

@main
enum DrumxLessonChecks {
  static func main() {
    let suite = "drumx.lesson-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    reviewChecks()
    historyChecks(defaults: defaults)
    print("Drumx lesson review/history: \(checks) checks passed.")
  }
}
