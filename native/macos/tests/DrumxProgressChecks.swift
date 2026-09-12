import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private func profileChecks(defaults: UserDefaults) {
  let store = DrumxProgress(defaults: defaults, storageKey: "profiles")
  let first = store.selectedProfile
  check(first.name == "Player 1", "default name does not infer a personal name")
  check(store.profiles.count == 1, "fresh install has one player")
  check(!first.hasCompletedWelcome && first.checks.isEmpty, "new player has no welcome or check evidence")
  check(store.selectedHistoryKey == "drumx.lessonHistory.v1", "first player adopts legacy history key")
  check(first.resume == PracticeResume(), "fresh resume has beginner defaults")
  check(first.resume.lessonID == "find-the-pulse", "new default uses the canonical first lesson")
  check(first.resume.lessonVersion == nil, "generic default does not invent a course revision")
  let reopened = DrumxProgress(defaults: defaults, storageKey: "profiles")
  check(reopened.selectedProfile.id == first.id, "default UUID persists before any user changes")
  check(reopened.selectedProfile.createdAt == first.createdAt, "creation date survives reopening")

  defaults.set(Data("legacy private history".utf8), forKey: "drumx.lessonHistory.v1")
  let resume = PracticeResume(lessonID: "backbeat", tempo: 84, mode: 2, liveFeedback: false,
                             bars: 8, lessonVersion: "backbeat-v3")
  check(store.updateResume(resume), "valid resume stored")
  check(store.completeWelcome(), "explicit welcome completion stored")
  let checkedAt = first.createdAt.addingTimeInterval(30)
  check(store.markReadingChecked(lessonID: "pulse", version: "v1", at: checkedAt), "reading pass recorded")
  check(store.readingEvidence(lessonID: "pulse", version: "v1")?.recordedAt == checkedAt, "reading date retained")
  check(store.readingEvidence(lessonID: "pulse", version: "v1")?.kind == .readingQuizPassed, "reading condition explicit")
  check(store.techniqueEvidence(lessonID: "pulse", version: "v1") == nil, "reading cannot prove technique")
  check(store.markTechniqueChecked(lessonID: "pulse", version: "v1", at: checkedAt), "technique self-check recorded separately")
  check(store.techniqueEvidence(lessonID: "pulse", version: "v1")?.kind == .techniqueSelfCheck, "technique evidence is self-report")
  check(store.readingEvidence(lessonID: "pulse", version: "v2") == nil, "new version has no reading evidence")
  check(store.techniqueEvidence(lessonID: "pulse", version: "v2") == nil, "new version has no technique evidence")
  check(store.readingEvidence(lessonID: "other", version: "v1") == nil, "other lesson has no reading evidence")
  check(store.markReadingChecked(lessonID: "pulse", version: "v1", at: checkedAt.addingTimeInterval(5)), "repeated check is idempotent")
  check(store.readingEvidence(lessonID: "pulse", version: "v1")?.recordedAt == checkedAt, "repeated check preserves original date")
  check(store.markReadingChecked(lessonID: "pulse", version: "v2", at: checkedAt), "new version can have independent evidence")
  check(store.selectedProfile.checks.count == 3, "only explicit checks exist")

  let second = store.addProfile(name: "  Player 2  ")!
  check(second.name == "Player 2" && store.selectedProfileID == second.id, "adding trims and selects player")
  check(second.checks.isEmpty && !second.hasCompletedWelcome, "welcome and evidence do not leak into another player")
  check(store.readingEvidence(lessonID: "pulse", version: "v1") == nil, "selected reading evidence is isolated")
  check(second.resume == PracticeResume(), "resume is isolated between users")
  check(store.selectedHistoryKey != "drumx.lessonHistory.v1", "second player cannot access default history")
  check(store.selectedHistoryKey.contains(second.id.uuidString.lowercased()), "new player's history key includes stable UUID")
  let secondKey = store.selectedHistoryKey
  defaults.set(Data("second private history".utf8), forKey: secondKey)
  let secondOpen = DrumxProgress(defaults: defaults, storageKey: "profiles")
  check(secondOpen.selectedProfileID == second.id && secondOpen.selectedHistoryKey == secondKey, "selection and history namespace survive reopen")
  check(secondOpen.selectProfile(id: first.id), "existing player can be selected")
  check(secondOpen.selectedProfile.resume == resume && secondOpen.selectedProfile.lastLessonID == "backbeat", "entire prior resume restored")
  check(secondOpen.selectedProfile.resume.lessonVersion == "backbeat-v3", "lesson revision persists across reopen and profile selection")
  check(secondOpen.selectedProfile.hasCompletedWelcome, "welcome completion survives restart and selection")
  check(secondOpen.selectedProfile.checks.count == 3, "versioned evidence survives restart and selection")
  check(secondOpen.renameSelectedProfile(name: "  Learner One  "), "default player can choose a name")
  check(secondOpen.selectedProfile.name == "Learner One" && secondOpen.selectedProfileID == first.id, "rename preserves player UUID")
  check(secondOpen.selectedHistoryKey == "drumx.lessonHistory.v1", "rename preserves legacy history ownership")
  check(secondOpen.selectedProfile.resume == resume && secondOpen.selectedProfile.checks.count == 3,
        "rename preserves resume and evidence")
  check(DrumxProgress(defaults: defaults, storageKey: "profiles").selectedProfile.name == "Learner One", "renamed player reopens")
  check(!secondOpen.renameSelectedProfile(name: "PLAYER 2"), "rename cannot collide with another player")
  check(!secondOpen.renameSelectedProfile(name: "\n") && !secondOpen.renameSelectedProfile(name: String(repeating: "x", count: 33)),
        "rename shares name validation")
  check(defaults.data(forKey: "drumx.lessonHistory.v1") == Data("legacy private history".utf8), "legacy history bytes untouched")
  check(defaults.data(forKey: secondKey) == Data("second private history".utf8), "private player history bytes untouched")
}

private func invalidInputChecks(defaults: UserDefaults) {
  let store = DrumxProgress(defaults: defaults, storageKey: "validation")
  let original = defaults.data(forKey: "validation")
  for name in ["", "  ", String(repeating: "x", count: 33), "a\nb", "a\u{0}b", "PLAYER 1"] {
    check(store.addProfile(name: name) == nil, "invalid or duplicate name rejected")
    check(defaults.data(forKey: "validation") == original, "invalid name cannot mutate saved state")
  }
  check(store.addProfile(name: String(repeating: "a", count: 32)) != nil, "32-character name accepted")
  check(store.addProfile(name: "鼓") != nil, "non-Latin player names accepted")
  check(!store.selectProfile(id: UUID()), "unknown player cannot become selected")
  let validResume = store.selectedProfile.resume
  let invalid = [
    PracticeResume(tempo: .nan), PracticeResume(tempo: .infinity),
    PracticeResume(tempo: 29), PracticeResume(tempo: 241),
    PracticeResume(mode: -1), PracticeResume(mode: 3),
    PracticeResume(bars: 0), PracticeResume(bars: 65),
    PracticeResume(lessonID: ""), PracticeResume(lessonID: " pulse"),
    PracticeResume(lessonID: "a\nb"), PracticeResume(lessonID: String(repeating: "x", count: 129)),
    PracticeResume(lessonVersion: ""), PracticeResume(lessonVersion: " v1"),
    PracticeResume(lessonVersion: "v1\nother"),
    PracticeResume(lessonVersion: String(repeating: "v", count: 129)),
  ]
  for resume in invalid {
    check(!store.updateResume(resume), "invalid resume rejected")
    check(store.selectedProfile.resume == validResume, "invalid resume preserves selected settings")
  }
  check(store.updateResume(PracticeResume(tempo: 30, mode: 0, bars: 1)), "minimum valid settings accepted")
  check(store.updateResume(PracticeResume(tempo: 240, mode: 2, liveFeedback: false, bars: 64)), "maximum valid settings accepted")
  check(!store.markReadingChecked(lessonID: "", version: "v1"), "empty lesson cannot earn evidence")
  check(!store.markTechniqueChecked(lessonID: "pulse", version: ""), "empty version cannot earn evidence")
  check(!store.markReadingChecked(lessonID: "pulse", version: "v1", at: Date(timeIntervalSinceReferenceDate: .infinity)), "invalid check date rejected")
  check(!store.markTechniqueChecked(lessonID: "pulse", version: "v1", at: store.selectedProfile.createdAt.addingTimeInterval(-1)), "check before profile creation rejected")
  check(store.selectedProfile.checks.isEmpty, "rejected checks create no evidence")
  while store.profiles.count < 8 { _ = store.addProfile(name: "Player \(store.profiles.count + 1)") }
  check(store.addProfile(name: "Ninth") == nil && store.profiles.count == 8, "eight-profile cap enforced")
}

private func resumeCompatibilityChecks(defaults: UserDefaults) {
  let source = DrumxProgress(defaults: defaults, storageKey: "versionedResume")
  let versioned = PracticeResume(lessonID: "backbeat", tempo: 92, mode: 1,
                                liveFeedback: false, bars: 8, lessonVersion: "backbeat-v2")
  check(source.updateResume(versioned), "versioned resume saves")
  check(DrumxProgress(defaults: defaults, storageKey: "versionedResume").selectedProfile.resume == versioned,
        "versioned resume reopens without losing conditions")
  var object = try! JSONSerialization.jsonObject(with: defaults.data(forKey: "versionedResume")!) as! [String: Any]
  var profiles = object["profiles"] as! [[String: Any]]
  var resume = profiles[0]["resume"] as! [String: Any]
  resume.removeValue(forKey: "lessonVersion")
  resume["lessonID"] = "pulse"
  profiles[0]["resume"] = resume
  object["profiles"] = profiles
  let legacyData = try! JSONSerialization.data(withJSONObject: object)
  defaults.set(legacyData, forKey: "legacyResume")
  let legacy = DrumxProgress(defaults: defaults, storageKey: "legacyResume")
  check(legacy.lastError == nil && legacy.selectedProfileID == source.selectedProfileID,
        "old resume without version loads the same player")
  check(legacy.selectedProfile.resume.lessonVersion == nil, "missing old revision decodes as nil")
  check(legacy.selectedProfile.resume.lessonID == "pulse" && legacy.selectedProfile.resume.tempo == 92
          && legacy.selectedProfile.resume.mode == 1 && !legacy.selectedProfile.resume.liveFeedback
          && legacy.selectedProfile.resume.bars == 8,
        "old resume remains intact for controller compatibility handling")
  check(defaults.data(forKey: "legacyResume") == legacyData, "loading legacy resume does not rewrite original bytes")
  check(legacy.updateResume(versioned), "explicit action can upgrade a legacy resume")
  check(DrumxProgress(defaults: defaults, storageKey: "legacyResume").selectedProfile.resume == versioned,
        "upgraded legacy resume retains explicit revision")

  resume["lessonVersion"] = ""
  profiles[0]["resume"] = resume
  object["profiles"] = profiles
  let invalidData = try! JSONSerialization.data(withJSONObject: object)
  defaults.set(invalidData, forKey: "invalidResumeVersion")
  let invalid = DrumxProgress(defaults: defaults, storageKey: "invalidResumeVersion")
  check(invalid.lastError != nil, "invalid revision in stored data is rejected")
  check(defaults.data(forKey: "invalidResumeVersion") == invalidData, "invalid stored revision bytes remain untouched")
}

private func durablePracticeChecks(defaults: UserDefaults) {
  let store = DrumxProgress(defaults: defaults, storageKey: "durablePractice")
  let firstID = store.selectedProfileID
  let date = store.selectedProfile.createdAt.addingTimeInterval(10)
  check(store.practiceEvidence(lessonID: "pulse", version: "v1") == nil
          && store.recallEvidence(lessonID: "pulse", version: "v1") == nil,
        "fresh profile has no fabricated practice or recall evidence")
  check(store.markPracticeCompleted(lessonID: "pulse", version: "v1", recall: false, at: date),
        "ordinary completed practice can record its own condition")
  check(store.practiceEvidence(lessonID: "pulse", version: "v1")?.kind == .completedPractice
          && store.practiceEvidence(lessonID: "pulse", version: "v1")?.recordedAt == date,
        "completed practice records kind and date")
  check(store.recallEvidence(lessonID: "pulse", version: "v1") == nil,
        "ordinary practice does not create click-only evidence")
  check(store.readingEvidence(lessonID: "pulse", version: "v1") == nil
          && store.techniqueEvidence(lessonID: "pulse", version: "v1") == nil,
        "playing cannot award reading or self-reported technique checks")
  let recallDate = date.addingTimeInterval(30)
  check(store.markPracticeCompleted(lessonID: "pulse", version: "v1", recall: true, at: recallDate),
        "explicit recall conditions record click-only attempt")
  check(store.practiceEvidence(lessonID: "pulse", version: "v1")?.recordedAt == date,
        "recall does not replace earlier practice date")
  check(store.recallEvidence(lessonID: "pulse", version: "v1")?.recordedAt == recallDate
          && store.recallEvidence(lessonID: "pulse", version: "v1")?.kind == .clickOnlyAttempt,
        "recall conditions carry their own date")
  check(store.markPracticeCompleted(lessonID: "pulse", version: "v1", recall: false,
                                     at: recallDate.addingTimeInterval(5)),
        "ordinary practice still succeeds after recall")
  check(store.recallEvidence(lessonID: "pulse", version: "v1")?.recordedAt == recallDate,
        "later ordinary practice cannot erase prior recall")
  check(store.selectedProfile.checks.count == 2, "repeated takes do not accumulate score or count records")
  check(store.markReadingChecked(lessonID: "pulse", version: "v1", at: date)
          && store.markTechniqueChecked(lessonID: "pulse", version: "v1", at: date),
        "manual reading and technique evidence remains available separately")
  check(store.practiceEvidence(lessonID: "pulse", version: "v2") == nil
          && store.recallEvidence(lessonID: "pulse", version: "v2") == nil,
        "practice and recall cannot leak to a new lesson revision")
  check(store.practiceEvidence(lessonID: "other", version: "v1") == nil
          && store.recallEvidence(lessonID: "other", version: "v1") == nil,
        "practice and recall cannot leak to another lesson")

  // Replace an opaque recent-history window as its independent owner does when
  // older attempts age out. Progress must not depend on any record in that key.
  let originalAttemptID = UUID().uuidString
  var rollingHistory = [originalAttemptID]
  for _ in 0..<205 {
    rollingHistory.append(UUID().uuidString)
    rollingHistory = Array(rollingHistory.suffix(200))
  }
  check(rollingHistory.count == 200 && !rollingHistory.contains(originalAttemptID),
        "history fixture has evicted the original completed take")
  let historyData = try! JSONEncoder().encode(rollingHistory)
  defaults.set(historyData, forKey: store.selectedHistoryKey)
  let reopened = DrumxProgress(defaults: defaults, storageKey: "durablePractice")
  check(reopened.practiceEvidence(lessonID: "pulse", version: "v1")?.recordedAt == date,
        "completed-practice evidence survives eviction from the separate 200-take window")
  check(reopened.recallEvidence(lessonID: "pulse", version: "v1")?.recordedAt == recallDate,
        "recall evidence survives eviction from the separate history window")
  check(reopened.readingEvidence(lessonID: "pulse", version: "v1") != nil
          && reopened.techniqueEvidence(lessonID: "pulse", version: "v1") != nil,
        "new practice flags preserve existing manual evidence across reopen")
  check(defaults.data(forKey: reopened.selectedHistoryKey) == historyData,
        "progress reopening cannot mutate the separate history store")

  _ = reopened.addProfile(name: "Another Player")
  check(reopened.practiceEvidence(lessonID: "pulse", version: "v1") == nil
          && reopened.recallEvidence(lessonID: "pulse", version: "v1") == nil,
        "practice evidence is isolated from another player")
  check(reopened.markPracticeCompleted(lessonID: "pulse", version: "v2", recall: true),
        "new player may create independent recall evidence")
  check(reopened.selectedProfile.checks.count == 2
          && reopened.practiceEvidence(lessonID: "pulse", version: "v2") != nil,
        "first recall attempt stores both required conditions together")
  check(reopened.selectProfile(id: firstID), "original player can resume after another player's take")
  check(reopened.recallEvidence(lessonID: "pulse", version: "v2") == nil,
        "new player's version evidence does not leak backward")
  let beforeInvalid = defaults.data(forKey: "durablePractice")
  check(!reopened.markPracticeCompleted(lessonID: "", version: "v1", recall: true),
        "invalid lesson cannot create either practice condition")
  check(!reopened.markPracticeCompleted(lessonID: "pulse", version: "", recall: false),
        "invalid version cannot create practice evidence")
  check(!reopened.markPracticeCompleted(lessonID: "pulse", version: "v3", recall: true,
                                        at: Date(timeIntervalSinceReferenceDate: .infinity)),
        "invalid practice date is rejected")
  check(defaults.data(forKey: "durablePractice") == beforeInvalid,
        "invalid practice records cannot partially mutate durable evidence")
}

private func corruptRecordChecks(defaults: UserDefaults) {
  let corrupt = Data("not a progress record".utf8)
  defaults.set(corrupt, forKey: "corrupt")
  let store = DrumxProgress(defaults: defaults, storageKey: "corrupt")
  check(store.lastError != nil, "corrupt record reported")
  check(store.selectedProfile.name == "Player 1" && store.selectedProfile.checks.isEmpty, "safe fallback has no fabricated evidence")
  check(defaults.data(forKey: "corrupt") == corrupt, "corrupt original not overwritten on initialization")
  check(store.selectProfile(id: store.selectedProfileID), "no-op selection accepted")
  check(store.updateResume(PracticeResume()), "no-op resume accepted")
  check(store.renameSelectedProfile(name: "Player 1"), "no-op rename accepted")
  check(defaults.data(forKey: "corrupt") == corrupt && store.lastError != nil, "no-op calls preserve original corrupt record and warning")
  check(store.addProfile(name: "") == nil, "invalid action rejected after corruption")
  check(defaults.data(forKey: "corrupt") == corrupt, "rejected action preserves corrupt original")
  check(store.completeWelcome(), "explicit state change may replace corrupt record")
  check(store.lastError == nil && defaults.data(forKey: "corrupt") != corrupt, "successful explicit change stores valid replacement")
  check(DrumxProgress(defaults: defaults, storageKey: "corrupt").selectedProfile.hasCompletedWelcome, "replacement record reopens")

  defaults.set("wrong storage type", forKey: "wrongType")
  let wrongType = DrumxProgress(defaults: defaults, storageKey: "wrongType")
  check(wrongType.lastError != nil && defaults.string(forKey: "wrongType") == "wrong storage type", "wrong source type preserved")

  let source = DrumxProgress(defaults: defaults, storageKey: "source")
  _ = source.markReadingChecked(lessonID: "pulse", version: "v1")
  let validData = defaults.data(forKey: "source")!
  let validJSON = try! JSONSerialization.jsonObject(with: validData) as! [String: Any]
  func reject(_ key: String, mutate: (inout [String: Any]) -> Void) {
    var object = validJSON
    mutate(&object)
    let data = try! JSONSerialization.data(withJSONObject: object)
    defaults.set(data, forKey: key)
    let loaded = DrumxProgress(defaults: defaults, storageKey: key)
    check(loaded.lastError != nil && loaded.selectedProfile.checks.isEmpty, "invalid decoded source rejected without evidence")
    check(defaults.data(forKey: key) == data, "invalid decoded original preserved")
  }
  reject("futureSchema") { $0["schemaVersion"] = 2 }
  reject("unknownSelection") { $0["selectedProfileID"] = UUID().uuidString }
  reject("duplicateProfile") { object in
    var profiles = object["profiles"] as! [[String: Any]]
    profiles.append(profiles[0])
    object["profiles"] = profiles
  }
  reject("badResume") { object in
    var profiles = object["profiles"] as! [[String: Any]]
    var resume = profiles[0]["resume"] as! [String: Any]
    resume["tempo"] = 999
    profiles[0]["resume"] = resume
    object["profiles"] = profiles
  }
  reject("falseCondition") { object in
    var profiles = object["profiles"] as! [[String: Any]]
    var evidence = profiles[0]["checks"] as! [[String: Any]]
    evidence[0]["kind"] = "midiVerifiedTechnique"
    profiles[0]["checks"] = evidence
    object["profiles"] = profiles
  }
  reject("wrongLegacyOwner") { object in
    var profiles = object["profiles"] as! [[String: Any]]
    profiles[0]["usesLegacyHistory"] = false
    object["profiles"] = profiles
  }
  reject("recallWithoutCompletion") { object in
    var profiles = object["profiles"] as! [[String: Any]]
    var evidence = profiles[0]["checks"] as! [[String: Any]]
    evidence[0]["kind"] = "clickOnlyAttempt"
    profiles[0]["checks"] = evidence
    object["profiles"] = profiles
  }
}

@main
enum DrumxProgressChecks {
  static func main() {
    let suite = "drumx.progress-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    profileChecks(defaults: defaults)
    invalidInputChecks(defaults: defaults)
    resumeCompatibilityChecks(defaults: defaults)
    durablePracticeChecks(defaults: defaults)
    corruptRecordChecks(defaults: defaults)
    print("Drumx local player/progress: \(checks) checks passed.")
  }
}
