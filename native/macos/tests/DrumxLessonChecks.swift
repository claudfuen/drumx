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

private func sparseOneBarReviewChecks() {
  let exercises: [(String, Int32, [Double])] = [
    ("find-the-pulse", 1, [0, 1, 2, 3]),
    ("backbeat-rests", 1, [1, 3]),
    ("kick-pulse", 2, [0, 2]),
  ]
  for (lesson, pad, beats) in exercises {
    for offset in [0.01, -0.04] {
      let take = TestTake(tempo: 60, bars: 1)
      let chart = beats.map { DXChartEvent(pad: pad, beat: $0) }
      let loaded = chart.withUnsafeBufferPointer {
        dx_core_load_chart(take.core, 60, 4, $0.baseAddress, Int32($0.count))
      }
      check(loaded == 1, "\(lesson): sparse one-bar chart loads")
      take.play(offset: offset)
      let live = DrumxRunScore(snapshot: take.snapshot, completedNaturally: false)
      check(live.stars < 5 && !live.isComplete,
        "\(lesson): hitting every sparse target still requires completing the phrase")
      take.finish()
      let snapshot = take.snapshot
      let score = DrumxRunScore(snapshot: snapshot, completedNaturally: true)
      let review = LessonReview(snapshot: snapshot, completedNaturally: true)
      check(Int(snapshot.total.expected) == beats.count && snapshot.total.on_time == snapshot.total.expected,
        "\(lesson): every authored sparse target landed within the band")
      check(score.isPerfect && score.isComplete && score.stars == 5 && score.points == 10_000,
        "\(lesson): complete sparse timing success earns all five stars")
      check(review.headline == "The phrase stayed together" && review.detail.contains("Every note landed"),
        "\(lesson): complete sparse success receives positive measured-outcome coaching")
      check(review.suggestedPad == nil && !review.detail.contains("tended"),
        "\(lesson): sparse success does not invent a missing part or short-sample timing diagnosis")
      check(LessonReview(snapshot: snapshot, completedNaturally: false).headline == "Take stopped",
        "\(lesson): successful notes alone cannot promote a stopped take")
    }
  }

  let imperfect = TestTake(tempo: 60, bars: 1)
  let chart = [DXChartEvent(pad: 2, beat: 0), DXChartEvent(pad: 2, beat: 2)]
  check(chart.withUnsafeBufferPointer {
    dx_core_load_chart(imperfect.core, 60, 4, $0.baseAddress, Int32($0.count))
  } == 1, "sparse extra-hit comparison chart loads")
  imperfect.play(offset: 0.01)
  _ = dx_core_input(imperfect.core, 2, 0.02, 0.8)
  imperfect.finish()
  check(!DrumxRunScore(snapshot: imperfect.snapshot, completedNaturally: true).isPerfect,
    "an extra hit prevents sparse perfection")
  check(LessonReview(snapshot: imperfect.snapshot, completedNaturally: true).headline
    == "Build the pattern one part at a time", "sparse extras still receive practice guidance")
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

private func archiveHistoryChecks(defaults: UserDefaults) throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("drumx-history-checks-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let archiveURL = directory.appendingPathComponent("History/player-a.json")
  let base = settings()
  let date = Date(timeIntervalSince1970: 10_000)
  let full = TestTake()
  full.play(offset: 0.02)
  full.finish()
  let earlyBestID = UUID()
  let legacy = LessonHistory(defaults: defaults, key: "archive-legacy")
  check(legacy.record(id: earlyBestID, settings: base, snapshot: full.snapshot,
    completedNaturally: true, endedAt: date) != nil, "legacy best prepared for archive migration")
  let originalDefaults = defaults.data(forKey: "archive-legacy")!

  let history = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: archiveURL)
  check(history.lastError == nil && history.attempts == legacy.attempts,
    "absent archive seeds from retained legacy attempts")
  let migratedAttempts = try JSONDecoder().decode([LessonAttempt].self, from: Data(contentsOf: archiveURL))
  check(migratedAttempts == legacy.attempts,
    "legacy migration creates a readable archive immediately")
  check(defaults.data(forKey: "archive-legacy") == originalDefaults,
    "archive migration preserves original defaults bytes")

  let weaker = TestTake()
  weaker.play(offset: 0.06)
  weaker.finish()
  for index in 1...205 {
    check(history.record(id: UUID(), settings: base, snapshot: weaker.snapshot,
      completedNaturally: true, endedAt: date.addingTimeInterval(Double(index))) != nil,
      "every complete archived attempt reports a successful durable write")
  }
  check(history.attempts.count == 206 && history.best(matching: base)?.id == earlyBestID,
    "more than 200 new takes cannot evict an earlier archived personal best")
  check(history.recent(matching: base).count == 6
    && history.recent(matching: base, limit: Int.max).count == 200,
    "recent display remains bounded while the archive retains all attempts")
  let reopened = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: archiveURL)
  check(reopened.attempts == history.attempts && reopened.best(matching: base)?.id == earlyBestID,
    "full history and earliest personal best survive reopening")
  check(defaults.data(forKey: "archive-legacy") == originalDefaults,
    "archive recording never rewrites the migration source")

  let otherURL = directory.appendingPathComponent("History/player-b.json")
  let other = LessonHistory(defaults: defaults, key: "archive-other-player", archiveURL: otherURL)
  check(other.attempts.isEmpty && other.best(matching: base) == nil,
    "new player archive does not inherit another player's score history")
  let otherID = UUID()
  check(other.record(id: otherID, settings: base, snapshot: full.snapshot,
    completedNaturally: true, endedAt: date) != nil, "second player can save independently")
  check(LessonHistory(defaults: defaults, key: "archive-other-player", archiveURL: otherURL)
    .attempts.map(\.id) == [otherID], "second player's archive reopens independently")
  check(LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: archiveURL)
    .attempts == history.attempts, "second player recording leaves first player's archive unchanged")
  check(defaults.object(forKey: "archive-other-player") == nil,
    "archive-only player does not need a duplicate defaults history")

  let delayed = TestTake()
  delayed.finish()
  let delayedID = UUID(), delayedDate = date.addingTimeInterval(500)
  check(history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: delayedDate)?.missed == 48,
    "archive accepts naturally completed omissions before delayed input arrives")
  delayed.play(offset: 0.005)
  check(history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: delayedDate)?.matched == 48,
    "same UUID corrects archived omissions using preserved input timestamps")
  check(history.attempts.count == 207 && history.best(matching: base)?.id == delayedID,
    "upward archive correction updates rank without appending a duplicate take")
  _ = dx_core_input(delayed.core, 0, -0.08, 0.8)
  check(history.record(id: delayedID, settings: base, snapshot: delayed.snapshot,
    completedNaturally: true, endedAt: delayedDate)?.extra == 1,
    "downward archive correction retains the chronological duplicate strike")
  check(history.attempts.count == 207 && history.best(matching: base)?.id == earlyBestID,
    "downward correction restores the earlier personal best across all saved takes")
  check(LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: archiveURL)
    .attempts == history.attempts, "latest UUID correction persists across reopening")

  let beforePartial = try Data(contentsOf: archiveURL)
  let partial = TestTake()
  partial.play(include: { $0.id == 0 })
  check(history.record(id: UUID(), settings: base, snapshot: partial.snapshot,
    completedNaturally: false) == nil, "live or partial take does not enter the archive")
  let afterPartial = try Data(contentsOf: archiveURL)
  check(afterPartial == beforePartial,
    "an unfinished live snapshot leaves archive bytes untouched")

  // Once present, the archive is authoritative even if legacy defaults change.
  defaults.set(Data("changed legacy value".utf8), forKey: "archive-legacy")
  let preferred = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: archiveURL)
  check(preferred.lastError == nil && preferred.attempts == history.attempts,
    "existing valid archive is preferred over an unreadable legacy source")
  defaults.set(originalDefaults, forKey: "archive-legacy")

  let corruptURL = directory.appendingPathComponent("History/corrupt.json")
  let corruptBytes = Data("{ damaged archive".utf8)
  try corruptBytes.write(to: corruptURL)
  let corrupt = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: corruptURL)
  check(corrupt.attempts.isEmpty && corrupt.lastError != nil,
    "corrupt existing archive fails closed instead of silently falling back to legacy history")
  check(corrupt.record(id: UUID(), settings: base, snapshot: full.snapshot,
    completedNaturally: true) == nil && corrupt.lastError != nil,
    "corrupt archive blocks new writes until explicit recovery")
  let preservedCorruptBytes = try Data(contentsOf: corruptURL)
  check(preservedCorruptBytes == corruptBytes,
    "failed load and attempted record preserve the exact corrupt file")
  check(defaults.data(forKey: "archive-legacy") == originalDefaults,
    "corrupt archive handling preserves the legacy source too")

  var mixedObjects = try JSONSerialization.jsonObject(with: originalDefaults) as! [[String: Any]]
  var invalidObject = mixedObjects[0]
  invalidObject["id"] = UUID().uuidString
  invalidObject["matched"] = 500
  mixedObjects.append(invalidObject)
  let invalidBytes = try JSONSerialization.data(withJSONObject: mixedObjects)
  let invalidURL = directory.appendingPathComponent("History/invalid-record.json")
  try invalidBytes.write(to: invalidURL)
  let invalidArchive = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: invalidURL)
  check(invalidArchive.attempts.isEmpty && invalidArchive.lastError != nil,
    "one invalid record blocks the entire existing archive instead of silently dropping evidence")
  check(invalidArchive.record(id: UUID(), settings: base, snapshot: full.snapshot,
    completedNaturally: true) == nil, "semantically invalid archive rejects later writes")
  let preservedInvalidBytes = try Data(contentsOf: invalidURL)
  check(preservedInvalidBytes == invalidBytes, "invalid record leaves the complete original archive intact")
  defaults.set(invalidBytes, forKey: "archive-legacy-filter")
  check(LessonHistory(defaults: defaults, key: "archive-legacy-filter").attempts.count == 1,
    "defaults-only decoding retains its prior invalid-record filtering behavior")

  let writableParent = directory.appendingPathComponent("write-failure", isDirectory: true)
  let writableURL = writableParent.appendingPathComponent("history.json")
  let unwritable = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: writableURL)
  let priorAttempts = unwritable.attempts
  let priorBytes = try Data(contentsOf: writableURL)
  let preservedParent = directory.appendingPathComponent("preserved-history", isDirectory: true)
  try FileManager.default.moveItem(at: writableParent, to: preservedParent)
  let blocker = Data("a file cannot be an archive directory".utf8)
  try blocker.write(to: writableParent)
  check(unwritable.record(id: UUID(), settings: base, snapshot: full.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(1000)) == nil,
    "blocked parent makes an atomic archive write fail")
  check(unwritable.lastError != nil && unwritable.attempts == priorAttempts,
    "failed archive write neither claims success nor publishes an unsaved take")
  let preservedBlocker = try Data(contentsOf: writableParent)
  check(preservedBlocker == blocker,
    "archive write failure does not replace the blocking file")
  let preservedArchive = try Data(contentsOf: preservedParent.appendingPathComponent("history.json"))
  check(preservedArchive == priorBytes,
    "prior durable archive remains unchanged after failed write")
  check(defaults.data(forKey: "archive-legacy") == originalDefaults,
    "failed archive write does not use legacy defaults as an unnoticed fallback")
  let blockedAtOpen = LessonHistory(defaults: defaults, key: "archive-legacy", archiveURL: writableURL)
  check(blockedAtOpen.lastError != nil && blockedAtOpen.attempts.isEmpty,
    "existing non-directory parent is not mistaken for an absent archive eligible for migration")
  check(blockedAtOpen.record(id: UUID(), settings: base, snapshot: full.snapshot,
    completedNaturally: true) == nil, "blocked archive location cannot report a saved take")
}

private func pendingSaveChecks(defaults: UserDefaults) throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("drumx-pending-checks-\(UUID().uuidString)", isDirectory: true)
  let parent = directory.appendingPathComponent("active", isDirectory: true)
  let preserved = directory.appendingPathComponent("preserved", isDirectory: true)
  let archive = parent.appendingPathComponent("history.json")
  defer { try? FileManager.default.removeItem(at: directory) }
  let history = LessonHistory(defaults: defaults, key: "pending-history", archiveURL: archive)
  check(!history.hasPendingSaves && history.pendingSaveCount == 0 && history.retryPendingSaves(),
    "an unused archive does not invent unsaved results or a quit warning")
  let base = settings(), date = Date(timeIntervalSince1970: 30_000)
  let baseline = TestTake(); baseline.finish()
  let baselineID = UUID()
  check(history.record(id: baselineID, settings: base, snapshot: baseline.snapshot,
    completedNaturally: true, endedAt: date) != nil, "pending fixture starts with a durable baseline")
  let original = try Data(contentsOf: archive)
  try FileManager.default.moveItem(at: parent, to: preserved)
  let blocker = Data("blocked path".utf8); try blocker.write(to: parent)
  let first = TestTake(); first.play(); first.finish()
  let firstID = UUID(), secondID = UUID()
  check(history.record(id: firstID, settings: base, snapshot: first.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(1)) == nil,
    "a write failure does not report a durable complete take")
  check(history.hasPendingSave(id: firstID) && history.pendingSaveCount == 1,
    "the immutable completed result remains queued independently of its transport")
  check(history.attempts.map(\.id) == [baselineID] && history.best(matching: base)?.id == baselineID,
    "a queued perfect take does not manufacture a saved personal best")
  check(!history.retryPendingSaves() && history.pendingSaveCount == 1,
    "failed retries retain the exact pending result")
  _ = dx_core_input(first.core, 0, -0.08, 0.8)
  check(history.record(id: firstID, settings: base, snapshot: first.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(99)) == nil && history.pendingSaveCount == 1,
    "a same-ID late correction replaces the queued value without duplicating a take")
  check(history.record(id: firstID, settings: settings(offset: 10), snapshot: first.snapshot,
    completedNaturally: true) == nil && history.pendingSaveCount == 1,
    "a correction cannot move queued evidence into a different condition group")
  let second = TestTake(); second.play(offset: 0.02); second.finish()
  check(history.record(id: secondID, settings: base, snapshot: second.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(2)) == nil && history.pendingSaveCount == 2,
    "starting and completing another transport does not replace the first unsaved result")
  let partial = TestTake()
  check(history.record(id: UUID(), settings: base, snapshot: partial.snapshot,
    completedNaturally: false) == nil && history.pendingSaveCount == 2,
    "stopped or partial work does not enter the recovery queue")
  check(history.attempts.count == 1 && history.recent(matching: base).count == 1,
    "all ranked and recent evidence stays committed-only during a failed batch")
  let durableDuringFailure = try Data(contentsOf: preserved.appendingPathComponent("history.json"))
  let blockingBytes = try Data(contentsOf: parent)
  check(durableDuringFailure == original && blockingBytes == blocker,
    "retries preserve both prior archive bytes and the unrelated blocking file")
  try FileManager.default.removeItem(at: parent)
  try FileManager.default.moveItem(at: preserved, to: parent)
  check(history.retryPendingSaves() && !history.hasPendingSaves && history.pendingSaveCount == 0,
    "restoring storage atomically publishes the entire queued batch")
  check(history.attempts.map(\.id) == [baselineID, firstID, secondID],
    "recovered corrections retain their original chronological position")
  check(history.attempts.first(where: { $0.id == firstID })?.extra == 1,
    "recovery saves the latest corrected counters for the original UUID")
  check(history.best(matching: base)?.id == secondID && history.lastError == nil,
    "personal best and error status change only after durable recovery")
  check(LessonHistory(defaults: defaults, key: "pending-history", archiveURL: archive).attempts == history.attempts,
    "a new process view reads every recovered result with no duplicates")
  check(defaults.object(forKey: "pending-history") == nil,
    "recovery never hides a write failure by falling back to defaults")

  // A correction to an already saved take is held separately too.
  try FileManager.default.moveItem(at: parent, to: preserved); try blocker.write(to: parent)
  _ = dx_core_input(second.core, 0, -0.08, 0.8)
  check(history.record(id: secondID, settings: base, snapshot: second.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(200)) == nil && history.pendingSaveCount == 1,
    "a failed correction to an existing UUID becomes recoverable without appending a record")
  check(history.attempts.first(where: { $0.id == secondID })?.extra == 0,
    "a failed correction does not publish counters that were not saved")
  try FileManager.default.removeItem(at: parent); try FileManager.default.moveItem(at: preserved, to: parent)
  check(history.retryPendingSaves() && history.attempts.count == 3,
    "retry replaces the committed UUID atomically without duplication")
  check(history.attempts.first(where: { $0.id == secondID })?.extra == 1
    && history.attempts.last?.endedAt == date.addingTimeInterval(2),
    "corrected saved counters retain the attempt's original end time")

  let corruptURL = directory.appendingPathComponent("corrupt.json")
  let corruptBytes = Data("unreadable but retained".utf8); try corruptBytes.write(to: corruptURL)
  let blocked = LessonHistory(defaults: defaults, key: "pending-corrupt", archiveURL: corruptURL)
  check(!blocked.hasPendingSaves, "a load error alone is not an unsaved result")
  let recoveredID = UUID()
  check(blocked.record(id: recoveredID, settings: base, snapshot: second.snapshot,
    completedNaturally: true, endedAt: date.addingTimeInterval(3)) == nil && blocked.hasPendingSaves,
    "completed work remains recoverable even when the archive was blocked at open")
  check(!blocked.retryPendingSaves() && blocked.attempts.isEmpty,
    "retry does not replace an unreadable archive with an empty history")
  let unchanged = try Data(contentsOf: corruptURL)
  check(unchanged == corruptBytes, "blocked retries preserve the original unreadable bytes")
  try original.write(to: corruptURL, options: .atomic)
  check(blocked.retryPendingSaves() && blocked.attempts.map(\.id) == [baselineID, recoveredID],
    "explicit restoration of a valid archive recovers old and newly queued work together")
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
  static func main() throws {
    let suite = "drumx.lesson-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    reviewChecks()
    sparseOneBarReviewChecks()
    historyChecks(defaults: defaults)
    try archiveHistoryChecks(defaults: defaults)
    try pendingSaveChecks(defaults: defaults)
    runScoreChecks()
    print("Drumx lesson review/history: \(checks) checks passed.")
  }
}
