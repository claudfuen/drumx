import AppKit

extension LabController {
  func makePlayerHistory() -> LessonHistory {
    // Test builds use their own bundle namespace, keeping their practice separate.
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = support.appendingPathComponent("Drumx", isDirectory: true)
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "org.drumx.timing-lab", isDirectory: true)
      .appendingPathComponent("History", isDirectory: true)
    return LessonHistory(key: progress.selectedHistoryKey,
      archiveURL: directory.appendingPathComponent(progress.selectedHistoryKey + ".json"))
  }

  var repeatedNotes: [DrumxLessonNote] {
    (0..<lessonBars).flatMap { bar in
      lesson.events.map { DrumxLessonNote(beat: $0.beat + Double(bar * 4), pad: $0.pad, hand: $0.hand, velocity: $0.velocity) }
    }
  }

  func handHint(pad: Int, seconds: Double) -> String? {
    let beat = (seconds * tempo / 60).truncatingRemainder(dividingBy: 4)
    return lesson.events.first { $0.pad == pad && abs($0.beat - beat) < 0.00001 }?.hand
  }

  func restorePlayer() {
    let resume = progress.selectedProfile.resume
    lesson = DrumxCourse.lesson(id: resume.lessonID) ?? DrumxCourse.lessons[0]
    tempo = min(144, max(48, resume.tempo)); mode = resume.mode; showLive = resume.liveFeedback
    lessonBars = [1, 4, 8].contains(resume.bars) ? resume.bars : 4
    if let version = resume.lessonVersion, version != lesson.version {
      tempo = lesson.suggestedBPM; mode = 0; showLive = true; lessonBars = 4
    }
    if mode == 1 && lessonBars == 1 { lessonBars = 4 }
    playerButton.title = progress.selectedProfile.name
    tempoSlider.doubleValue = tempo; tempoLabel.stringValue = "\(Int(tempo)) BPM"
    if modeMenu.numberOfItems > mode { modeMenu.selectItem(at: mode) }
    liveToggle.state = showLive ? .on : .off
    if lengthMenu.numberOfItems == 3 { lengthMenu.selectItem(at: [1, 4, 8].firstIndex(of: lessonBars) ?? 1) }
  }

  func saveResume() {
    // Merely navigating setup must not replace unreadable saved progress with its fallback.
    guard progress.selectedProfile.hasCompletedWelcome else { return }
    _ = progress.updateResume(PracticeResume(lessonID: lesson.id, tempo: tempo, mode: mode,
                                           liveFeedback: showLive, bars: lessonBars, lessonVersion: lesson.version))
    if let error = progress.lastError { setStatus(error) }
  }

  func buildWelcome() {
    let mark = DrumxWelcomeMark()
    mark.heightAnchor.constraint(equalToConstant: 146).isActive = true
    let title = label("Find your rhythm.", 52, weight: .bold, color: .labelColor)
    let description = NSTextField(wrappingLabelWithString:
      "A real drum kit. A clear pulse. A little progress every time you play.")
    description.font = .systemFont(ofSize: 19); description.textColor = .secondaryLabelColor
    welcomeName.font = .systemFont(ofSize: 16)
    welcomeName.widthAnchor.constraint(equalToConstant: 260).isActive = true
    welcomeName.placeholderString = "Your player name"
    welcomeName.setAccessibilityLabel("Your player name")
    welcomeName.target = self; welcomeName.action = #selector(finishWelcome)
    welcomeError.textColor = .systemOrange; welcomeError.font = .systemFont(ofSize: 12)
    let nameRow = row([label("PLAYING AS", 11, weight: .semibold), welcomeName], spacing: 18)
    let steps = row([
      column([label("01  GET COMFORTABLE", 11, weight: .semibold), label("Check the kit, or try A / S / Space.", 13)], spacing: 8), spacer(),
      column([label("02  BUILD YOUR FOUNDATION", 11, weight: .semibold), label("12 small lessons. Your own pace.", 13)], spacing: 8), spacer(),
      column([label("03  COME BACK STRONGER", 11, weight: .semibold), label("Your practice stays on this Mac.", 13)], spacing: 8),
    ])
    let actions = row([button("Let's play", #selector(finishWelcome), primary: true),
                       button("Connect my kit", #selector(showSetup)),
                       label("Keyboard is ready. No account needed.", 12)], spacing: 18)
    let stack = column([mark, title, description, nameRow, steps, welcomeError, actions], spacing: 24)
    [mark, description, steps].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    center(stack, in: welcomeView)
  }

  @objc func finishWelcome() {
    guard !transportActive else { return }
    guard progress.renameSelectedProfile(name: welcomeName.stringValue), progress.completeWelcome() else {
      welcomeError.stringValue = progress.lastError ?? "Choose a name between 1 and 32 characters."
      return
    }
    welcomeError.stringValue = ""
    playerButton.title = progress.selectedProfile.name
    saveResume(); showPage(.mainMenu)
    setStatus("Start with the pulse. Keep your hands comfortable and take breaks as you practise.")
  }

  var unlockState: DrumxUnlockState {
    DrumxUnlocks.evaluate(course: DrumxCourse.lessons, history: history.attempts, progress: progress)
  }

  func refreshCourse() {
    var statuses: [String: String] = [:]
    var practised = 0
    for definition in DrumxCourse.lessons {
      let attempts = history.attempts.filter { $0.settings.lessonVersion == definition.version && $0.matched > 0 }
      let played = !attempts.isEmpty || progress.practiceEvidence(lessonID: definition.id, version: definition.version) != nil
      let reading = progress.readingEvidence(lessonID: definition.id, version: definition.version) != nil
      let recall = attempts.contains { $0.settings.mode == 2 && !$0.settings.liveFeedback }
        || progress.recallEvidence(lessonID: definition.id, version: definition.version) != nil
      if played { practised += 1 }
      statuses[definition.id] = recall && reading ? "Read + recall tried" : recall ? "Recall tried"
        : reading && played ? "Practised + read" : played ? "Practised" : reading ? "Reading checked" : "New"
    }
    let state = unlockState
    courseView.update(lesson: lesson, player: progress.selectedProfile.name, statuses: statuses, practised: practised,
      availability: state.availableIDs, cleared: state.clearedIDs, lockReasons: state.reasonByID)
  }

  func selectLesson(_ id: String) {
    guard !transportActive, let selected = DrumxCourse.lesson(id: id) else { return }
    guard unlockState.availableIDs.contains(id) else {
      setStatus(unlockState.reasonByID[id] ?? "Complete the previous lesson to open this one."); return
    }
    if selected.id != lesson.id {
      lesson = selected; tempo = selected.suggestedBPM; mode = 0; showLive = true; lessonBars = 4
    }
    saveResume(); openCurrentLesson()
  }

  func openCurrentLesson() {
    guard !transportActive else { return }
    guard unlockState.availableIDs.contains(lesson.id) else { backToCourse(); return }
    resetCore(); showPage(.prepare)
    setStatus("\(lesson.practiceMinutes) of practice. Listen, count, repeat, then try less help.")
  }

  func refreshLesson() {
    lessonHeading.stringValue = lesson.title
    lessonSubtitle.stringValue = lesson.objective
    lessonExplanation.stringValue = lesson.explanation
    lessonPractice.stringValue = "\(lesson.practiceMinutes) · Count \(lesson.counts)"
    notation.lesson = lesson
    tempoSlider.doubleValue = tempo; tempoLabel.stringValue = "\(Int(tempo)) BPM"
    modeMenu.selectItem(at: mode); liveToggle.state = showLive ? .on : .off
    lengthMenu.selectItem(at: [1, 4, 8].firstIndex(of: lessonBars) ?? 1)
    let takes = history.attempts.filter { $0.settings.lessonVersion == lesson.version && $0.matched > 0 }
    let reading = progress.readingEvidence(lessonID: lesson.id, version: lesson.version) != nil
    let recall = takes.contains { $0.settings.mode == 2 && !$0.settings.liveFeedback }
      || progress.recallEvidence(lessonID: lesson.id, version: lesson.version) != nil
    lessonEvidence.stringValue = "\(takes.count) takes with matched hits  ·  Reading \(reading ? "checked" : "to try")  ·  Recall \(recall ? "tried" : "to try")"
    window.title = "Drumx · \(lesson.title)"
    let state = unlockState
    if !state.clearedIDs.contains(lesson.id) {
      lessonEvidence.stringValue += "  ·  Unlock next: 4+ bars, 80% caught"
    }
  }

  @objc func backToCourse() {
    guard !transportActive else { return }
    saveResume(); resetCore(); showPage(.course)
    window.title = "Drumx · Foundations"
    setStatus("Choose a chapter to explore. Open lessons are always available to revisit.")
  }

  @objc func nextLesson() {
    guard !transportActive else { return }
    if let index = DrumxCourse.lessons.firstIndex(where: { $0.id == lesson.id }), index + 1 < DrumxCourse.lessons.count {
      let next = DrumxCourse.lessons[index + 1]
      if unlockState.availableIDs.contains(next.id) { selectLesson(next.id) }
      else { setStatus(unlockState.reasonByID[next.id] ?? "Keep practising this pattern.") }
    } else {
      backToCourse()
      setStatus("You reached the last lesson. Revisit an earlier pattern with less help or a comfortable new tempo.")
    }
  }

  func refreshUnlockReview() {
    let state = unlockState
    guard let index = DrumxCourse.lessons.firstIndex(where: { $0.id == lesson.id }) else { return }
    if index + 1 < DrumxCourse.lessons.count {
      let next = DrumxCourse.lessons[index + 1]
      let available = state.availableIDs.contains(next.id)
      nextLessonButton.isEnabled = available
      nextLessonButton.title = available ? "Next lesson →" : "Next lesson locked"
      unlockCaption.stringValue = available ? "Open next: \(next.title)" : state.reasonByID[next.id] ?? "Finish 4+ bars and catch at least 80% of the notes."
    } else {
      nextLessonButton.isEnabled = true; nextLessonButton.title = "Explore foundations"
      unlockCaption.stringValue = "Keep building: revisit a pattern with less guidance."
    }
    nextLessonButton.needsDisplay = true
  }

  @objc func lengthChanged() {
    guard !transportActive else { return }
    lessonBars = [1, 4, 8][max(0, lengthMenu.indexOfSelectedItem)]
    if lessonBars == 1 && mode == 1 { mode = 0; modeMenu.selectItem(at: 0) }
    saveResume(); resetCore(); focusStage()
  }

  @objc func showPlayers() {
    guard !transportActive, playerWindow == nil, checkWindow == nil else { return }
    if currentPage == .settings { leaveSettings() }
    saveResume()
    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
    panel.title = "Who's playing?"; panel.appearance = window.appearance
    let content = LessonRootView(); content.controller = self; panel.contentView = content
    playerMenu.removeAllItems()
    for profile in progress.profiles {
      playerMenu.addItem(withTitle: profile.name); playerMenu.lastItem?.representedObject = profile.id
    }
    playerMenu.selectItem(at: progress.profiles.firstIndex(where: { $0.id == progress.selectedProfile.id }) ?? 0)
    playerMenu.target = self; playerMenu.action = #selector(changePlayer)
    playerMenu.setAccessibilityLabel("Player profile")
    newPlayerName.stringValue = progress.selectedProfile.name
    newPlayerName.placeholderString = "Name"; newPlayerName.setAccessibilityLabel("Player name")
    newPlayerName.widthAnchor.constraint(equalToConstant: 240).isActive = true
    playerError.stringValue = ""; playerError.textColor = .systemOrange
    let stack = column([
      label("Your own starting point.", 26, weight: .bold, color: .labelColor),
      label("Share a kit. Keep your practice and learning checks separate.", 14),
      row([label("PLAYER", 11), playerMenu]),
      row([newPlayerName, button("Rename", #selector(renamePlayer)), button("Add player", #selector(addPlayer))]),
      playerError, row([spacer(), button("Done", #selector(closePlayers), primary: true)]),
    ], spacing: 20)
    center(stack, in: content, width: 560)
    playerWindow = panel; window.beginSheet(panel); panel.makeFirstResponder(content)
  }

  @objc func changePlayer() {
    guard let id = playerMenu.selectedItem?.representedObject as? UUID, progress.selectProfile(id: id) else { return }
    history = makePlayerHistory(); restorePlayer(); closePlayers()
    resetCore(); showPage(progress.selectedProfile.hasCompletedWelcome ? .mainMenu : .welcome)
  }
  @objc func addPlayer() {
    guard progress.addProfile(name: newPlayerName.stringValue) != nil else { playerError.stringValue = progress.lastError ?? "Choose a different name."; return }
    history = makePlayerHistory(); restorePlayer(); closePlayers(); resetCore(); showPage(.welcome)
  }
  @objc func renamePlayer() {
    guard progress.renameSelectedProfile(name: newPlayerName.stringValue) else { playerError.stringValue = progress.lastError ?? "Check the name."; return }
    playerButton.title = progress.selectedProfile.name; closePlayers(); showPage(.mainMenu)
  }
  @objc func closePlayers() {
    if let panel = playerWindow { window.endSheet(panel); panel.orderOut(nil) }
    playerWindow = nil; focusStage()
  }

  @objc func showLearningCheck() {
    guard !transportActive, checkWindow == nil, playerWindow == nil else { return }
    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 490), styleMask: [.titled], backing: .buffered, defer: false)
    panel.title = "Lesson check"; panel.appearance = window.appearance
    let content = LessonRootView(); content.controller = self; panel.contentView = content
    let question = NSTextField(wrappingLabelWithString: lesson.readingQuestion)
    question.font = .systemFont(ofSize: 23, weight: .semibold)
    let choices = column(lesson.readingChoices.enumerated().map { index, choice in
      let answer = button(choice, #selector(answerReading(_:))); answer.tag = index
      return answer
    }, spacing: 8)
    checkFeedback.stringValue = "Choose an answer. You can revisit this check any time."
    checkFeedback.font = .systemFont(ofSize: 13)
    let technique = NSTextField(wrappingLabelWithString: lesson.techniqueTip)
    technique.font = .systemFont(ofSize: 13)
    techniqueCheck.target = self; techniqueCheck.action = #selector(recordTechnique)
    techniqueCheck.state = progress.techniqueEvidence(lessonID: lesson.id, version: lesson.version) == nil ? .off : .on
    techniqueCheck.isEnabled = techniqueCheck.state == .off
    let stack = column([label("CONNECT IT TO REAL DRUMMING", 11, weight: .semibold), question,
      choices, checkFeedback, technique, techniqueCheck,
      row([label("Self-check only. MIDI cannot verify your technique.", 11), spacer(), button("Done", #selector(closeLearningCheck), primary: true)])], spacing: 14)
    [question, checkFeedback, technique].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    center(stack, in: content, width: 672)
    checkWindow = panel; window.beginSheet(panel); panel.makeFirstResponder(content)
  }
  @objc func answerReading(_ sender: NSButton) {
    if sender.tag == lesson.readingAnswer {
      _ = progress.markReadingChecked(lessonID: lesson.id, version: lesson.version)
      checkFeedback.stringValue = progress.lastError ?? "That's it. Reading check saved. Count it aloud as you play."
    } else {
      checkFeedback.stringValue = "Not quite. Count \(lesson.counts), think through the pattern, then try again."
    }
  }
  @objc func recordTechnique() {
    guard techniqueCheck.state == .on else { return }
    if progress.markTechniqueChecked(lessonID: lesson.id, version: lesson.version) { techniqueCheck.isEnabled = false }
    if let error = progress.lastError { checkFeedback.stringValue = error }
  }
  @objc func closeLearningCheck() {
    if let panel = checkWindow { window.endSheet(panel); panel.orderOut(nil) }
    checkWindow = nil
    if currentPage == .review { refreshUnlockReview() } else { refreshLesson() }
    focusStage()
  }

  func refreshKitCheck() {
    let names = ["Hi-hat", "Snare", "Kick"]
    kitCheckStatus.stringValue = names.enumerated().map { checkedPads.contains($0.offset) ? "\($0.element) received" : "\($0.element) waiting" }.joined(separator: "   ·   ")
  }
}
