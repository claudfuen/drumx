import AppKit

extension LabController {
  var isGuidedPulse: Bool { lesson.version == DrumxTempoCoach.lessonVersion && !pulsePractice.isFreePractice }
  var isPulseLesson: Bool { lesson.version == DrumxTempoCoach.lessonVersion }

  func pulseTakeSettings() -> TakeSettings {
    TakeSettings(tempo: tempo, mode: mode, liveFeedback: showLive, bars: lessonBars,
      calibrationMS: calibrationMS,
      inputIdentity: io.selectedSourceID.map { "midi:\($0)" } ?? "keyboard", mapping: mappings,
      lessonVersion: lesson.version, handHints: showHands,
      tempoPolicyVersion: isPulseLesson ? 1 : nil, monitoring: drumSound,
      readinessPolicyVersion: isPulseLesson ? nil : 1)
  }

  var pulseRecommendation: DrumxTempoCoach.Recommendation? {
    guard isPulseLesson else { return nil }
    return DrumxTempoCoach.evaluate(history: history.attempts, settings: pulseTakeSettings())
  }

  func restorePulseRoute() {
    pulsePractice = progress.selectedProfile.pulsePractice ?? DrumxPulsePractice.initial(
      resume: progress.selectedProfile.resume,
      existingPlayer: progress.selectedProfile.hasCompletedWelcome || !history.attempts.isEmpty)
    guard isPulseLesson else { return }
    applyPulseCondition(pulsePractice.isFreePractice ? pulsePractice.free : pulsePractice.guided)
  }

  func applyPulseCondition(_ resume: PracticeResume) {
    let plan = DrumxPracticePlan.restore(resume: resume, lesson: lesson)
    tempo = plan.tempo; mode = plan.mode; showLive = plan.liveFeedback; lessonBars = plan.bars
  }

  func storePulseCondition() {
    guard isPulseLesson else { return }
    let current = PracticeResume(tempo: tempo, mode: mode, liveFeedback: showLive,
      bars: lessonBars, lessonVersion: lesson.version, sessionFormatVersion: 1)
    if pulsePractice.isFreePractice { pulsePractice.free = current }
    else { pulsePractice.guided = current }
    _ = progress.updatePulsePractice(pulsePractice)
  }

  /// Called only from an explicit play/listen action. Review can describe the next
  /// condition without changing the completed take or today's active transport.
  func applyNextGuidedCondition() {
    guard isGuidedPulse, let recommendation = pulseRecommendation else { return }
    applyPulseCondition(recommendation.next)
  }

  @objc func togglePulseRoute() {
    guard isPulseLesson, !transportActive else { return }
    storePulseCondition()
    pulsePractice.isFreePractice.toggle()
    applyPulseCondition(pulsePractice.isFreePractice ? pulsePractice.free : pulsePractice.guided)
    _ = progress.updatePulsePractice(pulsePractice)
    saveResume(); resetCore(); showPage(.prepare)
  }

  @objc func openFreePractice() {
    guard !transportActive else { return }
    if isGuidedPulse { togglePulseRoute() }
    else { backToLesson() }
    practiceControls?.isHidden = false
    optionsButton.title = "Hide options"
    resetKitMenuFocus()
  }

  @objc func repeatPulse() { startTake(advanceGuided: false) }

  @objc func startPulseCheckpoint() {
    guard isGuidedPulse, !transportActive else { return }
    applyPulseCondition(PracticeResume(tempo: 72, lessonVersion: lesson.version, sessionFormatVersion: 1))
    startTake(advanceGuided: false)
  }

  @objc func useLessonCheckpointSettings() {
    guard !isPulseLesson, !transportActive else { return }
    tempo = lesson.suggestedBPM; lessonBars = 16; mode = 0; showLive = true
    saveResume(); resetCore(); showPage(.prepare)
  }

  @objc func startPulseStretch() {
    guard isGuidedPulse, let recommendation = pulseRecommendation,
      recommendation.checkpointEarned else { return }
    let pace = tempo >= 84 ? 96.0 : 84.0
    applyPulseCondition(PracticeResume(tempo: pace, lessonVersion: lesson.version, sessionFormatVersion: 1))
    startTake(advanceGuided: false)
  }

  func refreshPulsePreparation() {
    practiceRouteButton.isHidden = !isPulseLesson
    practiceRouteButton.title = isGuidedPulse ? "Free practice" : "Return to guided"
    practiceRouteButton.setAccessibilityLabel(isGuidedPulse ? "Open free practice with separate tempo and assistance settings" : "Return to app-guided pulse practice")
    optionsButton.isHidden = isGuidedPulse
    pulseCheckpointButton.isHidden = isPulseLesson && !isGuidedPulse
    let checkpointEarned = pulseRecommendation?.checkpointEarned ?? false
    let optionalPace = tempo >= 84 ? 96 : 84
    pulseCheckpointButton.title = checkpointEarned ? "Try \(optionalPace) BPM · optional" : "Try 72 BPM"
    pulseCheckpointButton.action = checkpointEarned ? #selector(startPulseStretch) : #selector(startPulseCheckpoint)
    pulseCheckpointButton.setAccessibilityLabel(checkpointEarned
      ? "Try the optional \(optionalPace) BPM challenge" : "Try the guided 72 BPM checkpoint directly")
    if !isPulseLesson {
      pulseCheckpointButton.title = "Use checkpoint settings"
      pulseCheckpointButton.action = #selector(useLessonCheckpointSettings)
      pulseCheckpointButton.setAccessibilityLabel("Prepare a guided 16-bar checkpoint at \(Int(lesson.suggestedBPM)) BPM")
    }
    pulseCoachView.isHidden = !isGuidedPulse
    practiceSummary.isHidden = isGuidedPulse
    lessonEvidence.isHidden = isGuidedPulse
    if isGuidedPulse { practiceControls?.isHidden = true }
    startButton.action = #selector(beginLesson)
    guard isPulseLesson, let recommendation = pulseRecommendation else {
      startButton.title = "Start playing"; return
    }
    if isGuidedPulse {
      startButton.title = recommendation.actionTitle
      if recommendation.decision.action == Int32(DX_TEMPO_CONTINUE.rawValue) {
        startButton.title = "Continue to next lesson"; startButton.action = #selector(nextLesson)
      }
      let next = recommendation.next
      practiceSummary.stringValue = "GUIDED PULSE  ·  \(Int(next.tempo)) BPM next  ·  16 bars  ·  \(Int((3840 / next.tempo).rounded())) seconds"
      pulseCoachView.update(bpm: next.tempo, title: recommendation.reason,
        detail: "16 bars · \(Int((3840 / next.tempo).rounded())) seconds · Pace stays fixed during the take",
        checkpoint: recommendation.checkpointEarned, recalled: recommendation.recallEarned)
    } else {
      startButton.title = "Start free practice"
      practiceSummary.stringValue = "FREE PRACTICE  ·  \(Int(tempo)) BPM  ·  \(lessonBars) bars  ·  \(modeNames[mode])"
      lessonEvidence.stringValue = "Free practice keeps its own settings. Checkpoint evidence requires 72 BPM, 16 bars, Guided notes and live feedback."
    }
    startButton.needsDisplay = true; practiceRouteButton.needsDisplay = true
  }

  func refreshPulseReview(stopped: DXSnapshot?, takeID: UUID) {
    repeatPulseButton.isHidden = !isGuidedPulse
    slowButton.isHidden = isGuidedPulse
    loopButton.isHidden = false
    loopButton.title = isGuidedPulse ? "Free practice" : lessonBars == 1 ? "Back to four bars" : "Work on one bar"
    loopButton.action = isGuidedPulse ? #selector(openFreePractice) : #selector(repairBar)
    challengeButton.isHidden = false
    challengeButton.action = #selector(nextChallenge)
    retryButton.title = "Play again"
    retryButton.action = #selector(retryTake)
    guard isGuidedPulse, let recommendation = DrumxTempoCoach.evaluate(
      history: history.attempts, settings: pulseTakeSettings(), stopped: stopped, stoppedID: takeID)
    else { return }
    retryButton.title = recommendation.actionTitle
    if recommendation.decision.action == Int32(DX_TEMPO_CHECK_INPUT.rawValue) {
      retryButton.title = "Check kit & sound"; retryButton.action = #selector(showSetup)
    }
    if recommendation.decision.action == Int32(DX_TEMPO_CONTINUE.rawValue) {
      retryButton.title = "Continue to next lesson"; retryButton.action = #selector(nextLesson)
    }
    reviewDetail.stringValue = recommendation.reason + " " + recommendation.achievement
    repeatPulseButton.title = "Repeat \(Int(tempo)) BPM"
    challengeButton.isHidden = !recommendation.checkpointEarned
    let stretch = tempo >= 84 ? 96 : 84
    challengeButton.title = "Try \(stretch) BPM · optional"
    challengeButton.action = #selector(startPulseStretch)
    retryButton.needsDisplay = true; loopButton.needsDisplay = true; challengeButton.needsDisplay = true
  }
}
