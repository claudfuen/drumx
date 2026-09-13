import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private let course = DrumxCourse.lessons
private let mapping = [[42, 44, 46], [38, 40], [35, 36]]

private func attempt(_ lesson: DrumxLessonDefinition, bars: Int = 4, matched: Int? = nil,
                     extra: Int = 0, onTime: Int = 0, mode: Int = 0, live: Bool = true,
                     version: String? = nil, expected: Int? = nil, missed: Int? = nil,
                     tempo: Double = 60, hitRate: Double? = nil, endedAt: Date = Date()) -> LessonAttempt {
  let expected = expected ?? lesson.events.count * bars
  let matched = matched ?? expected
  let denominator = Double(expected) + Double(extra)
  return LessonAttempt(id: UUID(), endedAt: endedAt,
    settings: TakeSettings(tempo: tempo, mode: mode, liveFeedback: live, bars: bars,
      calibrationMS: 0, inputIdentity: "keyboard", mapping: mapping,
      lessonVersion: version ?? lesson.version),
    matched: matched, missed: missed ?? expected - matched, extra: extra, onTime: onTime,
    expected: expected, timingAccuracyPercent: Double(onTime) / denominator * 100,
    hitRatePercent: hitRate ?? Double(matched) / denominator * 100,
    meanOffsetMS: matched > 0 ? 80 : nil, meanAbsoluteOffsetMS: matched > 0 ? 80 : nil,
    bestStreak: onTime)
}

private func readyAttempt(_ lesson: DrumxLessonDefinition, counts: [Int]? = nil,
                          matches: [Int]? = nil, onTimes: [Int]? = nil,
                          extra: Int = 0, bpm: Double? = nil, mode: Int = 0,
                          bars: Int = 16, input: String = "keyboard", handHints: Bool = true,
                          offset: Double = 0, monitoring: Bool = false, map: [[Int]]? = nil, date: Double = 0) -> LessonAttempt {
  let expectedPads = counts ?? (0..<3).map { pad in lesson.events.filter({ $0.pad == pad }).count * bars }
  let matches = matches ?? expectedPads
  let onTimes = onTimes ?? matches
  let pads = (0..<3).map { pad in
    LessonPadEvidence(expected: expectedPads[pad], matched: matches[pad],
      missed: expectedPads[pad] - matches[pad], extra: pad == 0 ? extra : 0, onTime: onTimes[pad])
  }
  let expected = expectedPads.reduce(0, +), matched = matches.reduce(0, +), onTime = onTimes.reduce(0, +)
  let denominator = Double(expected + extra)
  return LessonAttempt(id: UUID(), endedAt: Date(timeIntervalSinceReferenceDate: date),
    settings: TakeSettings(tempo: bpm ?? lesson.suggestedBPM, mode: mode, liveFeedback: mode != 2,
      bars: bars, calibrationMS: offset, inputIdentity: input, mapping: map ?? mapping,
      lessonVersion: lesson.version, handHints: handHints, monitoring: monitoring, readinessPolicyVersion: 1),
    matched: matched, missed: expected - matched, extra: extra, onTime: onTime, expected: expected,
    timingAccuracyPercent: Double(onTime) / denominator * 100,
    hitRatePercent: Double(matched) / denominator * 100,
    meanOffsetMS: matched > 0 ? 0 : nil, meanAbsoluteOffsetMS: matched > 0 ? 0 : nil,
    bestStreak: onTime, pads: pads)
}

private func readinessChecks(defaults: UserDefaults) {
  let lesson = course[6]
  let good = readyAttempt(lesson, date: 1), good2 = readyAttempt(lesson, date: 2)
  func status(_ rows: [LessonAttempt]) -> DrumxUnlocks.ReadinessStatus {
    DrumxUnlocks.readinessStatus(lesson: lesson, history: rows)
  }
  check(!status([good]).checkpoint && status([good]).passing == 1, "one steady take is useful evidence but not a checkpoint")
  check(!status([good, good]).checkpoint, "the same take identity cannot supply both successes")
  check(status([good, good2]).checkpoint, "two comparable guided takes earn repeatability")
  let boundary = readyAttempt(lesson, matches: [128, 32, 26], onTimes: [128, 32, 23], extra: 19)
  check(status([boundary, readyAttempt(lesson, matches: [128, 32, 26], onTimes: [128, 32, 23], extra: 19)]).checkpoint,
        "rounded-up per-pad thresholds and floored ten-percent extras qualify at the boundary")
  let noKick = readyAttempt(lesson, matches: [128, 32, 0], date: 3)
  check(Double(noKick.matched) / Double(noKick.expected) > 0.8, "missing every kick still exceeds the old aggregate threshold")
  check(!status([noKick, readyAttempt(lesson, matches: [128, 32, 0], date: 4)]).checkpoint,
        "hat density cannot conceal a completely missing kick")
  check(status([good, noKick, good2]).checkpoint, "two steady takes within a comparable three-window qualify")
  check(status([good, good2, noKick, readyAttempt(lesson, matches: [128, 32, 0], date: 4)]).checkpoint,
        "later difficult practice does not erase an earned checkpoint")
  check(!status([good, noKick, readyAttempt(lesson, matches: [128, 32, 0], date: 4), readyAttempt(lesson, date: 5)]).checkpoint,
        "two successes separated outside every three-window do not pool")
  for bad in [readyAttempt(lesson, bpm: 60), readyAttempt(lesson, mode: 1),
              readyAttempt(lesson, mode: 2), readyAttempt(lesson, bars: 4),
              readyAttempt(lesson, extra: 20), readyAttempt(lesson, onTimes: [128, 32, 22]),
              readyAttempt(lesson, matches: [128, 32, 25]),
              readyAttempt(lesson, counts: [160, 16, 16])] {
    check(!status([bad, bad]).checkpoint, "wrong tempo, guidance, phrase, extras, per-pad threshold or chart allocation cannot qualify")
  }
  check(!status([good, readyAttempt(lesson, input: "different-kit")]).checkpoint,
        "different input conditions cannot pool checkpoint evidence")
  check(!status([good, readyAttempt(lesson, handHints: false)]).checkpoint,
        "changed hand hints create a different comparison group")
  check(!status([good, readyAttempt(lesson, offset: 0.25)]).checkpoint,
        "fractional calibration remains a distinct captured condition")
  check(!status([good, readyAttempt(lesson, monitoring: true)]).checkpoint,
        "monitoring routes cannot pool checkpoint evidence")
  check(status([good, readyAttempt(lesson, map: mapping.map { $0.reversed() })]).checkpoint,
        "alias ordering does not alter a mapping's meaning")
  var corrupt = good
  corrupt.pads = [LessonPadEvidence(expected: 128, matched: 128, missed: 0, extra: 1, onTime: 128)] + Array(good.pads!.dropFirst())
  check(!DrumxRunScore(attempt: corrupt).isComplete && !status([corrupt, corrupt]).checkpoint,
        "per-pad totals inconsistent with aggregate are not valid archived evidence")
  var missing = good; missing.pads = nil
  check(!DrumxRunScore(attempt: missing).isComplete, "new-policy archive cannot omit its per-pad evidence")
  let roundTrip = try! JSONDecoder().decode(LessonAttempt.self, from: JSONEncoder().encode(good))
  check(roundTrip == good, "new optional per-pad evidence round-trips losslessly")
  let legacy = attempt(lesson)
  let oldRoundTrip = try! JSONDecoder().decode(LessonAttempt.self, from: JSONEncoder().encode(legacy))
  check(oldRoundTrip.pads == nil && oldRoundTrip.settings.readinessPolicyVersion == nil,
        "legacy archive does not acquire new policy or invented instrument evidence")
  let progress = fresh(defaults)
  check(DrumxUnlocks.migrateLegacyAccess(course: course, history: [legacy], progress: progress),
        "legacy access is frozen before new practice")
  let preserved = DrumxUnlocks.evaluate(course: course, history: [legacy], progress: progress)
  check(preserved.availableIDs.contains(course[7].id) && preserved.clearedIDs.isEmpty,
        "old aggregate completion preserves reached access without new checkpoint")
  _ = progress.updateResume(PracticeResume(lessonID: course.last!.id))
  _ = progress.markPracticeCompleted(lessonID: course.last!.id, version: course.last!.version, recall: false)
  let later = DrumxUnlocks.evaluate(course: course, history: [legacy, readyAttempt(course.last!)], progress: progress)
  check(!later.availableIDs.contains(course.last!.id), "new sandbox resume and practice flags cannot increase frozen legacy access")
  for lesson in course.dropFirst() {
    check(DrumxUnlocks.readinessStatus(lesson: lesson,
      history: [readyAttempt(lesson), readyAttempt(lesson, date: 1)]).checkpoint,
      "every authored non-pulse lesson can earn its own instrument checkpoint")
  }
}

private func fresh(_ defaults: UserDefaults) -> DrumxProgress {
  DrumxProgress(defaults: defaults, storageKey: "unlocks.\(UUID().uuidString)")
}

private func thresholdChecks(defaults: UserDefaults) {
  let progress = fresh(defaults)
  let first = course[0], second = course[1]
  let initial = DrumxUnlocks.evaluate(course: course, history: [], progress: progress)
  check(initial.availableIDs == [first.id] && initial.clearedIDs.isEmpty, "new player begins with exactly the first lesson")
  check(initial.recommendedID == first.id && initial.nextRequiredAction.contains("72 BPM"), "new player receives an actionable pattern goal")
  check(initial.reasonByID[second.id]?.contains(first.title) == true, "locked next lesson names its prerequisite")
  check(initial.practisedIDs.isEmpty && initial.readingIDs.isEmpty && initial.recallIDs.isEmpty, "fresh profile has no achievements")

  // Five bars of four quarter notes make an exact integer 80% boundary.
  let below = DrumxUnlocks.evaluate(course: course, history: [attempt(first, bars: 5, matched: 15)], progress: progress)
  check(!below.clearedIDs.contains(first.id) && !below.availableIDs.contains(second.id), "75% does not clear an 80% goal")
  let exact = DrumxUnlocks.evaluate(course: course, history: [attempt(first, bars: 5, matched: 16)], progress: progress)
  check(exact.clearedIDs.isEmpty && exact.availableIDs == [first.id, second.id], "legacy 80% preserves next access without earning the new checkpoint")
  check(exact.readingIDs.isEmpty, "within-chapter unlock does not manufacture or require reading evidence")
  check(exact.recommendedID == second.id, "next unlocked lesson is recommended")
  let minimum = DrumxUnlocks.evaluate(course: course, history: [attempt(first, matched: 13)], progress: progress)
  check(minimum.clearedIDs.isEmpty && minimum.availableIDs.contains(second.id), "legacy 13 of 16 preserves previously earned access")
  let tooFew = DrumxUnlocks.evaluate(course: course, history: [attempt(first, matched: 12)], progress: progress)
  check(!tooFew.clearedIDs.contains(first.id), "12 of 16 remains below the threshold")
  let short = DrumxUnlocks.evaluate(course: course, history: [attempt(first, bars: 3)], progress: progress)
  check(short.practisedIDs.contains(first.id) && !short.clearedIDs.contains(first.id), "three bars count as practice but cannot clear")
  let looseTiming = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, bars: 5, matched: 16, extra: 30, onTime: 0)], progress: progress)
  check(looseTiming.clearedIDs.isEmpty && looseTiming.availableIDs.contains(second.id), "legacy access keeps its old coverage rule without a new tempo achievement")
  let assisted = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, tempo: 30)], progress: progress)
  check(assisted.clearedIDs.isEmpty && assisted.availableIDs.contains(second.id), "legacy slow practice keeps prior access")
  let memoryLive = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, mode: 2, live: true)], progress: progress)
  check(memoryLive.availableIDs.contains(second.id) && memoryLive.clearedIDs.isEmpty && memoryLive.recallIDs.isEmpty,
        "legacy memory with live feedback preserves access but is not click-only evidence")
  let clickOnly = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, mode: 2, live: false)], progress: progress)
  check(clickOnly.recallIDs.contains(first.id), "archived click-only conditions are tracked separately")

  for bad in [attempt(first, missed: 1), attempt(first, expected: 3),
              attempt(first, tempo: .nan), attempt(first, hitRate: 0),
              attempt(first, endedAt: Date(timeIntervalSinceReferenceDate: .infinity))] {
    let state = DrumxUnlocks.evaluate(course: course, history: [bad], progress: progress)
    check(state.clearedIDs.isEmpty && state.practisedIDs.isEmpty, "malformed archive values cannot clear or award practice")
    check(state.availableIDs == [first.id], "malformed records cannot extend access")
  }
  let zero = DrumxUnlocks.evaluate(course: course, history: [attempt(course[8], matched: 0)], progress: progress)
  check(zero.availableIDs == [first.id] && zero.practisedIDs.isEmpty, "no-hit archive alone cannot invent prior practice access")
}

private func chapterAndMigrationChecks(defaults: UserDefaults) {
  let progress = fresh(defaults)
  var history = [attempt(course[0])] + course[1..<4].flatMap { [readyAttempt($0), readyAttempt($0, date: 1)] }
  var state = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(state.availableIDs == Set(course.prefix(4).map(\.id)), "chapter boundary remains locked after pattern completion alone")
  check(state.reasonByID[course[4].id]?.contains("reading check") == true,
        "chapter lock explains reading requirement")
  check(state.recommendedID == course[3].id && state.nextRequiredAction.contains("reading check"),
        "boundary recommendation returns to the required reading action")
  _ = progress.markTechniqueChecked(lessonID: course[3].id, version: course[3].version)
  state = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(!state.availableIDs.contains(course[4].id), "technique self-check cannot substitute for reading")
  _ = progress.markReadingChecked(lessonID: course[3].id, version: "old-version")
  state = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(!state.availableIDs.contains(course[4].id), "old-version reading cannot satisfy current chapter gate")
  _ = progress.markReadingChecked(lessonID: course[3].id, version: course[3].version)
  state = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(state.availableIDs.contains(course[4].id) && !state.availableIDs.contains(course[5].id),
        "current reading unlocks exactly the next lesson")
  _ = progress.updateResume(PracticeResume(lessonID: course[4].id, lessonVersion: course[4].version))
  state = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(!state.availableIDs.contains(course[5].id), "selecting a newly unlocked lesson cannot leapfrog its goal")
  history += [readyAttempt(course[4]), readyAttempt(course[4], date: 1)]
  state = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(state.availableIDs.contains(course[5].id), "its own valid take unlocks the following lesson")

  let durable = fresh(defaults)
  _ = durable.markPracticeCompleted(lessonID: course[8].id, version: "earlier-version", recall: true)
  let preserved = DrumxUnlocks.evaluate(course: course, history: [], progress: durable)
  check(preserved.availableIDs == Set(course.prefix(9).map(\.id)), "durable prior-version practice preserves reached access and earlier lessons")
  check(preserved.clearedIDs.isEmpty && preserved.practisedIDs.isEmpty && preserved.recallIDs.isEmpty,
        "older-version access is distinct from current-version achievements")
  check(!preserved.availableIDs.contains(course[9].id), "preserved access does not clear its frontier prerequisite")

  let archived = fresh(defaults)
  let oneBar = DrumxUnlocks.evaluate(course: course, history: [attempt(course[6], bars: 1, matched: 1)], progress: archived)
  check(oneBar.availableIDs == Set(course.prefix(7).map(\.id)), "existing low-score short practice retains access without new threshold regression")
  check(oneBar.clearedIDs.isEmpty && oneBar.practisedIDs == [course[6].id], "archive access preservation does not fabricate cleared work")
  let older = DrumxUnlocks.evaluate(course: course,
    history: [attempt(course[6], version: course[6].id + "-v0")], progress: archived)
  check(older.availableIDs == Set(course.prefix(7).map(\.id)) && older.clearedIDs.isEmpty,
        "exact numeric prior-version namespace preserves access but cannot clear")
  let wrong = DrumxUnlocks.evaluate(course: course,
    history: [attempt(course[6], version: course[6].id + "-v1-unrelated")], progress: archived)
  check(wrong.availableIDs == [course[0].id] && wrong.clearedIDs.isEmpty,
        "fuzzy version prefix cannot transfer an unrelated archive")

  let saved = fresh(defaults)
  _ = saved.updateResume(PracticeResume(lessonID: course[10].id, lessonVersion: "prior-revision"))
  let resumed = DrumxUnlocks.evaluate(course: course, history: [], progress: saved)
  check(resumed.availableIDs == Set(course.prefix(11).map(\.id)), "saved current lesson remains accessible across revision changes")
  check(resumed.clearedIDs.isEmpty && !resumed.availableIDs.contains(course[11].id),
        "saved selection preserves access without clearing or advancing beyond it")
  _ = saved.addProfile(name: "New Player")
  let newPlayer = DrumxUnlocks.evaluate(course: course, history: [], progress: saved)
  check(newPlayer.availableIDs == [course[0].id] && newPlayer.clearedIDs.isEmpty,
        "new player's empty archive and evidence begin independently")
}

private func archiveAdmissionChecks(defaults: UserDefaults) {
  let progress = fresh(defaults)
  let history = LessonHistory(defaults: defaults, key: "unlock-admission")
  let core = dx_core_create()!
  defer { dx_core_destroy(core) }
  let lesson = course[0]
  let chart = (0..<4).flatMap { bar in
    lesson.events.map { DXChartEvent(pad: Int32($0.pad), beat: Double(bar * 4) + $0.beat) }
  }
  let loaded = chart.withUnsafeBufferPointer { dx_core_load_chart(core, 60, 16, $0.baseAddress, Int32($0.count)) }
  check(loaded == 1, "admission fixture loads real authored four-bar chart")
  var snapshot = DXSnapshot()
  for index in 0..<dx_core_event_count(core) {
    var event = DXEvent()
    _ = dx_core_event(core, index, &event)
    if index < 13 { _ = dx_core_input(core, event.pad, event.time_seconds + 0.08, 0.8) }
  }
  dx_core_finish(core, 12.1)
  dx_core_snapshot(core, &snapshot)
  let settings = TakeSettings(tempo: 60, mode: 0, liveFeedback: true, bars: 4,
    calibrationMS: 0, inputIdentity: "keyboard", mapping: mapping, lessonVersion: lesson.version)
  check(history.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: false) == nil,
        "stopped take is not admitted to progression archive")
  check(history.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: true) == nil,
        "natural flag cannot admit a structurally partial take")
  let partial = DrumxUnlocks.evaluate(course: course, history: history.attempts, progress: progress)
  check(partial.clearedIDs.isEmpty && partial.availableIDs == [lesson.id], "partial take never reaches unlock evaluation")
  let demoLoaded = chart.withUnsafeBufferPointer { dx_core_load_chart(core, 60, 16, $0.baseAddress, Int32($0.count)) }
  check(demoLoaded == 1, "demonstration admission fixture resets the full chart")
  dx_core_advance(core, 16)
  dx_core_snapshot(core, &snapshot)
  check(snapshot.finished != 0 && snapshot.elapsed_seconds >= snapshot.duration_seconds,
        "demonstration exclusion is tested against a fully completed snapshot")
  check(history.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: false) == nil,
        "unscored demonstration policy cannot archive even a completed snapshot")
  check(DrumxUnlocks.evaluate(course: course, history: history.attempts, progress: progress).clearedIDs.isEmpty,
        "demonstration has no archived attempt to unlock from")

  _ = chart.withUnsafeBufferPointer { dx_core_load_chart(core, 60, 16, $0.baseAddress, Int32($0.count)) }
  for index in 0..<13 {
    var event = DXEvent()
    _ = dx_core_event(core, Int32(index), &event)
    _ = dx_core_input(core, event.pad, event.time_seconds + 0.08, 0.8)
  }
  dx_core_advance(core, 16)
  dx_core_snapshot(core, &snapshot)
  check(history.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: true) != nil,
        "real naturally completed take is admitted to the archive")
  let complete = DrumxUnlocks.evaluate(course: course, history: history.attempts, progress: progress)
  check(complete.clearedIDs.isEmpty && complete.availableIDs.contains(course[1].id),
        "real legacy archive preserves next access without earning the new pulse checkpoint")
}

private func readinessArchiveChecks(defaults: UserDefaults) throws {
  let lesson = course[6]
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drumx-readiness-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let archive = directory.appendingPathComponent("history.json")
  try Data("original unreadable archive".utf8).write(to: archive)
  let history = LessonHistory(defaults: defaults, key: "readiness-pending", archiveURL: archive)
  let core = dx_core_create()!
  defer { dx_core_destroy(core) }
  let chart = (0..<16).flatMap { bar in
    lesson.events.map { DXChartEvent(pad: Int32($0.pad), beat: Double(bar * 4) + $0.beat) }
  }
  check(chart.withUnsafeBufferPointer { dx_core_load_chart(core, lesson.suggestedBPM, 64, $0.baseAddress, Int32($0.count)) } == 1,
        "readiness archive fixture uses the complete native authored chart")
  for index in 0..<dx_core_event_count(core) {
    var event = DXEvent(); _ = dx_core_event(core, index, &event)
    _ = dx_core_input(core, event.pad, event.time_seconds, 0.8)
  }
  dx_core_advance(core, 64 * 60 / lesson.suggestedBPM)
  var snapshot = DXSnapshot(); dx_core_snapshot(core, &snapshot)
  let settings = readyAttempt(lesson).settings
  check(history.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: true) == nil,
        "unreadable archive retains the first new-policy take without publishing it")
  check(history.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: true) == nil,
        "a second completed take also waits for durable persistence")
  check(history.pendingSaveCount == 2 && !DrumxUnlocks.readinessStatus(lesson: lesson, history: history.attempts).checkpoint,
        "pending native takes never award a readiness checkpoint")
  try Data("[]".utf8).write(to: archive, options: .atomic)
  check(history.retryPendingSaves() && history.attempts.count == 2,
        "restored native archive publishes both waiting completed takes together")
  check(history.attempts.allSatisfy { $0.pads?.map(\.expected) == [128, 32, 32] && $0.pads?.map(\.onTime) == [128, 32, 32] },
        "native archive stores the real DXSnapshot instrument totals")
  let reopened = LessonHistory(defaults: defaults, key: "readiness-pending", archiveURL: archive)
  check(reopened.lastError == nil && DrumxUnlocks.readinessStatus(lesson: lesson, history: reopened.attempts).checkpoint,
        "native readiness evidence survives actual archive reopen")
  snapshot.pads.2.expected += 1
  check(reopened.record(id: UUID(), settings: settings, snapshot: snapshot, completedNaturally: true) == nil,
        "inconsistent snapshot instrument totals cannot enter the archive")
}

private func completeSequenceChecks(defaults: UserDefaults) {
  let progress = fresh(defaults)
  var history: [LessonAttempt] = []
  for (index, lesson) in course.enumerated() {
    let before = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
    check(before.availableIDs.contains(lesson.id) && before.recommendedID == lesson.id,
          "lesson \(index + 1) is the sequential recommendation before its take")
    history += index == 0 ? [attempt(lesson)] : [readyAttempt(lesson), readyAttempt(lesson, date: 1)]
    var after = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
    check(index == 0 ? !after.clearedIDs.contains(lesson.id) : after.clearedIDs.contains(lesson.id), "legacy pulse retains access; later lessons clear on their own authored charts")
    if index + 1 < course.count {
      let next = course[index + 1]
      if next.chapter != lesson.chapter {
        check(!after.availableIDs.contains(next.id), "each chapter boundary needs predecessor reading")
        _ = progress.markReadingChecked(lessonID: lesson.id, version: lesson.version)
        after = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
      }
      check(after.availableIDs.contains(next.id), "lesson \(index + 2) becomes available after its own prerequisites")
      if index + 2 < course.count {
        check(!after.availableIDs.contains(course[index + 2].id), "one cleared lesson never leapfrogs a later lesson")
      }
    }
  }
  let end = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
  check(end.availableIDs == Set(course.map(\.id)) && end.clearedIDs == Set(course.dropFirst().map(\.id)),
        "complete course sequence preserves all available pattern goals")
  check(end.recallIDs.isEmpty, "finishing the course never fabricates a memory achievement")
}

@main
enum DrumxUnlockChecks {
  static func main() throws {
    let suite = "drumx.unlock-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    readinessChecks(defaults: defaults)
    thresholdChecks(defaults: defaults)
    chapterAndMigrationChecks(defaults: defaults)
    archiveAdmissionChecks(defaults: defaults)
    try readinessArchiveChecks(defaults: defaults)
    completeSequenceChecks(defaults: defaults)
    check(DrumxUnlocks.evaluate(course: [], history: [], progress: fresh(defaults)).availableIDs.isEmpty,
          "empty course produces no invented lesson")
    print("Drumx beginner unlocks: \(checks) checks passed.")
  }
}
