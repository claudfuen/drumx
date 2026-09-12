import AppKit

extension LabController {
  func selectKitPad(_ pad: Int) {
    guard (0..<3).contains(pad) else { return }
    kitSetup.cancelLearning(); learning = nil; io.setMIDILearnActive(false)
    selectedKitPad = pad; refreshKitInspector()
  }
  func refreshKitInspector() {
    let names = ["Hi-hat", "Snare", "Kick"]
    mappingTitle.stringValue = names[selectedKitPad]
    mappingNotes.stringValue = mappings[selectedKitPad].isEmpty ? "No MIDI notes assigned" : "MIDI notes  " + mappings[selectedKitPad].map(String.init).joined(separator: " · ")
    kitVisual.selectedPad = selectedKitPad
    kitVisual.learningPad = kitSetup.pendingPad
    mapNoteButton.isEnabled = kitSetup.isMIDISelected && kitSetup.pendingPad == nil
    cancelMapButton.isHidden = kitSetup.pendingPad == nil
    mapNoteButton.tag = selectedKitPad
    if let pad = kitSetup.pendingPad {
      mappingHelp.stringValue = "Strike your \(names[pad].lowercased()) once. This adds its note and keeps existing articulations."
    } else {
      mappingHelp.stringValue = kitSetup.isMIDISelected
        ? "Select a drum in the picture to inspect its notes. Add another note for a rim or hi-hat articulation."
        : "Choose your MIDI module above. Keyboard previews let you try the sounds; they do not verify your drum kit."
    }
    if let error = kitSetup.lastError { mappingHelp.stringValue = error }
    refreshKitCheck()
  }
  @objc func learnSelectedPad() { learnMapping(mapNoteButton) }
  @objc func cancelKitMapping() {
    kitSetup.cancelLearning(); learning = nil; io.setMIDILearnActive(false); refreshKitInspector()
  }
  @objc func leaveKitForLesson() {
    leaveSettings()
    guard progress.selectedProfile.hasCompletedWelcome else { showPage(.welcome); return }
    saveResume(); openCurrentLesson()
  }
  @objc func testDrumSounds() {
    guard !transportActive else { return }
    guard drumSound else { soundStatus.stringValue = "Enable Drumx drum sounds above to test them."; return }
    let hits = [DrumxDemoHit(pad: 0, beat: 0, velocity: 100),
      DrumxDemoHit(pad: 1, beat: 1, velocity: 108), DrumxDemoHit(pad: 2, beat: 2, velocity: 112)]
    if !io.startDemo(bpm: 120, firstBeatHostTime: DrumxIO.hostNowSeconds() + 0.1, durationBeats: 4, hits: hits) {
      soundStatus.stringValue = "Audio preview could not start. Check this Mac's audio output."
    }
  }
  @objc func kitMenuChanged() {
    kitMenusEnabled = kitMenuToggle.state == .on
    UserDefaults.standard.set(kitMenusEnabled, forKey: "drumx.kitMenuControls")
    menuInput.reset(at: DrumxIO.hostNowSeconds()); updateKitMenuLegend()
  }

  /// MIDI commands never enter the playing, setup, or teaching-check handlers.
  /// Captured MIDI time is used so a queued musical hit cannot confirm a later menu.
  func routeKitMenu(pad: Int, velocity: Int, at time: Double) -> Bool {
    guard kitMenusEnabled, kitSetup.isMIDISelected, !transportActive,
      kitSetup.pendingPad == nil, playerWindow == nil, checkWindow == nil,
      [.mainMenu, .prepare, .review, .pause].contains(currentPage) else { return false }
    if let command = menuInput.receive(pad: pad, velocity: velocity, at: time) {
      if currentPage == .mainMenu {
        switch command {
        case .previous: mainMenuView.moveSelection(-1)
        case .next: mainMenuView.moveSelection(1)
        case .activate: mainMenuView.activateSelection()
        }
      } else {
        let available = kitMenuActions.filter { !$0.isHidden && $0.isEnabled }
        if !available.isEmpty {
          kitMenuIndex = kitSelectedAction.flatMap { selected in available.firstIndex { $0 === selected } } ?? 0
          switch command {
          case .previous: kitMenuIndex = (kitMenuIndex + available.count - 1) % available.count
          case .next: kitMenuIndex = (kitMenuIndex + 1) % available.count
          case .activate: available[kitMenuIndex].performClick(nil)
          }
          if command != .activate { selectKitMenuAction() }
        }
      }
    }
    updateKitMenuLegend()
    return true
  }
  func resetKitMenuFocus() {
    kitMenuActions.forEach { $0.selectedByKit = false }
    switch currentPage {
    case .prepare: kitMenuActions = [startButton, hearButton, courseButton]
    case .review: kitMenuActions = [retryButton, nextLessonButton, challengeButton, loopButton, courseButton]
    case .pause: kitMenuActions = [pauseRestart, pauseReviewButton, pauseHome]
    default: kitMenuActions = []
    }
    kitMenuIndex = 0; kitSelectedAction = nil
    menuInput.reset(at: DrumxIO.hostNowSeconds())
    selectKitMenuAction(); updateKitMenuLegend()
  }
  private func selectKitMenuAction() {
    let available = kitMenuActions.filter { !$0.isHidden && $0.isEnabled }
    for button in kitMenuActions { button.selectedByKit = false }
    guard kitMenusEnabled, kitSetup.isMIDISelected, !available.isEmpty else { return }
    kitMenuIndex = min(kitMenuIndex, available.count - 1)
    kitSelectedAction = available[kitMenuIndex]
    available[kitMenuIndex].selectedByKit = true
  }
  func updateKitMenuLegend() {
    guard kitMenusEnabled, kitSetup.isMIDISelected, !transportActive,
      [.mainMenu, .prepare, .review, .pause].contains(currentPage) else { return }
    keyboardLegend.stringValue = menuInput.isKickArmed(at: DrumxIO.hostNowSeconds())
      ? "KICK again to choose · HI-HAT previous · SNARE next"
      : "HI-HAT previous · SNARE next · KICK ×2 choose"
  }
  @objc func togglePracticeOptions() {
    guard !transportActive, let controls = practiceControls else { return }
    controls.isHidden.toggle()
    optionsButton.title = controls.isHidden ? "Practice options" : "Hide options"
    focusStage()
  }
  func refreshPracticeSummary() {
    let seconds = Int((Double(lessonBars * 4) * 60 / tempo).rounded())
    practiceSummary.stringValue = "\(seconds) seconds of playing · \(lessonBars) bars · \(Int(tempo)) BPM · \(modeNames[mode])"
  }
}
