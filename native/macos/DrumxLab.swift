import AppKit
import CoreMIDI
import Darwin

private let padNames = ["Hi-hat", "Snare", "Kick"]
private let ink = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
private let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
private let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)

final class LessonButton: NSButton {
  var primary = false
  var quiet = false
  var selectedByKit = false { didSet { needsDisplay = true } }
  private var hovered = false
  override var acceptsFirstResponder: Bool { isEnabled }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
  override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
  override var intrinsicContentSize: NSSize {
    NSSize(
      width: max(
        quiet ? 80 : 110,
        (title as NSString).size(withAttributes: [
          .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
        ]).width + 36), height: 43)
  }
  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    (primary
      ? lime.withAlphaComponent(isHighlighted ? 0.7 : 1)
      : NSColor.white.withAlphaComponent(isHighlighted ? 0.13 : hovered ? 0.09 : quiet ? 0 : 0.045)).setFill()
    path.fill()
    if !primary && !quiet {
      NSColor.white.withAlphaComponent(hovered ? 0.26 : 0.12).setStroke()
      path.stroke()
    }
    if window?.firstResponder === self || selectedByKit {
      lime.withAlphaComponent(0.9).setStroke(); path.lineWidth = 2; path.stroke()
    }
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
      .foregroundColor: (primary ? ink : paper).withAlphaComponent(isEnabled ? 1 : 0.35),
    ]
    let size = (title as NSString).size(withAttributes: attrs)
    (title as NSString).draw(
      at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
      withAttributes: attrs)
  }
}

final class LessonRootView: NSView {
  weak var controller: LabController?
  override var acceptsFirstResponder: Bool { true }
  override func cancelOperation(_ sender: Any?) { controller?.dismissOrStop() }
  override func keyDown(with event: NSEvent) {
    guard !event.isARepeat else { return }
    if event.keyCode == 53 {
      controller?.dismissOrStop()
      return
    }
    if event.keyCode == 36 {
      controller?.quickStart()
      return
    }
    if controller?.currentPage == .mainMenu, event.keyCode == 125 || event.keyCode == 126 {
      controller?.mainMenuView.moveSelection(event.keyCode == 125 ? 1 : -1)
      return
    }
    if let pad = ["a": 0, "s": 1, " ": 2][event.charactersIgnoringModifiers?.lowercased() ?? ""] {
      controller?.keyboardHit(
        pad: pad, velocity: event.modifierFlags.contains(.shift) ? 48 : 108,
        hostTime: event.timestamp)
    } else {
      super.keyDown(with: event)
    }
  }
}

final class LabController: NSObject, NSWindowDelegate {
  let io = DrumxIO()
  let core: OpaquePointer
  let scene = PracticeView()
  let root = LessonRootView()
  let prepareView = NSView(), reviewView = NSView()
  let welcomeView = NSView(), courseView = DrumxCourseMenuView()
  let mainMenuView = DrumxMainMenuView(), settingsView = DrumxSettingsPage(), pauseView = NSView()
  let pageTitle = NSTextField(labelWithString: "")
  let backButton = LessonButton(title: "← Back", target: nil, action: nil)
  let keyboardLegend = NSTextField(labelWithString: "")
  let kitSetup = DrumxKitSetup()
  let kitVisual = DrumxKitCheckView()
  var selectedKitPad = 1
  let mappingTitle = NSTextField(labelWithString: "Snare")
  let mappingNotes = NSTextField(labelWithString: "")
  let mappingHelp = NSTextField(wrappingLabelWithString: "")
  let mapNoteButton = LessonButton(title: "Add MIDI note", target: nil, action: nil)
  let cancelMapButton = LessonButton(title: "Cancel", target: nil, action: nil)
  let kitMenuToggle = DrumxToggle(checkboxWithTitle: "Navigate with my drums", target: nil, action: nil)
  let menuInput = DrumxMenuInput()
  var kitMenusEnabled = false
  var kitMenuIndex = 0
  weak var kitSelectedAction: LessonButton?
  var kitMenuActions: [LessonButton] = []
  let startButton = LessonButton(title: "Start playing", target: nil, action: nil)
  let hearButton = LessonButton(title: "Hear the pattern", target: nil, action: nil)
  let optionsButton = LessonButton(title: "Practice options", target: nil, action: nil)
  let pulseCheckpointButton = LessonButton(title: "Try 72 BPM", target: nil, action: nil)
  let repeatPulseButton = LessonButton(title: "Repeat this pace", target: nil, action: nil)
  let pulseCoachView = DrumxTempoView()
  let practiceRouteButton = LessonButton(title: "Free practice", target: nil, action: nil)
  let slowButton = LessonButton(title: "Slow it down", target: nil, action: nil)
  var pulsePractice = DrumxPulsePractice.initial(resume: PracticeResume(), existingPlayer: false)
  var practiceControls: NSStackView?
  let practiceSummary = NSTextField(labelWithString: "")
  let pauseRestart = LessonButton(title: "Restart with count-in", target: nil, action: nil)
  let pauseHome = LessonButton(title: "Main menu", target: nil, action: nil)
  var settingsOrigin: Page = .mainMenu
  var settingsSection = 0
  var settingsPanels: [NSView] = []
  var settingsButtons: [LessonButton] = []
  let handsToggle = DrumxToggle(checkboxWithTitle: "Show R / L sticking suggestions", target: nil, action: nil)
  let settingsPlayer = NSTextField(labelWithString: "")
  let nextLessonButton = LessonButton(title: "Next lesson", target: nil, action: nil)
  let unlockCaption = NSTextField(wrappingLabelWithString: "")
  let pauseTitle = NSTextField(labelWithString: "Practice paused")
  let pauseDetail = NSTextField(wrappingLabelWithString: "")
  let pauseReviewButton = LessonButton(title: "Review this take", target: nil, action: nil)
  var pausedDemo = false
  let progress = DrumxProgress()
  var lesson = DrumxCourse.lessons[0]
  var currentPage: Page = .welcome
  let playerButton = LessonButton(title: "Player 1", target: nil, action: nil)
  let courseButton = LessonButton(title: "Main menu", target: nil, action: nil)
  let welcomeName = NSTextField(string: "Player 1")
  let welcomeError = NSTextField(labelWithString: "")
  let lessonHeading = NSTextField(labelWithString: "")
  let lessonSubtitle = NSTextField(wrappingLabelWithString: "")
  let lessonExplanation = NSTextField(wrappingLabelWithString: "")
  let lessonPractice = NSTextField(labelWithString: "")
  let lessonEvidence = NSTextField(wrappingLabelWithString: "")
  let notation = DrumxNotationView()
  let lengthMenu = DrumxPopUpButton()
  let kitCheckStatus = NSTextField(labelWithString: "Play hi-hat, snare, and kick to check your input.")
  var checkedPads: Set<Int> = []
  var playerWindow: NSWindow?, checkWindow: NSWindow?
  let playerMenu = DrumxPopUpButton()
  let newPlayerName = NSTextField(string: "")
  let playerError = NSTextField(labelWithString: "")
  let checkFeedback = NSTextField(wrappingLabelWithString: "")
  let techniqueCheck = DrumxToggle(checkboxWithTitle: "I checked this myself", target: nil, action: nil)
  var snapshot = DXSnapshot()
  var running = false, completed = false, demonstrating = false
  var transportActive: Bool { running || demonstrating }
  var usedLiveFeedback = false
  var tempo = 96.0, mode = 0, showHands = true, showLive = true
  var lessonBars = 4
  var practiceStart = 0.0, clickStart = 0.0, calibrationMS = 0.0
  var hitFeedback = DrumxHitFeedback()
  var mappings = [[42, 44, 46], [38, 40], [35, 36]]
  var learning: Int?
  var drumSound = true
  let modeNames = ["Guided", "Hidden bars", "From memory"]
  var history: LessonHistory!
  private var takeID = UUID(), takeSettings: TakeSettings?, endedAt = Date()
  private var takeWindow: DrumxTakeWindow?
  var finishedNaturally = false
  private var timer: Timer?, lastStatusUpdate = 0.0
  private var nextHistoryRetry = 0.0
  private var pendingPracticeMarks: Set<UUID> = []
  private var allowsUnsavedExit = false
  private var closePromptActive = false
  private var showingReview = false
  private var demoEnd = 0.0
  private var lastDemoVisualTime = -Double.infinity
  let window: NSWindow
  let sourceMenu = DrumxPopUpButton(), modeMenu = DrumxPopUpButton()
  let tempoSlider = DrumxSlider(value: 96, minValue: 48, maxValue: 144, target: nil, action: nil)
  let tempoLabel = NSTextField(labelWithString: "96 BPM")
  let liveToggle = DrumxToggle(checkboxWithTitle: "Live timing", target: nil, action: nil)
  let offsetField = NSTextField(string: "0")
  let soundToggle = DrumxToggle(checkboxWithTitle: "Drum sound", target: nil, action: nil)
  let volumeSlider = DrumxSlider(value: 0.7, minValue: 0, maxValue: 1, target: nil, action: nil)
  let soundStatus = NSTextField(labelWithString: "Loading drum sounds…")
  let status = NSTextField(labelWithString: "Keyboard ready. Connect a MIDI kit in Settings.")
  let setupStatus = NSTextField(
    labelWithString: "Choose your MIDI input, then play each pad to check its sound.")
  let results = NSTextField(labelWithString: "LISTEN   /   PLAY   /   REMEMBER")
  private let runScoreHUD = RunScoreHUD()
  private let runScoreReview = RunScoreReviewView()
  private var previousBestPoints: Int?
  let play = LessonButton(title: "Stop take", target: nil, action: nil)
  let kitButton = LessonButton(title: "Settings", target: nil, action: nil)
  let reviewTitle = NSTextField(labelWithString: "Take complete")
  let reviewDetail = NSTextField(wrappingLabelWithString: "")
  let reviewConditions = NSTextField(labelWithString: "")
  let personalBest = NSTextField(labelWithString: "")
  let scoreCaption = NSTextField(labelWithString: "")
  let retryButton = LessonButton(title: "Play again", target: nil, action: nil)
  let challengeButton = LessonButton(title: "Hide a phrase", target: nil, action: nil)
  let loopButton = LessonButton(title: "Work on one bar", target: nil, action: nil)
  private var metricValues: [NSTextField] = []
  var mappingButtons: [NSButton] = []

  override init() {
    guard let core = dx_core_create() else { fatalError("Could not create scoring core") }
    self.core = core
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1140, height: 830),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init()
    window.delegate = self
    history = makePlayerHistory()
    restorePlayer()
    window.title = "Drumx · Foundations"
    window.minSize = NSSize(width: 1020, height: 780)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = ink
    window.titlebarAppearsTransparent = true
    if let saved = UserDefaults.standard.array(forKey: "drumx.lab.mapping") as? [[Int]],
      saved.count == 3
    {
      mappings = saved.map { $0.filter { (0...127).contains($0) } }
    }
    _ = kitSetup.replaceMappings(mappings)
    mappings = kitSetup.mappings
    kitMenusEnabled = UserDefaults.standard.bool(forKey: "drumx.kitMenuControls")
    kitMenuToggle.state = kitMenusEnabled ? .on : .off
    let savedOffset = UserDefaults.standard.double(forKey: "drumx.lab.inputOffsetMS")
    calibrationMS = savedOffset.isFinite ? min(200, max(-200, savedOffset)) : 0
    offsetField.stringValue = String(format: "%.0f", calibrationMS)
    showHands = (UserDefaults.standard.object(forKey: "drumx.lab.handHints") as? Bool) ?? true
    if let volume = UserDefaults.standard.object(forKey: "drumx.lab.volume") as? Double, volume.isFinite {
      volumeSlider.doubleValue = min(1, max(0, volume))
    }
    buildUI()
    scene.controller = self
    root.controller = self
    scene.setAccessibilityElement(true)
    scene.setAccessibilityRole(.image)
    drumSound = (UserDefaults.standard.object(forKey: "drumx.lab.drumSound") as? Bool) ?? true
    soundToggle.state = drumSound ? .on : .off
    io.onSamplerStatusChanged = { [weak self] message in self?.soundStatus.stringValue = message }
    io.setMIDIMapping(mappings)
    do {
      guard let resources = Bundle.main.resourceURL else {
        throw NSError(
          domain: "Drumx", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Sample resources missing"])
      }
      try io.loadSampler(manifestURL: resources.appendingPathComponent("BigRusty/manifest.json"))
      io.setMonitorVolume(Float(volumeSlider.doubleValue))
      io.setMonitoring(enabled: drumSound)
    } catch {
      drumSound = false
      soundToggle.state = .off
      soundToggle.isEnabled = false
      soundStatus.stringValue = "Drum sounds unavailable: \(error.localizedDescription)"
    }
    io.onMIDI = { [weak self] note, velocity, time in
      self?.midi(note: note, velocity: velocity, time: time)
    }
    io.onConnectionChanged = { [weak self] in
      guard let self else { return }
      self.stopTake()
      self.kitSetup.selectSource(self.io.selectedSourceID)
      self.kitSetup.invalidateInput()
      self.learning = nil; self.io.setMIDILearnActive(false)
      self.menuInput.reset(at: DrumxIO.hostNowSeconds())
      self.updateSources(self.io.sources)
    }
    io.onSourcesChanged = { [weak self] sources in self?.updateSources(sources) }
    io.onStatusChanged = { [weak self] message in self?.setStatus(message) }
    io.onAudioInterrupted = { [weak self] message in
      self?.stopTake()
      self?.setStatus(message)
    }
    updateSources(io.sources)
    if let savedSource = UserDefaults.standard.object(forKey: "drumx.lab.lastSourceID") as? NSNumber,
       io.sources.contains(where: { $0.id == savedSource.int32Value }) {
      io.connect(sourceID: savedSource.int32Value)
      updateSources(io.sources)
    }
    resetCore()
    showPage(progress.selectedProfile.hasCompletedWelcome ? .mainMenu : .welcome)
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
      self?.tick()
    }
    window.center()
    window.makeKeyAndOrderFront(nil)
    focusStage()
  }

  deinit {
    timer?.invalidate()
    io.stopClick()
    io.stopDemo()
    dx_core_destroy(core)
  }

  func label(
    _ text: String, _ size: CGFloat = 13, weight: NSFont.Weight = .regular,
    color: NSColor = .secondaryLabelColor
  ) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    return l
  }
  func row(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let r = NSStackView(views: views)
    r.orientation = .horizontal
    r.spacing = spacing
    r.alignment = .centerY
    return r
  }
  func column(_ views: [NSView], spacing: CGFloat = 16) -> NSStackView {
    let c = NSStackView(views: views)
    c.orientation = .vertical
    c.alignment = .leading
    c.spacing = spacing
    return c
  }
  func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return v
  }
  func button(_ title: String, _ action: Selector, primary: Bool = false) -> LessonButton {
    let b = LessonButton(title: title, target: self, action: action)
    b.primary = primary
    b.isBordered = false
    return b
  }
  private func anchor(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
      child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
    ])
  }
  func center(_ child: NSView, in parent: NSView, width: CGFloat = 880) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
      child.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
      child.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
      child.widthAnchor.constraint(equalToConstant: width),
    ])
  }
  private func buildUI() {
    window.contentView = root
    root.wantsLayer = true
    root.layer?.backgroundColor = ink.cgColor
    let logo = label("drumx", 28, weight: .bold, color: paper)
    let header = row(
      [logo, pageTitle, spacer(), results, runScoreHUD, backButton, courseButton, kitButton, playerButton],
      spacing: 14)
    pageTitle.font = .systemFont(ofSize: 10, weight: .semibold)
    pageTitle.textColor = .secondaryLabelColor
    runScoreHUD.widthAnchor.constraint(equalToConstant: 420).isActive = true
    runScoreHUD.heightAnchor.constraint(equalToConstant: 44).isActive = true
    results.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
    results.textColor = .secondaryLabelColor
    kitButton.target = self
    kitButton.action = #selector(showSetup)
    kitButton.isBordered = false
    playerButton.target = self; playerButton.action = #selector(showPlayers); playerButton.isBordered = false
    courseButton.target = self; courseButton.action = #selector(goMainMenu); courseButton.isBordered = false
    backButton.target = self; backButton.action = #selector(goBack); backButton.isBordered = false
    [courseButton, backButton, kitButton, playerButton].forEach { $0.quiet = true }
    play.target = self
    play.action = #selector(stopAction)
    play.isBordered = false
    status.font = .systemFont(ofSize: 11)
    status.lineBreakMode = .byTruncatingMiddle
    status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    keyboardLegend.font = .systemFont(ofSize: 11); keyboardLegend.textColor = .secondaryLabelColor
    let bottom = row(
      [status, spacer(), keyboardLegend, play],
      spacing: 18)
    let main = NSView()
    for view in [header, main, bottom] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
      bottom.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      bottom.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
      main.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
      main.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -18),
      main.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      main.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
    ])
    for page in [welcomeView, mainMenuView, courseView, prepareView, scene, reviewView, settingsView, pauseView] { anchor(page, in: main) }
    buildWelcome()
    mainMenuView.onContinue = { [weak self] in self?.openCurrentLesson() }
    mainMenuView.onExplore = { [weak self] in self?.backToCourse() }
    mainMenuView.onSettings = { [weak self] in self?.showSetup() }
    courseView.onSelect = { [weak self] id in self?.selectLesson(id) }
    courseView.onContinue = { [weak self] in self?.openCurrentLesson() }
    buildPreparation()
    buildReview()
    buildSettings()
    buildPauseMenu()
  }

  private func buildPreparation() {
    lessonHeading.font = .systemFont(ofSize: 42, weight: .bold)
    lessonHeading.textColor = paper
    lessonSubtitle.font = .systemFont(ofSize: 18)
    lessonSubtitle.textColor = paper.withAlphaComponent(0.8)
    lessonSubtitle.maximumNumberOfLines = 2
    lessonExplanation.font = .systemFont(ofSize: 14)
    lessonExplanation.textColor = .secondaryLabelColor
    lessonExplanation.maximumNumberOfLines = 3
    notation.heightAnchor.constraint(equalToConstant: 172).isActive = true
    notation.wantsLayer = true; notation.layer?.cornerRadius = 14
    lessonPractice.font = .systemFont(ofSize: 12)
    lessonEvidence.font = .systemFont(ofSize: 12)
    lessonEvidence.textColor = lime
    lessonEvidence.maximumNumberOfLines = 2
    tempoSlider.target = self; tempoSlider.action = #selector(settingsChanged)
    tempoSlider.widthAnchor.constraint(equalToConstant: 115).isActive = true
    tempoSlider.setAccessibilityLabel("Practice tempo")
    tempoLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    tempoLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true
    modeMenu.addItems(withTitles: modeNames)
    modeMenu.target = self; modeMenu.action = #selector(settingsChanged)
    modeMenu.setAccessibilityLabel("Visual guidance")
    lengthMenu.addItems(withTitles: ["1 bar · repair", "4 bars · short", "8 bars", "16 bars · practice"])
    lengthMenu.selectItem(at: 3); lengthMenu.target = self; lengthMenu.action = #selector(lengthChanged)
    lengthMenu.setAccessibilityLabel("Practice phrase length")
    liveToggle.target = self; liveToggle.action = #selector(liveChanged(_:))
    liveToggle.state = showLive ? .on : .off
    liveToggle.toolTip = "Shows early/late and score feedback. Turn off for a click-only memory check."
    let controls = row([label("TEMPO", 10, weight: .semibold), tempoSlider, tempoLabel,
                        spacer(), lengthMenu, modeMenu, liveToggle], spacing: 14)
    startButton.target = self; startButton.action = #selector(beginLesson); startButton.primary = true; startButton.isBordered = false
    hearButton.target = self; hearButton.action = #selector(hearDemo); hearButton.isBordered = false
    optionsButton.target = self; optionsButton.action = #selector(togglePracticeOptions); optionsButton.isBordered = false; optionsButton.quiet = true
    practiceRouteButton.target = self; practiceRouteButton.action = #selector(togglePulseRoute)
    practiceRouteButton.isBordered = false; practiceRouteButton.quiet = true
    pulseCheckpointButton.target = self; pulseCheckpointButton.action = #selector(startPulseCheckpoint)
    pulseCheckpointButton.isBordered = false; pulseCheckpointButton.quiet = true
    pulseCheckpointButton.setAccessibilityLabel("Try the guided 72 BPM checkpoint directly")
    practiceSummary.font = .systemFont(ofSize: 13); practiceSummary.textColor = .secondaryLabelColor
    practiceControls = controls; controls.isHidden = true
    let actions = row([startButton, hearButton, button("Lesson check", #selector(showLearningCheck)), optionsButton, pulseCheckpointButton, practiceRouteButton], spacing: 10)
    let stack = column([label("HEAR IT. COUNT IT. MAKE IT YOURS.", 11, weight: .semibold, color: lime),
      lessonHeading, lessonSubtitle, lessonExplanation, notation, lessonPractice, practiceSummary, pulseCoachView, controls, actions, lessonEvidence], spacing: 12)
    [lessonSubtitle, lessonExplanation, notation, controls, lessonEvidence, pulseCoachView].forEach {
      $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    center(stack, in: prepareView)
    refreshLesson()
  }

  private func buildReview() {
    reviewTitle.font = .systemFont(ofSize: 36, weight: .bold)
    reviewTitle.textColor = paper
    reviewDetail.font = .systemFont(ofSize: 17)
    reviewDetail.textColor = paper.withAlphaComponent(0.75)
    reviewDetail.maximumNumberOfLines = 3
    reviewConditions.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    scoreCaption.font = .systemFont(ofSize: 12)
    scoreCaption.textColor = .secondaryLabelColor
    let stats = row([], spacing: 38)
    for title in ["HITS", "MISSES", "EXTRAS", "BEST COMBO"] {
      let value = label("0", 26, weight: .medium, color: paper)
      metricValues.append(value)
      stats.addArrangedSubview(column([value, label(title, 11, weight: .semibold)], spacing: 4))
    }
    stats.addArrangedSubview(spacer())
    runScoreReview.heightAnchor.constraint(equalToConstant: 130).isActive = true
    personalBest.font = .systemFont(ofSize: 13)
    personalBest.textColor = lime
    retryButton.primary = true
    retryButton.isBordered = false
    retryButton.target = self
    retryButton.action = #selector(retryTake)
    challengeButton.isBordered = false
    challengeButton.target = self
    challengeButton.action = #selector(nextChallenge)
    loopButton.isBordered = false
    loopButton.target = self
    loopButton.action = #selector(repairBar)
    slowButton.target = self; slowButton.action = #selector(slowerTake); slowButton.isBordered = false
    repeatPulseButton.target = self; repeatPulseButton.action = #selector(repeatPulse)
    repeatPulseButton.isBordered = false; repeatPulseButton.quiet = true
    let actions = row([
      retryButton, repeatPulseButton, slowButton, loopButton, challengeButton,
    ])
    nextLessonButton.isBordered = false; nextLessonButton.target = self; nextLessonButton.action = #selector(nextLesson)
    unlockCaption.font = .systemFont(ofSize: 12); unlockCaption.textColor = lime
    unlockCaption.maximumNumberOfLines = 2
    let stack = column(
      [
        label("LISTEN. ADJUST. GO AGAIN.", 11, weight: .semibold, color: lime), reviewConditions,
        reviewTitle, reviewDetail, runScoreReview, stats, scoreCaption, personalBest,
        actions, row([button("Lesson check", #selector(showLearningCheck)), nextLessonButton, unlockCaption]),
      ], spacing: 12)
    [reviewDetail, runScoreReview, stats].forEach {
      $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    center(stack, in: reviewView)
  }

  enum Page { case welcome, mainMenu, course, prepare, stage, review, settings, pause }
  func showPage(_ page: Page) {
    let previousPage = currentPage
    currentPage = page
    showingReview = page == .review
    for (view, destination) in [(welcomeView, Page.welcome), (mainMenuView, .mainMenu),
      (courseView, .course), (prepareView, .prepare), (scene, .stage), (reviewView, .review),
      (settingsView, .settings), (pauseView, .pause)] { view.isHidden = destination != page }
    playerButton.isHidden = page != .mainMenu
    backButton.isHidden = ![Page.course, .prepare, .review, .settings].contains(page)
    courseButton.isHidden = [.welcome, .mainMenu, .stage, .pause].contains(page)
    kitButton.isHidden = ![Page.course, .prepare, .review].contains(page)
    play.isHidden = page != .stage
    runScoreHUD.isHidden = page != .stage
    results.isHidden = true
    keyboardLegend.stringValue = page == .stage ? "A  hi-hat    S  snare    SPACE  kick    ESC  pause"
      : page == .mainMenu ? "↑ ↓  choose    RETURN  select"
      : page == .welcome ? "A / S / SPACE  try the drums"
      : "ESC  main menu"
    switch page {
    case .mainMenu:
      let state = unlockState
      mainMenuView.update(lesson: lesson, player: progress.selectedProfile.name,
        unlocked: state.availableIDs.count, cleared: state.clearedIDs.count)
      pageTitle.stringValue = "MAIN MENU"; window.title = "Drumx · Main menu"
      setStatus("Your rhythm. Your pace. Progress saved on this Mac.")
    case .course:
      refreshCourse(); pageTitle.stringValue = "FOUNDATIONS"; window.title = "Drumx · Foundations"
      setStatus("Explore each chapter. Open lessons stay yours to revisit.")
    case .prepare:
      refreshLesson(); pageTitle.stringValue = "FOUNDATIONS / LESSON"
    case .review:
      refreshPulseReview(stopped: finishedNaturally ? nil : snapshot, takeID: takeID)
      refreshUnlockReview(); pageTitle.stringValue = "TAKE REVIEW"
    case .welcome:
      if previousPage != .settings { welcomeName.stringValue = progress.selectedProfile.name }
      pageTitle.stringValue = "WELCOME"; window.title = "Drumx · Welcome"
      setStatus("Choose your player name. Connect a kit, or try the keyboard.")
    case .settings:
      pageTitle.stringValue = "SETTINGS"; window.title = "Drumx · Settings"
      settingsPlayer.stringValue = "Playing as \(progress.selectedProfile.name)"
      setStatus("Preferences save automatically. Your kit settings are shared by players on this Mac.")
    case .pause:
      pageTitle.stringValue = "PAUSED"
      setStatus("Take a breath. Restart with a fresh count-in when you're ready.")
    case .stage: pageTitle.stringValue = ""
    }
    if let error = history.lastError ?? progress.lastError { setStatus(error) }
    resetKitMenuFocus()
    focusStage()
  }
  func focusStage() {
    if playerWindow == nil && checkWindow == nil { window.makeFirstResponder(transportActive ? scene : root) }
  }
  func setStatus(_ text: String) {
    status.stringValue = text
    if currentPage != .settings { return }
    setupStatus.stringValue = text
  }
  func resetCore() {
    completed = false
    finishedNaturally = false
    takeWindow = nil
    hitFeedback.reset()
    runScoreHUD.update(score: nil, bestPoints: nil, state: "COUNT-IN")
    lastDemoVisualTime = -Double.infinity
    var chart = repeatedNotes.map { DXChartEvent(pad: Int32($0.pad), beat: $0.beat) }
    let loaded = chart.withUnsafeMutableBufferPointer {
      dx_core_load_chart(core, tempo, Double(lessonBars * 4), $0.baseAddress, Int32($0.count))
    }
    precondition(loaded == 1, "Built-in lesson chart must be valid")
    dx_core_set_guidance(core, Int32(mode))
    dx_core_snapshot(core, &snapshot)
    scene.needsDisplay = true
  }
  func refreshMappingLabels() {
    refreshKitInspector()
    for pad in 0..<mappingButtons.count {
      mappingButtons[pad].title =
        "\(padNames[pad]): \(mappings[pad].map(String.init).joined(separator: "/"))"
    }
  }
  private func updateSources(_ sources: [MIDISourceInfo]) {
    let previous = (sourceMenu.selectedItem?.representedObject as? NSNumber)?.int32Value
    if let previous, !sources.contains(where: { $0.id == previous }) {
      stopTake()
      checkedPads.removeAll(); refreshKitCheck()
      setStatus("MIDI disconnected. Reconnect or choose an input in Settings.")
    }
    let selected = io.selectedSourceID
    sourceMenu.removeAllItems()
    sourceMenu.addItem(withTitle: "Keyboard / no MIDI input")
    for source in sources {
      sourceMenu.addItem(withTitle: source.name)
      sourceMenu.lastItem?.representedObject = NSNumber(value: source.id)
    }
    if let id = selected,
      let item = sourceMenu.itemArray.first(where: {
        ($0.representedObject as? NSNumber)?.int32Value == id
      })
    {
      sourceMenu.select(item)
    } else if selected != nil {
      stopTake()
      io.connect(sourceID: nil)
    }
    if kitSetup.selectedSourceID != io.selectedSourceID {
      kitSetup.selectSource(io.selectedSourceID)
      learning = nil; io.setMIDILearnActive(false)
      menuInput.reset(at: DrumxIO.hostNowSeconds())
    }
    refreshKitCheck(); refreshKitInspector()
  }

  @objc func showSetup() {
    guard !transportActive, playerWindow == nil, checkWindow == nil else { return }
    if currentPage != .settings { settingsOrigin = currentPage }
    refreshMappingLabels(); refreshKitCheck()
    handsToggle.state = showHands ? .on : .off
    showPage(.settings)
    refreshKitInspector()
  }
  @objc func closeSetup() {
    leaveSettings()
    showPage(settingsOrigin)
  }
  func leaveSettings() {
    offsetChanged()
    kitSetup.cancelLearning()
    learning = nil
    io.setMIDILearnActive(false)
    io.stopDemo()
    refreshKitInspector()
  }
  @objc func sourceChanged() {
    stopTake(); completed = false
    kitSetup.invalidateInput(); learning = nil; io.setMIDILearnActive(false)
    let source = (sourceMenu.selectedItem?.representedObject as? NSNumber)?.int32Value
    io.connect(sourceID: source)
    kitSetup.selectSource(io.selectedSourceID)
    UserDefaults.standard.set(io.selectedSourceID.map { Int($0) }, forKey: "drumx.lab.lastSourceID")
    menuInput.reset(at: DrumxIO.hostNowSeconds())
    refreshKitCheck(); refreshKitInspector()
  }
  @objc func learnMapping(_ sender: NSButton) {
    guard !transportActive, currentPage == .settings else { return }
    selectedKitPad = sender.tag
    guard kitSetup.beginLearning(pad: selectedKitPad, at: DrumxIO.hostNowSeconds()) else {
      mappingHelp.stringValue = kitSetup.lastError ?? "Choose your MIDI module above first."; return
    }
    completed = false; learning = kitSetup.pendingPad
    io.setMIDILearnActive(true); refreshKitInspector()
  }
  @objc func settingsChanged() {
    guard !transportActive else { return }
    tempo = tempoSlider.doubleValue.rounded()
    tempoLabel.stringValue = "\(Int(tempo)) BPM"
    mode = modeMenu.indexOfSelectedItem
    if mode == 1 && lessonBars == 1 {
      lessonBars = 4; lengthMenu.selectItem(at: 1)
    }
    saveResume()
    refreshPracticeSummary()
    resetCore()
    focusStage()
  }
  @objc func handsChanged(_ sender: NSButton) {
    showHands = sender.state == .on
    UserDefaults.standard.set(showHands, forKey: "drumx.lab.handHints")
    scene.needsDisplay = true
  }
  @objc func liveChanged(_ sender: NSButton) {
    showLive = sender.state == .on
    saveResume()
    scene.needsDisplay = true
    focusStage()
  }
  @objc func offsetChanged() {
    guard !transportActive else { return }
    let proposed = Double(offsetField.stringValue) ?? 0
    calibrationMS = proposed.isFinite ? min(200, max(-200, proposed)) : 0
    offsetField.stringValue = String(format: "%.0f", calibrationMS)
    UserDefaults.standard.set(calibrationMS, forKey: "drumx.lab.inputOffsetMS")
  }
  @objc func soundChanged() {
    drumSound = soundToggle.state == .on
    io.setMonitoring(enabled: drumSound)
    UserDefaults.standard.set(drumSound, forKey: "drumx.lab.drumSound")
  }
  @objc func volumeChanged() {
    io.setMonitorVolume(Float(volumeSlider.doubleValue))
    UserDefaults.standard.set(volumeSlider.doubleValue, forKey: "drumx.lab.volume")
  }
  func dismissOrStop() {
    if checkWindow != nil { closeLearningCheck() }
    else if playerWindow != nil { closePlayers() }
    else if transportActive { pausePractice() }
    else if currentPage != .welcome && currentPage != .mainMenu { goMainMenu() }
  }
  func quickStart() {
    if playerWindow != nil || checkWindow != nil { return }
    guard !transportActive else { return }
    switch currentPage {
    case .welcome: finishWelcome()
    case .mainMenu: mainMenuView.activateSelection()
    case .prepare: startButton.performClick(nil)
    case .review: retryButton.performClick(nil)
    case .pause: restartPaused()
    default: break
    }
  }
  @objc func beginLesson() { startTake() }
  @objc func retryTake() { startTake() }
  @objc func stopAction() { stopTake() }
  @objc func slowerTake() {
    if isGuidedPulse { openFreePractice(); return }
    tempo = max(48, tempo - 8)
    tempoSlider.doubleValue = tempo
    tempoLabel.stringValue = "\(Int(tempo)) BPM"
    startTake()
  }
  @objc func repairBar() {
    if isGuidedPulse { openFreePractice(); return }
    // Each foundation exercise is one authored bar. Isolate it without changing its notes.
    lessonBars = lessonBars == 1 ? 4 : 1
    mode = 0
    modeMenu.selectItem(at: mode)
    startTake()
  }
  @objc func nextChallenge() {
    if isGuidedPulse { startTake(); return }
    if mode == 0 {
      mode = 1
      if lessonBars == 1 { lessonBars = 4 }
    } else {
      mode = 2
      showLive = false
      liveToggle.state = .off
    }
    modeMenu.selectItem(at: mode)
    startTake()
  }
  @objc func backToLesson() {
    stopTake()
    completed = false
    saveResume()
    resetCore()
    showPage(.prepare)
    setStatus(
      "\(io.selectedSourceID == nil ? "Keyboard" : "MIDI kit") ready. Find a comfortable tempo.")
  }
  @objc func hearDemo() {
    guard !transportActive else { return }
    saveResume()
    resetCore()
    learning = nil
    io.setMIDILearnActive(false)
    clickStart = DrumxIO.hostNowSeconds() + 0.75
    practiceStart = clickStart + 240 / tempo
    let demoHits = repeatedNotes.map { DrumxDemoHit(pad: $0.pad, beat: $0.beat, velocity: $0.velocity) }
    guard io.startDemo(bpm: tempo, firstBeatHostTime: practiceStart,
                       durationBeats: Double(lessonBars * 4), hits: demoHits) else {
      setStatus("Couldn't start the drum demo. Check Settings.")
      return
    }
    guard io.startClick(bpm: tempo, firstBeatHostTime: clickStart, beats: 4 + lessonBars * 4) else {
      io.stopDemo()
      setStatus(io.statusDescription)
      return
    }
    demoEnd = practiceStart + max(dx_core_duration(core), io.demoDurationSeconds)
    demonstrating = true
    runScoreHUD.update(score: nil, bestPoints: nil, state: "LISTEN  /  COUNT OUT LOUD")
    play.title = "Stop listening"
    showPage(.stage)
    results.stringValue = "LISTEN  /  COUNT OUT LOUD"
    setStatus("Listen, then count aloud: \(lesson.counts).")
  }
  func startTake(advanceGuided: Bool = true) {
    guard !transportActive else { return }
    if progress.selectedProfile.legacyAccessThrough == nil {
      guard history.lastError == nil,
        DrumxUnlocks.migrateLegacyAccess(course: DrumxCourse.lessons,
                                        history: history.attempts, progress: progress) else {
        setStatus(history.lastError ?? progress.lastError ?? "Progress could not be prepared. Your existing access has been preserved.")
        return
      }
    }
    offsetChanged()
    if isGuidedPulse, currentPage == .review, let captured = takeSettings,
      !DrumxTempoCoach.sameInputConditions(captured, pulseTakeSettings()) {
      completed = false; resetCore(); showPage(.prepare)
      setStatus("Your input conditions changed. Review the current coaching before starting.")
      return
    }
    if advanceGuided && !(currentPage == .review && !finishedNaturally) { applyNextGuidedCondition() }
    learning = nil
    io.setMIDILearnActive(false)
    io.stopDemo()
    saveResume()
    resetCore()
    usedLiveFeedback = showLive
    takeID = UUID()
    takeSettings = pulseTakeSettings()
    previousBestPoints = takeSettings.flatMap { history.best(matching: $0) }
      .map { DrumxRunScore(attempt: $0).points }
    clickStart = DrumxIO.hostNowSeconds() + 0.75
    practiceStart = clickStart + 240 / tempo
    takeWindow = DrumxTakeWindow(
      practiceStart: practiceStart, calibrationMS: calibrationMS,
      inputIdentity: io.selectedSourceID.map { "midi:\($0)" } ?? "keyboard")
    guard io.startClick(bpm: tempo, firstBeatHostTime: clickStart, beats: 4 + lessonBars * 4) else {
      setStatus(io.statusDescription)
      return
    }
    running = true
    play.title = "Stop take"
    showPage(.stage)
    setStatus(
      mode == 2 && !showLive
        ? "Click-only check. Your results appear after the phrase."
        : "\(lessonBars) \(lessonBars == 1 ? "bar" : "bars") · \(modeNames[mode]) · Esc to pause"
    )
  }
  func stopTake() {
    if demonstrating {
      demonstrating = false
      io.stopDemo()
      io.stopClick()
      showPage(.prepare)
      setStatus("Ready when you are. Try the groove yourself.")
      return
    }
    guard running else { return }
    let stopHostTime = DrumxIO.hostNowSeconds()
    let complete =
      takeWindow?.phraseHasEnded(atHostTime: stopHostTime, duration: dx_core_duration(core))
      ?? false
    dx_core_finish(core, stopHostTime - practiceStart)
    finishTake(naturally: complete, atHostTime: stopHostTime)
  }
  private func finishTake(naturally: Bool, atHostTime: Double) {
    takeWindow?.stop(atHostTime: atHostTime)
    running = false
    completed = true
    finishedNaturally = naturally
    endedAt = Date()
    io.stopClick()
    dx_core_snapshot(core, &snapshot)
    updateReview()
    showPage(.review)
    setStatus(
      naturally
        ? "Take complete. Choose what to work on next."
        : "Take stopped. Partial takes don't set personal bests.")
  }
  private func midi(note: Int, velocity: Int, time: Double) {
    guard let source = io.selectedSourceID else { return }
    guard let receipt = kitSetup.receiveMIDI(note: note, velocity: velocity, sourceID: source, at: time) else { return }
    learning = kitSetup.pendingPad
    io.setMIDILearnActive(learning != nil)
    if let change = receipt.mappingChange {
      mappings = change.mappings
      io.setMIDIMapping(mappings)
      UserDefaults.standard.set(mappings, forKey: "drumx.lab.mapping")
      refreshMappingLabels()
      let moved = change.removedFromPads.map { padNames[$0] }.joined(separator: ", ")
      mappingHelp.stringValue = change.wasAlreadyMapped ? "Note \(note) is already mapped here."
        : moved.isEmpty ? "Added note \(note). Existing articulations are kept."
        : "Moved note \(note) from \(moved). Check both pads again."
    }
    let hit = receipt.hit
    let description = "MIDI \(note) · velocity \(velocity) · \(hit.pad.map { padNames[$0] } ?? "unmapped")"
    kitVisual.showHit(pad: hit.pad, velocity: velocity, description: description)
    refreshKitCheck()
    if receipt.mappingChange != nil { return }
    guard let pad = hit.pad else {
      if currentPage == .settings { mappingHelp.stringValue = "Receiving note \(note), but it has no sound assigned. Select a pad, choose Add MIDI note, then strike again." }
      return
    }
    // Late captured strikes still correct the closed take before menu input is considered.
    receive(pad: pad, velocity: Double(velocity) / 127, hostTime: time, inputIdentity: "midi:\(source)")
    _ = routeKitMenu(pad: pad, velocity: velocity, at: time)
  }
  func keyboardHit(pad: Int, velocity: Int, hostTime: Double) {
    guard [.welcome, .settings, .prepare, .stage].contains(currentPage) else { return }
    // Capture time stays in the native host clock domain even if UI delivery is late.
    io.playPad(pad: pad, velocity: velocity)
    _ = kitSetup.receiveKeyboard(pad: pad, velocity: velocity, at: DrumxIO.hostNowSeconds())
    if currentPage == .settings {
      kitVisual.showHit(pad: pad, velocity: velocity, description: "Keyboard preview · \(padNames[pad]) · velocity \(velocity)")
      refreshKitCheck()
    }
    receive(
      pad: pad, velocity: Double(velocity) / 127, hostTime: hostTime, inputIdentity: "keyboard")
  }
  private func receive(pad: Int, velocity: Double, hostTime: Double, inputIdentity: String) {
    let now = DrumxIO.hostNowSeconds()
    var result: DXHitResult?
    if !demonstrating, running || completed,
      let songTime = takeWindow?.songTime(capturedAt: hostTime, inputIdentity: inputIdentity),
      songTime >= -0.125,
      songTime <= dx_core_duration(core) + 0.125
    {
      result = dx_core_input(core, Int32(pad), songTime, velocity)
      dx_core_snapshot(core, &snapshot)
      if completed { updateReview() }
    }
    // Every strike gets acknowledgment. Only the actual returned judgment may
    // trigger a capture/extra effect; the global last-hit snapshot loses chords.
    hitFeedback.record(
      pad: pad, judgment: result.map { Int($0.judgment) }, velocity: velocity,
      offsetMS: result?.offset_ms ?? 0, at: now,
      revealJudgment: running && showLive && !demonstrating)
    scene.needsDisplay = true
  }
  private func updateReview(saveResult: Bool = true) {
    let review = LessonReview(snapshot: snapshot, completedNaturally: finishedNaturally)
    reviewTitle.stringValue = review.headline
    reviewDetail.stringValue = review.detail
    reviewConditions.stringValue =
      "\(Int(tempo)) BPM  ·  \(modeNames[mode])  ·  \(lessonBars) \(lessonBars == 1 ? "bar" : "bars")  ·  \(usedLiveFeedback ? "live timing" : "feedback after phrase")"
    let s = snapshot.total
    let score = DrumxRunScore(snapshot: snapshot, completedNaturally: finishedNaturally)
    for (field, value) in zip(metricValues, [s.matched, s.missed, s.extra, s.best_streak]) {
      field.stringValue = String(value)
    }
    scoreCaption.stringValue =
      "Five stars: every target within 50 ms, no misses or extras, across the complete phrase."
    personalBest.stringValue =
      "Partial take · not saved. Complete the phrase to set a personal best."
    var recent: [LessonAttempt] = []
    var bestPoints: Int?
    var savedID: UUID?
    if let settings = takeSettings {
      let attempt: LessonAttempt?
      if saveResult {
        attempt = history.record(
          id: takeID, settings: settings, snapshot: snapshot, completedNaturally: finishedNaturally,
          endedAt: endedAt)
        if attempt != nil || history.hasPendingSave(id: takeID) { pendingPracticeMarks.insert(takeID) }
        nextHistoryRetry = DrumxIO.hostNowSeconds() + 1
        if attempt != nil { registerCommittedPractice() }
      } else {
        attempt = history.hasPendingSave(id: takeID) ? nil : history.attempts.first { $0.id == takeID }
      }
      bestPoints = history.best(matching: settings, excluding: takeID)
        .map { DrumxRunScore(attempt: $0).points }
      recent = history.recent(matching: settings)
      if let attempt {
        savedID = attempt.id
        personalBest.stringValue =
          "Saved on this Mac · comparisons use the same lesson, tempo, input, and aids."
      }
      if let error = history.lastError {
        personalBest.stringValue = "Couldn't save this take: \(error)"
      }
    }
    runScoreReview.update(score: score, recent: recent, currentID: savedID, bestPoints: bestPoints)
    loopButton.title = lessonBars == 1 ? "Back to four bars" : "Work on one bar"
    challengeButton.title =
      mode == 0 ? "Hide a phrase" : mode == 1 || showLive ? "Try click-only" : "Repeat click-only"
    refreshPulseReview(stopped: finishedNaturally ? nil : snapshot, takeID: takeID)
    results.stringValue = finishedNaturally ? "TAKE COMPLETE" : "TAKE STOPPED"
    refreshUnlockReview()
  }

  private func registerCommittedPractice() {
    // A queued take may belong to a lesson visited earlier in this session.
    // Resolve its captured version, never the lesson currently on screen.
    for attempt in history.attempts where pendingPracticeMarks.contains(attempt.id) {
      guard !history.hasPendingSave(id: attempt.id) else { continue }
      guard attempt.matched > 0,
        let definition = DrumxCourse.lessons.first(where: { $0.version == attempt.settings.lessonVersion })
      else { pendingPracticeMarks.remove(attempt.id); continue }
      if progress.markPracticeCompleted(lessonID: definition.id, version: definition.version,
        recall: attempt.settings.mode == 2 && !attempt.settings.liveFeedback, at: attempt.endedAt) {
        pendingPracticeMarks.remove(attempt.id)
      }
    }
  }

  @discardableResult
  func retryPendingHistory(force: Bool = false) -> Bool {
    guard !transportActive else { return !history.hasPendingSaves }
    let now = DrumxIO.hostNowSeconds()
    guard force || now >= nextHistoryRetry else { return !history.hasPendingSaves }
    let hadPending = history.hasPendingSaves
    guard hadPending || !pendingPracticeMarks.isEmpty else { return true }
    nextHistoryRetry = now + 1
    let saved = history.retryPendingSaves()
    if saved {
      registerCommittedPractice()
      if showingReview { updateReview(saveResult: false) }
      if currentPage == .course { refreshCourse() }
      if currentPage == .prepare { refreshLesson() }
      if currentPage == .mainMenu {
        let state = unlockState
        mainMenuView.update(lesson: lesson, player: progress.selectedProfile.name,
          unlocked: state.availableIDs.count, cleared: state.clearedIDs.count)
      }
      if let error = progress.lastError { setStatus(error) }
      else if hadPending { setStatus("Your takes are saved on this Mac.") }
    } else {
      setStatus(history.lastError ?? "Your takes are waiting to save. Keep Drumx open and retry before quitting.")
    }
    return !history.hasPendingSaves
  }

  func prepareHistoryForPlayerChange() -> Bool {
    _ = retryPendingHistory(force: true)
    guard !history.hasPendingSaves else {
      playerError.stringValue = "This player has \(history.pendingSaveCount) \(history.pendingSaveCount == 1 ? "take" : "takes") waiting to save. Keep this session open and retry before changing players."
      setStatus(history.lastError ?? playerError.stringValue)
      return false
    }
    return true
  }

  func resetHistorySaveTracking() {
    pendingPracticeMarks.removeAll()
    nextHistoryRetry = 0
  }

  func confirmApplicationClose() -> Bool {
    if allowsUnsavedExit { return true }
    guard !closePromptActive else { return false }
    // Closing ends the active phrase. Only actual completed unsaved attempts
    // below can prompt; a partial take never creates a hypothetical warning.
    if transportActive { stopTake() }
    _ = retryPendingHistory(force: true)
    while history.hasPendingSaves {
      let count = history.pendingSaveCount
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "\(count) \(count == 1 ? "take is" : "takes are") waiting to save."
      alert.informativeText = "Your results are kept in this session. Retry saving, or keep Drumx open. Quitting now will lose these unsaved takes."
      alert.addButton(withTitle: "Retry saving")
      alert.addButton(withTitle: "Keep playing")
      alert.addButton(withTitle: "Quit without saving")
      alert.buttons[1].keyEquivalent = "\u{1b}"
      closePromptActive = true
      let response = alert.runModal()
      closePromptActive = false
      switch response {
      case .alertFirstButtonReturn:
        _ = retryPendingHistory(force: true)
      case .alertThirdButtonReturn:
        // Also covers the app termination caused by closing the last window.
        allowsUnsavedExit = true
        return true
      default:
        return false
      }
    }
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool { confirmApplicationClose() }

  private func tick() {
    let now = DrumxIO.hostNowSeconds()
    let hadPulses = !hitFeedback.pulses.isEmpty
    hitFeedback.prune(at: now)
    if demonstrating {
      // Display only: audio was scheduled once on the native audio clock.
      // Animate demo strikes at their planned host time, without scoring them.
      let song = now - practiceStart
      for index in 0..<dx_core_event_count(core) {
        var event = DXEvent()
        guard dx_core_event(core, index, &event) == 1,
          event.time_seconds > lastDemoVisualTime, event.time_seconds <= song,
          song - event.time_seconds < DrumxHitFeedback.duration
        else { continue }
        hitFeedback.record(
          pad: Int(event.pad), judgment: nil, velocity: 0.8, offsetMS: 0,
          at: practiceStart + event.time_seconds, revealJudgment: false)
      }
      lastDemoVisualTime = song
    }
    if running {
      let song = now - practiceStart
      dx_core_advance(core, song)
      dx_core_snapshot(core, &snapshot)
      if song > dx_core_duration(core) + 0.15 { finishTake(naturally: true, atHostTime: now) }
    } else if demonstrating && now > demoEnd + 0.05 {
      demonstrating = false
      io.stopDemo()
      io.stopClick()
      showPage(.prepare)
      setStatus("That's the pattern. Count \(lesson.counts), then try it yourself.")
    }
    if !transportActive { _ = retryPendingHistory() }
    if now - lastStatusUpdate > 0.12 {
      updateKitMenuLegend()
      if running {
        if now < practiceStart {
          runScoreHUD.update(score: nil, bestPoints: nil, state: "COUNT-IN")
          results.stringValue = "COUNT-IN"
        } else if showLive {
          let score = DrumxRunScore(snapshot: snapshot, completedNaturally: false)
          runScoreHUD.update(score: score, bestPoints: previousBestPoints, state: "PLAYING")
          results.stringValue = "\(score.points) points, \(score.stars) stars, \(score.combo) combo"
        } else {
          runScoreHUD.update(score: nil, bestPoints: nil, state: "RESULTS AFTER THE PHRASE")
          results.stringValue = "RESULTS AFTER THE PHRASE"
        }
      }
      let phase =
        transportActive
        ? (now < practiceStart
          ? "Count-in" : demonstrating ? "Listening to demonstration" : "Playing")
        : showingReview ? "Review" : "Ready"
      scene.setAccessibilityLabel(
        "Practice rail. \(phase). \(modeNames[mode]). \(results.stringValue). Hi-hat A, snare S, kick Space. Shift for a softer hit."
      )
      lastStatusUpdate = now
    }
    if transportActive || hadPulses || !hitFeedback.pulses.isEmpty { scene.needsDisplay = true }
  }
}

final class LabAppDelegate: NSObject, NSApplicationDelegate {
  var controller: LabController?
  func applicationDidFinishLaunching(_ notification: Notification) {
    controller = LabController()
    let settings = NSMenuItem(title: "Settings…", action: #selector(LabController.showSetup), keyEquivalent: ",")
    settings.target = controller
    NSApp.mainMenu?.items.first?.submenu?.insertItem(settings, at: 0)
    NSApp.mainMenu?.items.first?.submenu?.insertItem(.separator(), at: 1)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    controller?.confirmApplicationClose() == false ? .terminateCancel : .terminateNow
  }
  func applicationWillTerminate(_ notification: Notification) {
    if controller?.currentPage == .settings { controller?.leaveSettings() }
    controller?.saveResume()
    controller?.io.stopClick()
    controller?.io.stopDemo()
  }
}

@main enum DrumxLabMain {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let menu = NSMenu()
    let item = NSMenuItem()
    menu.addItem(item)
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit Drumx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = appMenu
    app.mainMenu = menu
    let delegate = LabAppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
