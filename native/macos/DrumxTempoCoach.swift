import Foundation

/// Native adaptation only. Every numerical promotion rule lives in drumx_tempo.cpp.
enum DrumxTempoCoach {
  static let lessonID = "find-the-pulse"
  static let lessonVersion = "find-the-pulse-v1"
  static let policyVersion = 1

  private struct Conditions: Hashable {
    let input: String
    let mapping: [[Int]]
    let monitoring: Bool?
    let offset: Double
    init(_ settings: TakeSettings) {
      input = settings.inputIdentity; mapping = settings.mapping
      monitoring = settings.monitoring; offset = settings.calibrationMS
    }
  }

  struct Recommendation {
    let decision: DXTempoDecision
    var checkpointEarned: Bool { decision.checkpoint_earned != 0 }
    var recallEarned: Bool { decision.recall_earned != 0 }
    var next: PracticeResume {
      PracticeResume(tempo: decision.next_bpm, mode: Int(decision.next_guidance),
        liveFeedback: decision.next_live_feedback != 0, bars: Int(decision.next_bars),
        lessonVersion: lessonVersion, sessionFormatVersion: 1)
    }
    var actionTitle: String {
      switch decision.action {
      case Int32(DX_TEMPO_ADVANCE.rawValue): return "Try \(Int(decision.next_bpm)) BPM"
      case Int32(DX_TEMPO_REPEAT.rawValue): return "Repeat · \(Int(decision.next_bpm)) BPM"
      case Int32(DX_TEMPO_HIDE_NOTES.rawValue): return "Hide alternating bars"
      case Int32(DX_TEMPO_TRY_RECALL.rawValue): return "Play from memory"
      case Int32(DX_TEMPO_CONTINUE.rawValue): return "Repeat from memory"
      case Int32(DX_TEMPO_RESTART.rawValue): return "Restart · \(Int(decision.next_bpm)) BPM"
      case Int32(DX_TEMPO_CHECK_INPUT.rawValue): return "Try again · \(Int(decision.next_bpm)) BPM"
      default: return "Play · \(Int(decision.next_bpm)) BPM"
      }
    }
    var reason: String {
      switch decision.reason {
      case Int32(DX_TEMPO_ONE_STRONG_PHRASE.rawValue):
        return decision.action == Int32(DX_TEMPO_ADVANCE.rawValue)
          ? "A steady phrase. Try the next pace."
          : "One steady phrase. Repeat this condition to build reliable evidence."
      case Int32(DX_TEMPO_BUILD_REPEATABILITY.rawValue): return "Keep the spaces even through the last bar. Repeat this condition to build reliable evidence."
      case Int32(DX_TEMPO_CHECKPOINT_EARNED.rawValue): return "72 BPM checkpoint earned. Keep the pace and try fewer visual cues."
      case Int32(DX_TEMPO_HIDDEN_EARNED.rawValue): return "Hidden bars stayed steady. Next, recall the phrase with the click."
      case Int32(DX_TEMPO_RECALL_EARNED.rawValue): return "The pulse held from memory. Continue the course or revisit a comfortable pace."
      case Int32(DX_TEMPO_REPEATED_COVERAGE_DIFFICULTY.rawValue): return "Give the pattern more room. The next phrase restores an easier condition."
      case Int32(DX_TEMPO_TIMING_NEEDS_REPEAT.rawValue): return "The notes are there. Repeat this pace and listen for even spaces."
      case Int32(DX_TEMPO_NO_INPUT.rawValue): return "No matched notes. Check your input before trying the phrase again."
      case Int32(DX_TEMPO_INTERRUPTED.rawValue): return "This take stopped early. Restart the full phrase; your earned progress stays."
      case Int32(DX_TEMPO_PHRASE_TOO_SHORT.rawValue): return "Short repair is useful. Play 16 bars to build evidence for a pace."
      case Int32(DX_TEMPO_CONDITIONS_NEED_REPEAT.rawValue): return "This input and assistance need their own repeatable phrases."
      default: return "Start with one stroke per click. The app chooses the next fixed pace after your take."
      }
    }
    var achievement: String {
      if recallEarned { return "72 BPM checkpoint earned · Recalled at 72 BPM" }
      if checkpointEarned { return "72 BPM checkpoint earned · Recall still to practise" }
      return "60 → 66 → 72 BPM checkpoint · Optional 84 / 96 BPM later"
    }
  }

  /// History must belong only to the selected player. A separate transient stopped
  /// snapshot explains a restart, but never enters the archive or earns a checkpoint.
  static func evaluate(history: [LessonAttempt], settings: TakeSettings,
                       stopped: DXSnapshot? = nil, stoppedID: UUID? = nil) -> Recommendation? {
    guard settings.isValid, settings.lessonVersion == lessonVersion, settings.tempoPolicyVersion == policyVersion,
      settings.monitoring != nil, settings.calibrationMS.isFinite else { return nil }
    var conditions: [Conditions: UInt64] = [Conditions(settings): 1]
    var identifiers: [UUID: UInt64] = [:]
    func token(_ value: Conditions) -> UInt64 {
      if let token = conditions[value] { return token }
      let token = UInt64(conditions.count + 1); conditions[value] = token; return token
    }
    func identity(_ value: UUID) -> UInt64 {
      if let token = identifiers[value] { return token }
      let token = UInt64(identifiers.count + 1); identifiers[value] = token; return token
    }
    var attempts: [DXTempoAttempt] = []
    for attempt in history.sorted(by: { $0.endedAt < $1.endedAt }) where
      attempt.settings.lessonVersion == lessonVersion && attempt.settings.tempoPolicyVersion == policyVersion {
      guard DrumxRunScore(attempt: attempt).isComplete,
        attempt.expected == attempt.settings.bars * 4, attempt.expected <= Int(Int32.max),
        attempt.extra <= Int(Int32.max) else { continue }
      var item = DXTempoAttempt()
      item.attempt_id = identity(attempt.id); item.conditions_id = token(Conditions(attempt.settings))
      item.policy_version = Int32(policyVersion); item.bpm = attempt.settings.tempo
      item.bars = Int32(attempt.settings.bars); item.guidance = Int32(attempt.settings.mode)
      item.live_feedback = attempt.settings.liveFeedback ? 1 : 0
      item.expected = Int32(attempt.expected); item.matched = Int32(attempt.matched)
      item.on_time = Int32(attempt.onTime); item.missed = Int32(attempt.missed); item.extra = Int32(attempt.extra)
      item.complete = 1; item.valid = 1
      attempts.append(item)
    }
    if let stopped, let stoppedID {
      var item = DXTempoAttempt()
      item.attempt_id = identity(stoppedID); item.conditions_id = 1
      item.policy_version = Int32(policyVersion); item.bpm = settings.tempo
      item.bars = Int32(settings.bars); item.guidance = Int32(settings.mode)
      item.live_feedback = settings.liveFeedback ? 1 : 0
      item.expected = stopped.total.expected; item.matched = stopped.total.matched
      item.on_time = stopped.total.on_time; item.missed = stopped.total.missed; item.extra = stopped.total.extra
      item.complete = 0; item.valid = 1
      attempts.append(item)
    }
    var context = DXTempoContext()
    context.conditions_id = 1; context.policy_version = Int32(policyVersion)
    context.bpm = settings.tempo; context.bars = Int32(settings.bars)
    context.guidance = Int32(settings.mode); context.live_feedback = settings.liveFeedback ? 1 : 0
    var decision = DXTempoDecision()
    let valid = attempts.withUnsafeBufferPointer {
      dx_tempo_evaluate($0.baseAddress, $0.count, &context, &decision)
    }
    return valid == 1 ? Recommendation(decision: decision) : nil
  }

  static func sameInputConditions(_ lhs: TakeSettings, _ rhs: TakeSettings) -> Bool {
    lhs.lessonVersion == rhs.lessonVersion && lhs.tempoPolicyVersion == rhs.tempoPolicyVersion
      && Conditions(lhs) == Conditions(rhs)
  }

  static func checkpointEarned(history: [LessonAttempt]) -> Bool {
    // Achievement may survive changing kit, but evidence from different kits is
    // never pooled. The recommendation itself is always scoped to today's kit.
    var seen = Set<Conditions>()
    for attempt in history where attempt.settings.lessonVersion == lessonVersion
      && attempt.settings.tempoPolicyVersion == policyVersion && attempt.settings.tempo == 72
      && attempt.settings.mode == 0 && attempt.settings.liveFeedback {
      let conditions = Conditions(attempt.settings)
      guard seen.insert(conditions).inserted else { continue }
      if evaluate(history: history, settings: attempt.settings)?.checkpointEarned == true { return true }
    }
    return false
  }
}
