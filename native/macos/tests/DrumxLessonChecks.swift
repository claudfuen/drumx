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
  check(stored?.bestStreak == 48, "new history records the core's best on-time streak")
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
  check(DrumxRunScore(attempt: history.attempts.last!).stars == 0,
    "expired misses earn no stars while awaiting captured input")
  delayed.play(offset: 0.005)
  history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(1))
  check(history.attempts.count == 2 && history.attempts.last?.matched == 48,
    "same UUID upsert replaces misses without adding another take")
  check(history.best(matching: base)?.id == delayedID,
    "equal percentage and hit rate use lower absolute error as tie-breaker")
  check(DrumxRunScore(attempt: history.attempts.last!).stars == 5,
    "late correction can promote a naturally completed perfect take to five stars")
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
  check(DrumxRunScore(attempt: history.attempts.first { $0.id == delayedID }!).stars == 4,
    "a downward correction removes the perfect star")
  let recent = history.recent(matching: base)
  check(recent.count == 3 && recent[0].id == spamAttempt?.id && recent[2].id == id,
    "recent attempts are returned newest first")
  check(history.recent(matching: base, limit: 1).map(\.id) == [spamAttempt!.id],
    "recent attempt limit is respected")
  check(history.recent(matching: base, excluding: spamAttempt?.id).map(\.id) == [delayedID, id],
    "recent attempts can exclude the current result")
  check(history.recent(matching: settings(live: false)).isEmpty,
    "recent comparisons require the same aid conditions")
  check(history.recent(matching: base, limit: 0).isEmpty
    && history.recent(matching: base, limit: -1).isEmpty, "non-positive recent limits return no rows")

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
  check(bounded.recent(matching: base).count == 6
    && bounded.recent(matching: base, limit: Int.max).count == 200,
    "recent defaults to six and cannot exceed stored capacity")

  let encoded = try! JSONEncoder().encode(stored!)
  var legacyJSON = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
  legacyJSON.removeValue(forKey: "bestStreak")
  let legacyData = try! JSONSerialization.data(withJSONObject: legacyJSON)
  let legacy = try! JSONDecoder().decode(LessonAttempt.self, from: legacyData)
  check(legacy.bestStreak == nil, "older records without bestStreak still decode")
  let legacyScore = DrumxRunScore(attempt: legacy)
  check(legacyScore.points == 10_000 && legacyScore.stars == 5
    && legacyScore.combo == 0 && legacyScore.bestCombo == 0,
    "legacy scores retain earned results without fabricating recorded combos")
  defaults.set(try! JSONSerialization.data(withJSONObject: [legacyJSON]), forKey: "legacy")
  check(LessonHistory(defaults: defaults, key: "legacy").attempts.count == 1,
    "legacy history remains eligible after the optional field addition")
  defaults.set(Data("invalid json".utf8), forKey: "corrupt")
  check(LessonHistory(defaults: defaults, key: "corrupt").attempts.isEmpty,
    "corrupt local history does not prevent practice")
}

private func scoreSnapshot(
  onTime: Int32, expected: Int32 = 10_000, extra: Int32 = 0,
  missed: Int32 = 0, complete: Bool = true
) -> DXSnapshot {
  var snapshot = DXSnapshot()
  snapshot.bpm = 96
  snapshot.duration_seconds = 10
  snapshot.elapsed_seconds = complete ? 10 : 9.9
  snapshot.finished = complete ? 1 : 0
  snapshot.total.expected = expected
  snapshot.total.matched = expected - missed
  snapshot.total.missed = missed
  snapshot.total.extra = extra
  snapshot.total.on_time = onTime
  snapshot.total.streak = onTime
  snapshot.total.best_streak = onTime
  let denominator = Double(expected) + Double(extra)
  snapshot.total.timing_accuracy_percent = Double(onTime) / denominator * 100
  snapshot.total.hit_rate_percent = Double(expected - missed) / denominator * 100
  return snapshot
}

private func runScoreChecks() {
  let thresholdCases: [(Int32, Int)] = [
    (0, 0), (3999, 0), (4000, 1), (5999, 1), (6000, 2), (7499, 2),
    (7500, 3), (8999, 3), (9000, 4), (9999, 4), (10_000, 5),
  ]
  for (points, stars) in thresholdCases {
    let score = DrumxRunScore(snapshot: scoreSnapshot(onTime: points), completedNaturally: true)
    check(score.points == Int(points) && score.stars == stars,
      "star threshold uses exact earned points at \(points)")
    check((0...1).contains(score.progressToNextStar), "star progress stays normalized")
  }
  let halfway = DrumxRunScore(snapshot: scoreSnapshot(onTime: 5000), completedNaturally: true)
  check(halfway.stars == 1 && halfway.nextStarPoints == 6000 && halfway.progressToNextStar == 0.5,
    "progress measures the interval between the current and next star")
  let threshold = DrumxRunScore(snapshot: scoreSnapshot(onTime: 6000), completedNaturally: true)
  check(threshold.nextStarPoints == 7500 && threshold.progressToNextStar == 0,
    "crossing a threshold starts progress toward the next star")
  let perfect = DrumxRunScore(snapshot: scoreSnapshot(onTime: 10_000), completedNaturally: true)
  check(perfect.isComplete && perfect.isPerfect && perfect.nextStarPoints == nil
    && perfect.progressToNextStar == 1, "five-star completion has no next threshold")

  let livePerfect = DrumxRunScore(
    snapshot: scoreSnapshot(onTime: 10_000, complete: false), completedNaturally: false)
  check(livePerfect.points == 9999 && livePerfect.stars == 4
    && !livePerfect.isComplete && !livePerfect.isPerfect, "all targets hit before the end cannot earn five stars yet")
  let wronglyFlagged = DrumxRunScore(
    snapshot: scoreSnapshot(onTime: 10_000, complete: false), completedNaturally: true)
  check(wronglyFlagged.points == 9999 && !wronglyFlagged.isComplete,
    "natural flag alone cannot complete an unfinished snapshot")
  let manualEnd = DrumxRunScore(snapshot: scoreSnapshot(onTime: 10_000), completedNaturally: false)
  check(manualEnd.points == 9999 && manualEnd.stars == 4 && !manualEnd.isPerfect,
    "a manually stopped take never receives the perfect completion star")
  let extra = DrumxRunScore(snapshot: scoreSnapshot(onTime: 100, expected: 100, extra: 1), completedNaturally: true)
  let late = DrumxRunScore(snapshot: scoreSnapshot(onTime: 99, expected: 100), completedNaturally: true)
  let missed = DrumxRunScore(snapshot: scoreSnapshot(onTime: 99, expected: 100, missed: 1), completedNaturally: true)
  check(extra.points == 9900 && extra.stars == 4 && !extra.isPerfect,
    "extra hit expands the denominator and prevents perfection")
  check(late.points == 9900 && missed.points == 9900,
    "outside-band hits and omissions cannot earn on-time points")
  let noHits = DrumxRunScore(snapshot: scoreSnapshot(onTime: 0, missed: 10_000), completedNaturally: true)
  check(noHits.points == 0 && noHits.stars == 0 && noHits.isComplete,
    "a naturally completed empty attempt earns no points")

  let take = TestTake()
  let empty = DrumxRunScore(snapshot: take.snapshot, completedNaturally: false)
  check(empty.points == 0 && empty.combo == 0, "live score begins at zero")
  _ = dx_core_input(take.core, 0, 0.01, 0.8)
  let firstHit = DrumxRunScore(snapshot: take.snapshot, completedNaturally: false)
  check(firstHit.points == 208 && firstHit.stars == 0 && firstHit.combo == 1,
    "first live hit earns one share of all 48 targets rather than a 100-percent score")
  dx_core_advance(take.core, 0.3)
  let afterMiss = DrumxRunScore(snapshot: take.snapshot, completedNaturally: false)
  check(afterMiss.points == firstHit.points, "expiring an omission earns no points")
  check(afterMiss.combo == Int(take.snapshot.total.streak)
    && afterMiss.bestCombo == Int(take.snapshot.total.best_streak), "combos reflect the core with no multiplier")

  let almost = DrumxRunScore(
    snapshot: scoreSnapshot(onTime: Int32.max - 1, expected: Int32.max), completedNaturally: true)
  check(almost.points == 9999 && almost.stars == 4 && !almost.isPerfect,
    "a percentage extremely close to 100 does not round up to five stars")
  for extraCount in [0, Int.max] {
    let onTime = extraCount == 0 ? Int.max - 1 : Int.max
    let denominator = Double(Int.max) + Double(extraCount)
    let attempt = LessonAttempt(
      id: UUID(), endedAt: Date(), settings: settings(), matched: Int.max, missed: 0,
      extra: extraCount, onTime: onTime, expected: Int.max,
      timingAccuracyPercent: Double(onTime) / denominator * 100,
      hitRatePercent: Double(Int.max) / denominator * 100,
      meanOffsetMS: 0, meanAbsoluteOffsetMS: 0, bestStreak: nil)
    let score = DrumxRunScore(attempt: attempt)
    check(score.points == (extraCount == 0 ? 9999 : 5000),
      "large persisted counters neither overflow nor lose floor precision")
  }
  var invalid = scoreSnapshot(onTime: 10_000)
  invalid.elapsed_seconds = .nan
  let invalidScore = DrumxRunScore(snapshot: invalid, completedNaturally: true)
  check(invalidScore.points == 0 && !invalidScore.isComplete, "invalid clock cannot award a completed score")
}

@main
enum DrumxLessonChecks {
  static func main() {
    let suite = "drumx.lesson-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    reviewChecks()
    historyChecks(defaults: defaults)
    runScoreChecks()
    print("Drumx lesson review/history: \(checks) checks passed.")
  }
}
