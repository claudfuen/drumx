import AppKit

extension LabController {
  func buildSettings() {
    settingsButtons = ["Your kit", "Sound", "Playing", "Players"].enumerated().map { index, name in
      let tab = button(name, #selector(selectSettingsSection(_:))); tab.tag = index; tab.quiet = true
      return tab
    }
    sourceMenu.target = self; sourceMenu.action = #selector(sourceChanged)
    sourceMenu.setAccessibilityLabel("MIDI input")
    sourceMenu.heightAnchor.constraint(equalToConstant: 38).isActive = true
    mapNoteButton.target = self; mapNoteButton.action = #selector(learnSelectedPad)
    mapNoteButton.primary = true; mapNoteButton.isBordered = false
    cancelMapButton.target = self; cancelMapButton.action = #selector(cancelKitMapping)
    cancelMapButton.isBordered = false
    mappingTitle.font = .systemFont(ofSize: 24, weight: .semibold)
    mappingNotes.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    mappingNotes.textColor = .secondaryLabelColor
    mappingHelp.font = .systemFont(ofSize: 13); mappingHelp.textColor = .secondaryLabelColor
    mappingHelp.maximumNumberOfLines = 3
    kitCheckStatus.font = .systemFont(ofSize: 13, weight: .medium)
    kitCheckStatus.textColor = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
    let kitDetails = column([
      label("Connect. Strike. Play.", 26, weight: .semibold, color: .labelColor),
      sourceMenu, mappingTitle, mappingNotes,
      row([mapNoteButton, cancelMapButton], spacing: 8), mappingHelp, kitCheckStatus,
      button("Go to my lesson →", #selector(leaveKitForLesson)),
    ], spacing: 16)
    [sourceMenu, mappingHelp].forEach { $0.widthAnchor.constraint(equalTo: kitDetails.widthAnchor).isActive = true }
    let kit = splitSettings(kitVisual, kitDetails)
    kitVisual.onSelect = { [weak self] pad in self?.selectKitPad(pad) }

    soundToggle.target = self; soundToggle.action = #selector(soundChanged)
    soundToggle.title = "Drumx drum sounds"
    volumeSlider.target = self; volumeSlider.action = #selector(volumeChanged)
    volumeSlider.widthAnchor.constraint(equalToConstant: 230).isActive = true
    volumeSlider.setAccessibilityLabel("Drum and demonstration volume")
    soundStatus.font = .systemFont(ofSize: 12); soundStatus.textColor = .secondaryLabelColor
    let soundRows = column([
      settingsRow("Hear your hits", detail: "Turn off when you listen to the module's own sounds.", control: soundToggle),
      settingsRow("Drums & demonstrations", detail: "Keep the click and your drums comfortable to hear together.", control: volumeSlider),
      settingsRow("Try the sound", detail: "Plays a short hi-hat, snare, and kick preview when Drumx sounds are enabled.",
        control: button("Test drums", #selector(testDrumSounds))),
      soundStatus,
    ], spacing: 18)
    let sound = settingsContent(title: "Listen your way.", detail: "App sounds or module sounds. One clear listening route.", body: soundRows,
      footnote: "Audio uses this Mac's selected output. USB MIDI sends notes, not your module's audio.")

    handsToggle.target = self; handsToggle.action = #selector(handsChanged(_:))
    handsToggle.title = "Sticking hints"
    kitMenuToggle.target = self; kitMenuToggle.action = #selector(kitMenuChanged)
    offsetField.widthAnchor.constraint(equalToConstant: 80).isActive = true
    offsetField.target = self; offsetField.action = #selector(offsetChanged)
    offsetField.setAccessibilityLabel("Input scoring offset in milliseconds")
    let playingRows = column([
      settingsRow("Play from the kit", detail: "Hi-hat: previous. Snare: next. Kick twice: choose. Menus only.", control: kitMenuToggle),
      settingsRow("Hand suggestions", detail: "R / L are suggestions. MIDI cannot verify your hands.", control: handsToggle),
      settingsRow("Input scoring offset", detail: "Leave at 0 to start. Positive moves scoring earlier; negative moves it later.",
        control: row([offsetField, label("ms", 13)])),
    ], spacing: 18)
    let playing = settingsContent(title: "Stay in the groove.", detail: "Make the controls work around your playing.", body: playingRows,
      footnote: "Scoring offset is limited to ±200 ms and does not change sound latency. Motion follows your Mac's accessibility setting.")

    settingsPlayer.font = .systemFont(ofSize: 24, weight: .semibold)
    let playerRows = column([
      settingsRow("Who's playing?", detail: "Each player keeps their lesson, stars, settings, and learning checks.", control: button("Manage players", #selector(showPlayers))),
      settingsRow("Progress stays here", detail: "Completed takes save automatically on this Mac. No account needed.", control: label("LOCAL SAVE", 11, weight: .semibold)),
      settingsRow("One kit, separate journeys", detail: "Kit mappings, sound, and scoring offset are shared. Practice progress belongs to the player.", control: label("UP TO 8 PLAYERS", 11, weight: .semibold)),
    ], spacing: 18)
    let players = settingsContent(title: "Your own starting point.", detail: "Share the drums. Keep your progress.", body: column([settingsPlayer, playerRows], spacing: 22),
      footnote: "Cloud sync and profile deletion are not available in this build.")
    settingsPanels = [kit, sound, playing, players]
    settingsView.install(tabs: settingsButtons, panels: settingsPanels)
    updateSettingsSection(); refreshKitInspector()
  }

  private func setupCopy(_ text: String) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: 13); field.textColor = .secondaryLabelColor
    field.maximumNumberOfLines = 3
    return field
  }
  private func settingsRow(_ title: String, detail: String, control: NSView) -> NSView {
    let card = DrumxSettingsSurface()
    let copy = column([label(title, 17, weight: .medium, color: .labelColor), setupCopy(detail)], spacing: 7)
    for child in [copy, control] { child.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(child) }
    copy.arrangedSubviews.last?.widthAnchor.constraint(equalTo: copy.widthAnchor).isActive = true
    NSLayoutConstraint.activate([
      card.heightAnchor.constraint(equalToConstant: 92),
      copy.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
      copy.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      control.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
      control.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      copy.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -32),
    ])
    return card
  }
  private func settingsContent(title: String, detail: String, body: NSStackView, footnote: String) -> NSView {
    let panel = NSView()
    let heading = label(title, 28, weight: .semibold, color: .labelColor)
    let description = setupCopy(detail), foot = setupCopy(footnote)
    let stack = column([heading, description, body, foot], spacing: 16)
    body.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
    for item in [description, body, foot] { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    stack.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
    ])
    return panel
  }
  private func splitSettings(_ visual: NSView, _ details: NSStackView) -> NSView {
    let panel = DrumxSettingsSurface()
    [visual, details].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview($0) }
    NSLayoutConstraint.activate([
      visual.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
      visual.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
      visual.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
      visual.widthAnchor.constraint(equalTo: panel.widthAnchor, multiplier: 0.50, constant: -32),
      details.leadingAnchor.constraint(equalTo: visual.trailingAnchor, constant: 32),
      details.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -28),
      details.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
    ])
    return panel
  }
  @objc func selectSettingsSection(_ sender: NSButton) {
    leaveSettings(); settingsSection = sender.tag
    updateSettingsSection(); focusStage()
  }
  private func updateSettingsSection() {
    for (index, panel) in settingsPanels.enumerated() { panel.isHidden = index != settingsSection }
    for (index, item) in settingsButtons.enumerated() {
      item.primary = index == settingsSection
      item.setAccessibilityValue(index == settingsSection ? "Selected" : "")
      item.needsDisplay = true
    }
  }

  @objc func goMainMenu() {
    guard !transportActive else { pausePractice(); return }
    if currentPage == .settings { leaveSettings() }
    saveResume(); resetCore()
    showPage(progress.selectedProfile.hasCompletedWelcome ? .mainMenu : .welcome)
  }
  @objc func goBack() {
    switch currentPage {
    case .settings: closeSetup()
    case .prepare: backToCourse()
    case .review: backToLesson()
    default: goMainMenu()
    }
  }

  func buildPauseMenu() {
    pauseTitle.font = .systemFont(ofSize: 46, weight: .bold)
    pauseDetail.font = .systemFont(ofSize: 17); pauseDetail.textColor = .secondaryLabelColor
    pauseReviewButton.target = self; pauseReviewButton.action = #selector(reviewPaused)
    pauseReviewButton.isBordered = false
    pauseRestart.target = self; pauseRestart.action = #selector(restartPaused); pauseRestart.primary = true; pauseRestart.isBordered = false
    pauseHome.target = self; pauseHome.action = #selector(goMainMenu); pauseHome.isBordered = false
    let stack = column([
      label("TAKE A BREATH", 11, weight: .semibold), pauseTitle, pauseDetail,
      row([pauseRestart, pauseReviewButton, pauseHome]),
    ], spacing: 24)
    pauseDetail.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    center(stack, in: pauseView)
  }
  func pausePractice() {
    guard transportActive else { return }
    pausedDemo = demonstrating
    stopTake()
    // The core can complete during its final input-delivery grace period.
    // Keep that saved result on screen instead of describing it as interrupted.
    if !pausedDemo && finishedNaturally { return }
    pauseTitle.stringValue = pausedDemo ? "Listening paused." : "Practice paused."
    pauseDetail.stringValue = pausedDemo
      ? "Listen again from the beginning, with a fresh count-in."
      : "Restart from the beginning with a fresh count-in, or review the hits so far. An unfinished take doesn't change your records."
    pauseReviewButton.isHidden = pausedDemo
    showPage(.pause)
  }
  @objc func restartPaused() {
    if pausedDemo { hearDemo() } else { startTake() }
  }
  @objc func reviewPaused() {
    showPage(.review)
    setStatus("Review the hits so far. Restart a complete phrase when you are ready.")
  }
}
