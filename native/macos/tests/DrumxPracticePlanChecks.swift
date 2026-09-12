import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}
private func near(_ actual: Double, _ expected: Double) -> Bool { abs(actual - expected) < 0.000001 }

private func saved(_ plan: DrumxPracticePlan, lesson: DrumxLessonDefinition) -> PracticeResume {
  PracticeResume(lessonID: lesson.id, tempo: plan.tempo, mode: plan.mode,
    liveFeedback: plan.liveFeedback, bars: plan.bars, lessonVersion: lesson.version,
    sessionFormatVersion: DrumxPracticePlan.currentSessionFormatVersion)
}

private func standardChecks() {
  check(DrumxPracticePlan.barChoices == [1, 4, 8, 16], "repair, short checks, and longer practice remain explicit choices")
  for lesson in DrumxCourse.lessons {
    let plan = DrumxPracticePlan.standard(lesson: lesson)
    check(plan.tempo == lesson.suggestedBPM, "standard pace comes from the selected lesson")
    check(plan.bars == 16 && plan.mode == 0 && plan.liveFeedback, "standard phrase has enough guided repetitions")
    check(plan.durationSeconds >= 53 && plan.durationSeconds <= 64, "current course defaults give roughly one minute before review")
    check(near(plan.durationSeconds * plan.tempo / 60, 64), "standard phrase always has 64 quarter-note beats")
    check(near(plan.countInSeconds * plan.tempo / 60, 4), "count-in remains four quarter-note beats")
    check(near(plan.totalDurationSeconds, plan.durationSeconds + plan.countInSeconds), "count-in is separate from playing time")
    check(DrumxPracticePlan.restore(resume: saved(plan, lesson: lesson), lesson: lesson) == plan,
      "a current standard plan survives persistence without drift")
  }
  let first = DrumxCourse.lessons[0]
  check(DrumxPracticePlan.restore(resume: PracticeResume(), lesson: first) == .standard(lesson: first),
    "new profile begins at the authored first-lesson pace")
}

private func migrationChecks() {
  let lesson = DrumxCourse.lessons[0]
  let raw = Data("""
    {"lessonID":"find-the-pulse","tempo":84,"mode":2,"liveFeedback":false,"bars":4}
    """.utf8)
  let old = try! JSONDecoder().decode(PracticeResume.self, from: raw)
  check(old.sessionFormatVersion == nil && old.lessonVersion == nil, "pre-version JSON stays readable")
  let migrated = DrumxPracticePlan.restore(resume: old, lesson: lesson)
  check(migrated.bars == 16 && migrated.tempo == 84, "legacy default grows once while retaining the player's tempo")
  check(migrated.mode == 2 && !migrated.liveFeedback, "migration preserves strict recall rather than silently restoring aids")
  check(old.bars == 4 && old.sessionFormatVersion == nil, "planning does not mutate its input or persist by itself")
  let encoded = try! JSONEncoder().encode(saved(migrated, lesson: lesson))
  let reopened = try! JSONDecoder().decode(PracticeResume.self, from: encoded)
  check(reopened.sessionFormatVersion == 1 && reopened.bars == 16, "migrated plan persists its format marker")
  check(DrumxPracticePlan.restore(resume: reopened, lesson: lesson) == migrated, "reopening does not apply another migration")

  for bars in [1, 8, 16] {
    let oldChoice = PracticeResume(lessonID: lesson.id, tempo: 92, mode: 2, liveFeedback: false,
      bars: bars, lessonVersion: lesson.version)
    let restored = DrumxPracticePlan.restore(resume: oldChoice, lesson: lesson)
    check(restored.bars == bars && restored.tempo == 92 && restored.mode == 2 && !restored.liveFeedback,
      "legacy nondefault phrase choice and recall aids are preserved")
  }
  for bars in DrumxPracticePlan.barChoices {
    let choice = PracticeResume(lessonID: lesson.id, tempo: 76, mode: 0, liveFeedback: false,
      bars: bars, lessonVersion: lesson.version, sessionFormatVersion: 1)
    check(DrumxPracticePlan.restore(resume: choice, lesson: lesson).bars == bars,
      "current explicit phrase choice survives, including four bars")
  }
}

private func boundaryChecks() {
  let lesson = DrumxCourse.lessons[0]
  var resume = PracticeResume(lessonID: lesson.id, tempo: 120, mode: 2, liveFeedback: false,
    bars: 8, lessonVersion: lesson.version, sessionFormatVersion: 1)
  for (input, expected) in [(30.0, 48.0), (48, 48), (92, 92), (144, 144), (240, 144)] {
    resume.tempo = input
    check(DrumxPracticePlan.restore(resume: resume, lesson: lesson).tempo == expected, "stored tempo is bounded to the playable range")
  }
  for tempo in [Double.nan, .infinity, -.infinity] {
    resume.tempo = tempo
    let plan = DrumxPracticePlan.restore(resume: resume, lesson: lesson)
    check(plan.tempo == lesson.suggestedBPM && plan.durationSeconds.isFinite, "nonfinite tempo has a finite authored fallback")
  }
  resume.tempo = 60
  for bars in [-1, 0, 2, 3, 32, 64, Int.max] {
    resume.bars = bars
    check(DrumxPracticePlan.restore(resume: resume, lesson: lesson).bars == 16, "unsupported stored phrase length has a standard fallback")
  }
  resume.bars = 1; resume.mode = 1
  let hidden = DrumxPracticePlan.restore(resume: resume, lesson: lesson)
  check(hidden.bars == 4 && hidden.mode == 1 && !hidden.liveFeedback, "Hidden bars needs a complete shown/hidden sequence")
  resume.mode = 2
  let recall = DrumxPracticePlan.restore(resume: resume, lesson: lesson)
  check(recall.bars == 1 && recall.mode == 2 && !recall.liveFeedback, "one-bar click-only recall remains available")
  check(near(recall.durationSeconds, 4), "one bar at 60 BPM lasts four seconds")
  for mode in [-1, 3, Int.max] {
    resume.mode = mode
    check(DrumxPracticePlan.restore(resume: resume, lesson: lesson).mode == 0, "unknown guidance falls back to Guided")
  }
  resume.mode = 2; resume.bars = 8; resume.tempo = 120
  resume.lessonVersion = "find-the-pulse-v0"
  check(DrumxPracticePlan.restore(resume: resume, lesson: lesson) == .standard(lesson: lesson),
    "a changed lesson revision resets tempo, length, and assistance together")
  resume.lessonVersion = lesson.version; resume.lessonID = "unknown"
  check(DrumxPracticePlan.restore(resume: resume, lesson: lesson) == .standard(lesson: lesson), "an unknown selected lesson gets the supplied lesson's defaults")
  resume.lessonID = lesson.id
  for version in [-1, 0, 2, Int.max] {
    resume.sessionFormatVersion = version
    check(DrumxPracticePlan.restore(resume: resume, lesson: lesson) == .standard(lesson: lesson),
      "unsupported session formats are not treated as current choices")
  }
}

private func evidenceChecks() {
  let suite = "drumx.practice-plan-tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let progress = DrumxProgress(defaults: defaults)
  let lesson = DrumxCourse.lessons[0]
  check(progress.markReadingChecked(lessonID: lesson.id, version: lesson.version), "reading fixture records an explicit answer")
  let checksBefore = progress.selectedProfile.checks
  let plan = DrumxPracticePlan.restore(resume: progress.selectedProfile.resume, lesson: lesson)
  check(progress.updateResume(saved(plan, lesson: lesson)), "controller may persist the migrated plan")
  check(progress.selectedProfile.checks == checksBefore, "resuming or migrating cannot award or erase a reading check")
  check(progress.practiceEvidence(lessonID: lesson.id, version: lesson.version) == nil
      && progress.recallEvidence(lessonID: lesson.id, version: lesson.version) == nil,
    "a longer planned phrase creates no playing or recall achievement")
  let reopened = DrumxProgress(defaults: defaults)
  check(DrumxPracticePlan.restore(resume: reopened.selectedProfile.resume, lesson: lesson) == plan,
    "stored profile returns to the same plan")
}

@main enum DrumxPracticePlanChecks {
  static func main() {
    standardChecks(); migrationChecks(); boundaryChecks(); evidenceChecks()
    print("Drumx practice plan: \(checks) checks passed.")
  }
}
