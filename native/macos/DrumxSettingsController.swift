import AppKit

extension LabController {
  func buildSettings() {
    settingsButtons = ["Kit", "Sound", "Controls", "Players"].enumerated().map { index, name in
      let tab = button(name, #selector(selectSettingsSection(_:))); tab.tag = index; tab.quiet = true
      tab.setButtonType(.radio)
      tab.setAccessibilityLabel("\(name) settings")
      return tab
    }
    sourceMenu.target = self; sourceMenu.action = #selector(sourceChanged)
    sourceMenu.setAccessibilityLabel("MIDI input")
    sourceMenu.setAccessibilityHelp("Choose a connected drum module, or use the keyboard preview.")
    sourceMenu.toolTip = "MIDI selects the drum module. Keyboard preview stays available for setup."
    sourceMenu.font = .systemFont(ofSize: 14, weight: .medium)
    sourceMenu.heightAnchor.constraint(equalToConstant: 44).isActive = true
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
      label("MIDI input", 24, weight: .semibold, color: .labelColor),
      sourceMenu, mappingTitle, mappingNotes,
      row([mapNoteButton, cancelMapButton], spacing: 8), mappingHelp, kitCheckStatus,
      button("Open current lesson", #selector(leaveKitForLesson)),
    ], spacing: 18)
    [sourceMenu, mappingHelp].forEach { $0.widthAnchor.constraint(equalTo: kitDetails.widthAnchor).isActive = true }
    let kit = splitSettings(kitVisual, kitDetails)
    kitVisual.onSelect = { [weak self] pad in self?.selectKitPad(pad) }

    soundToggle.target = self; soundToggle.action = #selector(soundChanged)
    soundToggle.title = "Drumx drum sounds"
    soundToggle.font = .systemFont(ofSize: 13, weight: .medium)
    soundToggle.setAccessibilityHelp("Turn off when listening to your drum module's own sounds. This does not mute the practice click.")
    volumeSlider.target = self; volumeSlider.action = #selector(volumeChanged)
    volumeSlider.widthAnchor.constraint(equalToConstant: 196).isActive = true
    volumeSlider.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let volumeValue = label("", 13, weight: .medium, color: .labelColor)
    volumeValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    volumeValue.alignment = .right
    volumeValue.widthAnchor.constraint(equalToConstant: 46).isActive = true
    volumeValue.setAccessibilityElement(false)
    volumeSlider.attachValueLabel(volumeValue) { "\(Int(($0 * 100).rounded()))%" }
    let volumeControl = row([volumeSlider, volumeValue], spacing: 12)
    volumeSlider.setAccessibilityLabel("Drum and demonstration volume")
    soundStatus.font = .systemFont(ofSize: 12); soundStatus.textColor = .secondaryLabelColor
    soundStatus.cell?.usesSingleLineMode = false; soundStatus.cell?.wraps = true
    soundStatus.maximumNumberOfLines = 2
    soundStatus.setAccessibilityLabel("Drum sound status")
    let testSound = button("Test drums", #selector(testDrumSounds)); testSound.primary = true
    let soundRows = column([
      settingsRow("Drum sounds", detail: "Turn off when listening to your module's own sounds.", control: soundToggle),
      settingsRow("Volume", detail: "Applies to drum hits and demonstrations.", control: volumeControl),
      settingsRow("Sound check", detail: "Preview the hi-hat, snare, and kick with Drumx sounds enabled.", control: testSound),
      soundStatus,
    ], spacing: 0)
    let sound = settingsContent(title: "Audio", body: soundRows,
      footnote: "Audio uses this Mac's selected output. USB MIDI sends notes, not your module's audio.")

    handsToggle.target = self; handsToggle.action = #selector(handsChanged(_:))
    handsToggle.title = "Sticking hints"
    handsToggle.font = .systemFont(ofSize: 13, weight: .medium)
    handsToggle.setAccessibilityHelp("Displays suggested right and left hands. Drum MIDI does not identify the hand used.")
    kitMenuToggle.target = self; kitMenuToggle.action = #selector(kitMenuChanged)
    kitMenuToggle.font = .systemFont(ofSize: 13, weight: .medium)
    kitMenuToggle.setAccessibilityHelp("Available in the main menu, lesson preparation, review and pause. Settings and the learning path use keyboard or pointer controls.")
    let offsetText = offsetField.stringValue
    offsetField.cell = DrumxTextFieldCell(textCell: offsetText)
    offsetField.focusRingType = .none
    offsetField.heightAnchor.constraint(equalToConstant: 44).isActive = true
    offsetField.widthAnchor.constraint(equalToConstant: 80).isActive = true
    offsetField.target = self; offsetField.action = #selector(offsetChanged)
    offsetField.setAccessibilityLabel("Input scoring offset in milliseconds")
    let playingRows = column([
      settingsRow("Kit navigation", detail: "Hi-hat: previous action. Snare: next. Kick twice: choose. Available in the main menu, lesson, review, and pause.", control: kitMenuToggle),
      settingsRow("Hand suggestions", detail: "R / L are suggestions. MIDI cannot verify your hands.", control: handsToggle),
      settingsRow("Input scoring offset", detail: "Leave at 0 to start. Positive moves scoring earlier; negative moves it later.",
        control: row([offsetField, label("ms", 13)])),
    ], spacing: 0)
    let playing = settingsContent(title: "Playing controls", body: playingRows,
      footnote: "Scoring offset is limited to ±200 ms and does not change sound latency. Motion follows your Mac's accessibility setting.")

    settingsPlayer.font = .systemFont(ofSize: 24, weight: .semibold)
    let managePlayers = button("Manage players", #selector(showPlayers)); managePlayers.primary = true
    let playerRows = column([
      settingsRow("Active player", detail: "Lesson progress, stars, and learning checks are kept for each player.", control: managePlayers),
      settingsRow("Saved progress", detail: "Completed takes save automatically on this Mac. No account needed.", control: label("LOCAL SAVE", 11, weight: .semibold)),
      settingsRow("Shared setup", detail: "Kit mappings, sound, and scoring offset are shared between players.", control: label("UP TO 8 PLAYERS", 11, weight: .semibold)),
    ], spacing: 0)
    let players = settingsContent(title: "Players", body: column([settingsPlayer, playerRows], spacing: 16),
      footnote: "Cloud sync and profile deletion are not available in this build.")
    settingsPanels = [kit, sound, playing, players]
    settingsView.install(tabs: settingsButtons, panels: settingsPanels)
    updateSettingsSection(); refreshKitInspector()
  }

  private func setupCopy(_ text: String) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: 14); field.textColor = .secondaryLabelColor
    field.maximumNumberOfLines = 3
    field.setContentHuggingPriority(.required, for: .vertical)
    return field
  }
  private func settingsRow(_ title: String, detail: String, control: NSView) -> NSView {
    let card = DrumxSettingsRowSurface()
    let copy = column([label(title, 17, weight: .semibold, color: .labelColor), setupCopy(detail)], spacing: 6)
    copy.setHuggingPriority(.required, for: .vertical)
    let accessory = NSView()
    let measuredWidth = max(0, control.intrinsicContentSize.width, control.fittingSize.width)
    let controlWidth = min(260, max(control is DrumxToggle ? 230 : control is NSButton ? 160 : 0, measuredWidth))
    control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    control.setContentHuggingPriority(.required, for: .vertical)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    control.translatesAutoresizingMaskIntoConstraints = false
    accessory.addSubview(control)
    card.setAccessibilityRole(.group); card.setAccessibilityLabel(title)
    for child in [copy, accessory] { child.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(child) }
    copy.arrangedSubviews.last?.widthAnchor.constraint(equalTo: copy.widthAnchor).isActive = true
    let preferredHeight = card.heightAnchor.constraint(equalToConstant: 96)
    preferredHeight.priority = NSLayoutConstraint.Priority(999)
    NSLayoutConstraint.activate([
      preferredHeight,
      card.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
      copy.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      copy.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      copy.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 18),
      copy.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -18),
      accessory.widthAnchor.constraint(equalToConstant: 260),
      accessory.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      accessory.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
      accessory.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
      control.widthAnchor.constraint(equalToConstant: controlWidth),
      control.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
      control.centerYAnchor.constraint(equalTo: accessory.centerYAnchor),
      control.topAnchor.constraint(greaterThanOrEqualTo: accessory.topAnchor),
      control.bottomAnchor.constraint(lessThanOrEqualTo: accessory.bottomAnchor),
      copy.trailingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: -40),
    ])
    return card
  }
  private func settingsContent(title: String, body: NSStackView, footnote: String) -> NSView {
    let panel = NSView()
    let heading = label(title, 24, weight: .semibold, color: .labelColor)
    let foot = setupCopy(footnote)
    let stack = column([heading, body, foot], spacing: 20)
    heading.setContentHuggingPriority(.required, for: .vertical)
    stack.setHuggingPriority(.required, for: .vertical)
    func alignColumn(_ column: NSStackView) {
      column.setHuggingPriority(.required, for: .vertical)
      for child in column.arrangedSubviews {
        child.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        if let nested = child as? NSStackView, nested.orientation == .vertical { alignColumn(nested) }
      }
    }
    alignColumn(body)
    for item in [body, foot] { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    stack.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
      stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -8),
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
      details.topAnchor.constraint(greaterThanOrEqualTo: panel.topAnchor, constant: 20),
      details.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -20),
      panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 430),
    ])
    return panel
  }
  @objc func selectSettingsSection(_ sender: NSButton) {
    guard settingsPanels.indices.contains(sender.tag) else { return }
    leaveSettings(); settingsSection = sender.tag
    updateSettingsSection()
    window.makeFirstResponder(sender)
  }
  private func updateSettingsSection() {
    for (index, panel) in settingsPanels.enumerated() { panel.isHidden = index != settingsSection }
    for (index, item) in settingsButtons.enumerated() {
      item.primary = false
      item.state = index == settingsSection ? .on : .off
      item.setAccessibilityValue(index == settingsSection ? 1 : 0)
      item.needsDisplay = true
    }
    settingsView.revealSelectedSection()
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
    if pausedDemo { hearDemo() } else { startTake(advanceGuided: false) }
  }
  @objc func reviewPaused() {
    showPage(.review)
    setStatus("Review the hits so far. Restart a complete phrase when you are ready.")
  }
}
