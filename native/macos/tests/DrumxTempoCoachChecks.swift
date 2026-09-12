import Foundation

private var checks = 0
private func check(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !value() { fatalError("FAIL: \(message)") }
}
private let mapping = [[42, 44, 46], [38, 40], [35, 36]]
private func settings(_ bpm: Double = 72, mode: Int = 0, live: Bool = true,
                      bars: Int = 16, source: String = "keyboard", offset: Double = 0,
                      monitor: Bool? = true, map: [[Int]] = mapping, policy: Int? = 1,
                      version: String = "find-the-pulse-v1") -> TakeSettings {
  TakeSettings(tempo: bpm, mode: mode, liveFeedback: live, bars: bars,
    calibrationMS: offset, inputIdentity: source, mapping: map, lessonVersion: version,
    tempoPolicyVersion: policy, monitoring: monitor)
}
private func attempt(_ settings: TakeSettings = settings(), id: UUID = UUID(),
                     matched: Int? = nil, onTime: Int? = nil, extra: Int = 0,
                     date: Double = 1) -> LessonAttempt {
  let expected = settings.bars * 4, caught = matched ?? settings.bars * 4, timely = onTime ?? caught
  let denominator = Double(expected + extra)
  return LessonAttempt(id: id, endedAt: Date(timeIntervalSince1970: date), settings: settings,
    matched: caught, missed: expected - caught, extra: extra, onTime: timely, expected: expected,
    timingAccuracyPercent: Double(timely) / denominator * 100,
    hitRatePercent: Double(caught) / denominator * 100,
    meanOffsetMS: caught > 0 ? 0 : nil, meanAbsoluteOffsetMS: caught > 0 ? 0 : nil, bestStreak: timely)
}
private func evaluate(_ history: [LessonAttempt], _ current: TakeSettings = settings()) -> DrumxTempoCoach.Recommendation {
  guard let result = DrumxTempoCoach.evaluate(history: history, settings: current) else { fatalError("invalid fixture") }
  return result
}

@main enum DrumxTempoCoachChecks {
  static func main() throws {
    let suite = "drumx.tempo-native.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let progress = DrumxProgress(defaults: defaults)
    let course = DrumxCourse.lessons
    check(DrumxTempoCoach.evaluate(history: [], settings: settings(bars: Int.max)) == nil,
      "invalid context is rejected before narrowing integer fields")
    let start = evaluate([], settings(60))
    check(start.next.tempo == 60 && start.next.bars == 16 && start.next.mode == 0, "new guided pulse starts at 60 for a full block")
    let warmup = evaluate([attempt(settings(60))], settings(60))
    check(warmup.next.tempo == 66 && warmup.decision.current_earned == 0, "one steady warmup suggests next pace without claiming repeated evidence")
    check(warmup.reason == "A steady phrase. Try the next pace.", "warmup coaching matches the actual recommendation")
    check(evaluate([attempt(settings(66))], settings(66)).next.tempo == 72, "second authored warmup reaches checkpoint pace")
    let one = attempt(), two = attempt(date: 2)
    check(!evaluate([one]).checkpointEarned, "one checkpoint phrase is attempted, not earned")
    let earned = evaluate([one, two])
    check(earned.checkpointEarned && earned.next.mode == 1 && earned.next.liveFeedback, "two comparable phrases earn checkpoint then suggest hidden bars")
    check(evaluate([one, attempt(matched: 50, date: 2), attempt(date: 3)]).checkpointEarned, "two in three qualifies across one weaker take")
    check(!evaluate([one, attempt(matched: 50, date: 2), attempt(matched: 50, date: 3), attempt(date: 4)]).checkpointEarned, "separated successes outside a three-take window do not pool")
    check(evaluate([one, two, attempt(matched: 2, date: 3)]).checkpointEarned, "later difficulty does not erase earned checkpoint")
    check(!evaluate([one, attempt(id: one.id, date: 2)]).checkpointEarned, "duplicate identity is one attempt")
    check(!evaluate([one, two, attempt(id: two.id, matched: 0, date: 3)]).checkpointEarned, "last same-ID correction can revoke unearned evidence")
    check(!evaluate([attempt(settings(60)), attempt(settings(60), date: 2)], settings(60)).checkpointEarned, "repeated slower playing never impersonates 72")
    check(!evaluate([attempt(settings(84)), attempt(settings(84), date: 2)], settings(84)).checkpointEarned, "stretch playing never impersonates 72")
    for changed in [settings(source: "midi:4"), settings(offset: 1), settings(monitor: false),
                    settings(map: [[42, 44, 46], [38], [35, 36]]), settings(mode: 1),
                    settings(live: false), settings(bars: 8), settings(bars: 4)] {
      check(!evaluate([one, attempt(changed, date: 2)]).checkpointEarned, "different source/map/monitor/offset/assist/length evidence stays separate")
    }
    for old in [settings(policy: nil), settings(monitor: nil, policy: nil),
                settings(policy: 2), settings(version: "find-the-pulse-v2")] {
      check(!evaluate([attempt(old), attempt(old, date: 2)]).checkpointEarned, "legacy, unsupported policy and wrong lesson versions cannot earn")
    }
    let device = settings(source: "midi:4")
    check(!DrumxTempoCoach.sameInputConditions(settings(), device), "review detects a changed input before accepting an old recommendation")
    check(DrumxTempoCoach.sameInputConditions(settings(), settings(66, mode: 1)), "next tempo or assistance is separate from input-condition guard")
    let changedHidden = evaluate([], settings(mode: 1, source: "midi:new"))
    check(changedHidden.next.mode == 0 && changedHidden.next.liveFeedback && !changedHidden.checkpointEarned,
      "new input restores canonical guided checkpoint without pretending hidden work earned it")
    let historicalDevice = [attempt(device), attempt(device, date: 2)]
    check(!evaluate(historicalDevice).checkpointEarned, "coaching stays scoped to today's input")
    check(DrumxTempoCoach.checkpointEarned(history: historicalDevice), "course achievement survives device changes without pooling groups")
    let checkpointState = DrumxUnlocks.evaluate(course: course, history: historicalDevice, progress: progress)
    check(checkpointState.clearedIDs.contains(course[0].id) && checkpointState.availableIDs.contains(course[1].id), "shared checkpoint controls native course access")
    let freshWarmup = DrumxUnlocks.evaluate(course: course, history: [attempt(settings(60))], progress: progress)
    check(!freshWarmup.availableIDs.contains(course[1].id), "new policy cannot bypass checkpoint through legacy 80-percent rule")
    let freeEligible = [attempt(settings()), attempt(settings(), date: 2)]
    check(DrumxTempoCoach.checkpointEarned(history: freeEligible), "eligible free-practice conditions can count without a route label")
    let hidden = settings(mode: 1), recall = settings(mode: 2, live: false)
    let faded = [one, two, attempt(hidden, date: 3), attempt(hidden, date: 4)]
    check(evaluate(faded, hidden).next.mode == 2 && !evaluate(faded, hidden).next.liveFeedback, "repeated hidden work suggests strict recall")
    let memory = faded + [attempt(recall, date: 5), attempt(recall, date: 6)]
    check(evaluate(memory, recall).recallEarned, "strict recall evidence is earned separately")
    check(!evaluate([attempt(settings(mode: 2)), attempt(settings(mode: 2), date: 2)], settings(mode: 2)).recallEarned, "memory with live feedback cannot earn strict recall")
    var stopped = DXSnapshot(); stopped.total.expected = 64; stopped.total.matched = 2
    let interrupted = DrumxTempoCoach.evaluate(history: [one, two], settings: settings(), stopped: stopped, stoppedID: UUID())!
    check(interrupted.decision.action == Int32(DX_TEMPO_RESTART.rawValue) && interrupted.checkpointEarned, "stopped phrase recommends restart while retaining earlier checkpoint")
    check(evaluate([attempt(settings(84), matched: 2), attempt(settings(84), matched: 2, date: 2)], settings(84)).next.tempo == 72, "stretch repair returns to an authored pace")
    let realHistory = LessonHistory(defaults: defaults, key: "tempo-real-core")
    let core = dx_core_create()!
    defer { dx_core_destroy(core) }
    let chart = (0..<64).map { DXChartEvent(pad: 1, beat: Double($0)) }
    for _ in 0..<2 {
      check(chart.withUnsafeBufferPointer { dx_core_load_chart(core, 72, 64, $0.baseAddress, Int32($0.count)) } == 1,
        "policy fixture loads a real 16-bar one-pad pulse")
      for index in 0..<64 { _ = dx_core_input(core, 1, Double(index) * 60 / 72, 0.8) }
      dx_core_advance(core, 64 * 60 / 72)
      var full = DXSnapshot(); dx_core_snapshot(core, &full)
      check(realHistory.record(id: UUID(), settings: settings(), snapshot: full, completedNaturally: true) != nil,
        "naturally completed current-policy aggregate enters the existing archive")
    }
    check(DrumxTempoCoach.checkpointEarned(history: realHistory.attempts),
      "two actual scoring-core aggregates earn the shared pulse checkpoint through native archive admission")
    let legacy = settings(90, mode: 2, live: false, bars: 8, monitor: nil, policy: nil)
    let decoded = try JSONDecoder().decode(TakeSettings.self, from: JSONEncoder().encode(legacy))
    check(decoded == legacy && decoded.tempoPolicyVersion == nil, "old take encoding retains nil policy without invented evidence")
    let currentDecoded = try JSONDecoder().decode(TakeSettings.self, from: JSONEncoder().encode(settings()))
    check(currentDecoded.tempoPolicyVersion == 1 && currentDecoded.monitoring == true, "new policy and monitoring survive archive round trip")
    let oldResume = PracticeResume(tempo: 90, mode: 2, liveFeedback: false, bars: 8)
    var routes = DrumxPulsePractice.initial(resume: oldResume, existingPlayer: true)
    check(routes.isFreePractice && routes.free == oldResume && routes.guided.tempo == 60 && routes.guided.bars == 16, "migration preserves existing practice and offers a separate guided start")
    check(!DrumxPulsePractice.initial(resume: PracticeResume(), existingPlayer: false).isFreePractice, "new players default to guided")
    check(progress.updatePulsePractice(routes), "valid separate plans save")
    let firstID = progress.selectedProfile.id
    routes.isFreePractice = false; routes.guided.tempo = 66
    check(progress.updatePulsePractice(routes), "guided promotion persists only after explicit adapter action")
    let reload = DrumxProgress(defaults: defaults)
    check(reload.selectedProfile.pulsePractice == routes && reload.selectedProfile.pulsePractice?.free == oldResume, "guided save does not overwrite free conditions")
    let other = progress.addProfile(name: "Brother")!
    check(other.pulsePractice == nil && progress.selectedHistoryKey != reload.selectedHistoryKey, "new profile has independent plans and history")
    check(progress.selectProfile(id: firstID), "original profile remains selectable")
    check(progress.selectedProfile.pulsePractice == routes, "switching players restores the original plan")
    var invalid = routes; invalid.policyVersion = 2
    check(!progress.updatePulsePractice(invalid), "future policy does not silently become current guided evidence")
    invalid = routes; invalid.guided.bars = 1
    check(!progress.updatePulsePractice(invalid), "one-bar repair is free practice, not an invalid guided plan")
    invalid = routes; invalid.guided.mode = 2; invalid.guided.liveFeedback = true
    check(!progress.updatePulsePractice(invalid), "guided recall cannot retain live feedback")
    print("Drumx native tempo coach: \(checks) checks passed.")
  }
}
