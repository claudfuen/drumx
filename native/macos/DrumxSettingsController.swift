import AppKit

extension LabController {
  /// Settings owns its controls for the lifetime of the window. Changing sections
  /// never detaches a live MIDI control or changes a player's practice conditions.
  func buildSettings() {
    let title = label("Make it yours.", 42, weight: .bold, color: .labelColor)
    let subtitle = label("A comfortable kit. The sound you want. One less thing to think about.", 15)
    let sectionList = column([], spacing: 10)
    for (index, title) in ["01    Your kit", "02    Sound", "03    Playing", "04    Players & progress"].enumerated() {
      let item = button(title, #selector(selectSettingsSection(_:)))
      item.tag = index; item.quiet = true
      item.widthAnchor.constraint(equalToConstant: 200).isActive = true
      item.heightAnchor.constraint(equalToConstant: 50).isActive = true
      sectionList.addArrangedSubview(item); settingsButtons.append(item)
    }
    let detail = NSView()
    detail.widthAnchor.constraint(equalToConstant: 636).isActive = true
    detail.heightAnchor.constraint(equalToConstant: 430).isActive = true
    let kit = settingsColumn([
      label("Your kit", 27, weight: .semibold, color: .labelColor),
      settingCopy("Connect your module over USB, choose it here, then strike each pad to check the connection."),
      label("MIDI INPUT", 10, weight: .semibold), sourceMenu,
      label("PAD MAPPING", 10, weight: .semibold),
      settingCopy("Choose a pad below, then strike it once on your kit. The received MIDI note becomes its mapping."),
    ])
    sourceMenu.target = self; sourceMenu.action = #selector(sourceChanged)
    sourceMenu.widthAnchor.constraint(equalToConstant: 400).isActive = true
    sourceMenu.setAccessibilityLabel("MIDI input")
    for pad in 0..<3 {
      let item = button("", #selector(learnMapping(_:)))
      item.tag = pad; mappingButtons.append(item)
    }
    kit.addArrangedSubview(row(mappingButtons, spacing: 8))
    kitCheckStatus.font = .systemFont(ofSize: 12)
    kitCheckStatus.textColor = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
    kit.addArrangedSubview(kitCheckStatus)
    setupStatus.font = .systemFont(ofSize: 12); setupStatus.maximumNumberOfLines = 2
    setupStatus.lineBreakMode = .byWordWrapping
    kit.addArrangedSubview(setupStatus)
    kit.addArrangedSubview(settingCopy("No kit connected? A plays hi-hat, S plays snare, and Space plays kick. Hold Shift for a softer strike."))
    refreshMappingLabels(); refreshKitCheck()

    soundToggle.target = self; soundToggle.action = #selector(soundChanged)
    soundToggle.title = "Play Drumx sounds when I strike a pad"
    volumeSlider.target = self; volumeSlider.action = #selector(volumeChanged)
    volumeSlider.widthAnchor.constraint(equalToConstant: 260).isActive = true
    volumeSlider.setAccessibilityLabel("Drum and demonstration volume")
    soundStatus.font = .systemFont(ofSize: 12); soundStatus.maximumNumberOfLines = 2
    soundStatus.lineBreakMode = .byWordWrapping
    let sound = settingsColumn([
      label("Find your sound.", 27, weight: .semibold, color: .labelColor),
      settingCopy("Acoustic drum samples respond to your playing strength, with small variations between strikes."),
      soundToggle,
      settingCopy("Hearing your kit's own sounds? Turn this off to avoid hearing two drums at once. Lesson demonstrations stay audible."),
      row([label("Drums & demo", 13, weight: .medium), volumeSlider]),
      soundStatus,
      label("LISTENING SETUP", 10, weight: .semibold),
      settingCopy("Audio uses this Mac's selected output. If you use your module's sounds, combine its audio with the Drumx click. USB MIDI carries notes, not your module's audio."),
    ])

    handsToggle.target = self; handsToggle.action = #selector(handsChanged(_:))
    handsToggle.state = showHands ? .on : .off
    offsetField.widthAnchor.constraint(equalToConstant: 70).isActive = true
    offsetField.target = self; offsetField.action = #selector(offsetChanged)
    offsetField.setAccessibilityLabel("Input scoring offset in milliseconds")
    let playing = settingsColumn([
      label("Feel at home.", 27, weight: .semibold, color: .labelColor),
      handsToggle,
      settingCopy("Sticking letters suggest a hand. MIDI identifies the pad, so it cannot verify which hand you use."),
      label("TIMING ADJUSTMENT", 10, weight: .semibold),
      row([label("Input scoring offset", 13, weight: .medium), offsetField, label("ms", 13)]),
      settingCopy("Leave at 0 to start. A positive value moves scored strikes earlier; a negative value moves them later. Range: −200 to +200 ms. This adjusts scoring, not sound latency."),
      label("FOCUS & GUIDANCE", 10, weight: .semibold),
      settingCopy("Tempo, phrase length, and live timing are set inside each lesson and remembered for each player. Reduced motion follows your Mac's accessibility setting."),
    ])
    settingsPlayer.font = .systemFont(ofSize: 18, weight: .medium)
    let players = settingsColumn([
      label("Your own journey.", 27, weight: .semibold, color: .labelColor),
      settingsPlayer,
      settingCopy("Share the kit, keep your progress. Each player has their own lesson, practice settings, reading checks, and saved takes."),
      button("Manage players", #selector(showPlayers)),
      label("SAVED ON THIS MAC", 10, weight: .semibold),
      settingCopy("Completed takes save automatically. Stars compare matching practice conditions; lesson unlocks follow the foundation journey. Reading and recall remain separate achievements."),
      settingCopy("No account or cloud sync. Your practice stays in this app's local storage. Kit mappings, sound, and timing offset are shared by all players."),
    ])
    settingsPanels = [kit, sound, playing, players]
    for panel in settingsPanels {
      panel.translatesAutoresizingMaskIntoConstraints = false; detail.addSubview(panel)
      NSLayoutConstraint.activate([
        panel.topAnchor.constraint(equalTo: detail.topAnchor),
        panel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
        panel.widthAnchor.constraint(equalTo: detail.widthAnchor),
      ])
    }
    let body = row([sectionList, detail], spacing: 44)
    body.alignment = .top
    let stack = column([title, subtitle, body], spacing: 24)
    center(stack, in: settingsView)
    updateSettingsSection()
  }

  private func settingCopy(_ text: String) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: 14); field.textColor = .secondaryLabelColor
    field.preferredMaxLayoutWidth = 620
    return field
  }
  private func settingsColumn(_ views: [NSView]) -> NSStackView {
    let stack = column(views, spacing: 18)
    for field in views.compactMap({ $0 as? NSTextField }) {
      field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    return stack
  }
  @objc func selectSettingsSection(_ sender: NSButton) {
    // Commit a partially edited offset and stop MIDI learning when leaving its section.
    leaveSettings()
    settingsSection = sender.tag
    updateSettingsSection()
    focusStage()
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
    let stack = column([
      label("TAKE A BREATH", 11, weight: .semibold), pauseTitle, pauseDetail,
      row([button("Restart with count-in", #selector(restartPaused), primary: true),
        pauseReviewButton, button("Main menu", #selector(goMainMenu))]),
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
