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

private func fresh(_ defaults: UserDefaults) -> DrumxProgress {
  DrumxProgress(defaults: defaults, storageKey: "unlocks.\(UUID().uuidString)")
}

private func thresholdChecks(defaults: UserDefaults) {
  let progress = fresh(defaults)
  let first = course[0], second = course[1]
  let initial = DrumxUnlocks.evaluate(course: course, history: [], progress: progress)
  check(initial.availableIDs == [first.id] && initial.clearedIDs.isEmpty, "new player begins with exactly the first lesson")
  check(initial.recommendedID == first.id && initial.nextRequiredAction.contains("80%"), "new player receives an actionable pattern goal")
  check(initial.reasonByID[second.id]?.contains(first.title) == true, "locked next lesson names its prerequisite")
  check(initial.practisedIDs.isEmpty && initial.readingIDs.isEmpty && initial.recallIDs.isEmpty, "fresh profile has no achievements")

  // Five bars of four quarter notes make an exact integer 80% boundary.
  let below = DrumxUnlocks.evaluate(course: course, history: [attempt(first, bars: 5, matched: 15)], progress: progress)
  check(!below.clearedIDs.contains(first.id) && !below.availableIDs.contains(second.id), "75% does not clear an 80% goal")
  let exact = DrumxUnlocks.evaluate(course: course, history: [attempt(first, bars: 5, matched: 16)], progress: progress)
  check(exact.clearedIDs == [first.id] && exact.availableIDs == [first.id, second.id], "exactly 80% clears and unlocks next lesson")
  check(exact.readingIDs.isEmpty, "within-chapter unlock does not manufacture or require reading evidence")
  check(exact.recommendedID == second.id, "next unlocked lesson is recommended")
  let minimum = DrumxUnlocks.evaluate(course: course, history: [attempt(first, matched: 13)], progress: progress)
  check(minimum.clearedIDs.contains(first.id), "13 of 16 clears a four-bar take")
  let tooFew = DrumxUnlocks.evaluate(course: course, history: [attempt(first, matched: 12)], progress: progress)
  check(!tooFew.clearedIDs.contains(first.id), "12 of 16 remains below the threshold")
  let short = DrumxUnlocks.evaluate(course: course, history: [attempt(first, bars: 3)], progress: progress)
  check(short.practisedIDs.contains(first.id) && !short.clearedIDs.contains(first.id), "three bars count as practice but cannot clear")
  let looseTiming = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, bars: 5, matched: 16, extra: 30, onTime: 0)], progress: progress)
  check(looseTiming.clearedIDs.contains(first.id), "goal uses expected-note coverage, not timing precision or penalized score")
  let assisted = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, tempo: 30)], progress: progress)
  check(assisted.clearedIDs.contains(first.id), "slow guided practice can clear beginner work")
  let memoryLive = DrumxUnlocks.evaluate(course: course,
    history: [attempt(first, mode: 2, live: true)], progress: progress)
  check(memoryLive.clearedIDs.contains(first.id) && memoryLive.recallIDs.isEmpty,
        "memory with live feedback can clear but is not a click-only achievement")
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
  var history = Array(course.prefix(4)).map { attempt($0) }
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
  history.append(attempt(course[4]))
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
  check(complete.clearedIDs == [lesson.id] && complete.availableIDs.contains(course[1].id),
        "real archived 13-of-16 take unlocks the next lesson without on-time precision")
}

private func completeSequenceChecks(defaults: UserDefaults) {
  let progress = fresh(defaults)
  var history: [LessonAttempt] = []
  for (index, lesson) in course.enumerated() {
    let before = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
    check(before.availableIDs.contains(lesson.id) && before.recommendedID == lesson.id,
          "lesson \(index + 1) is the sequential recommendation before its take")
    history.append(attempt(lesson))
    var after = DrumxUnlocks.evaluate(course: course, history: history, progress: progress)
    check(after.clearedIDs.contains(lesson.id), "lesson \(index + 1) clears on its own authored chart")
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
  check(end.availableIDs == Set(course.map(\.id)) && end.clearedIDs == Set(course.map(\.id)),
        "complete twelve-lesson sequence preserves all available pattern goals")
  check(end.recallIDs.isEmpty, "finishing the course never fabricates a memory achievement")
}

@main
enum DrumxUnlockChecks {
  static func main() {
    let suite = "drumx.unlock-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    thresholdChecks(defaults: defaults)
    chapterAndMigrationChecks(defaults: defaults)
    archiveAdmissionChecks(defaults: defaults)
    completeSequenceChecks(defaults: defaults)
    check(DrumxUnlocks.evaluate(course: [], history: [], progress: fresh(defaults)).availableIDs.isEmpty,
          "empty course produces no invented lesson")
    print("Drumx beginner unlocks: \(checks) checks passed.")
  }
}
