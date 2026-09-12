import AppKit
import CoreMIDI
import Darwin

private let padNames = ["Hi-hat", "Snare", "Kick"]
private let ink = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
private let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
private let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)

final class LessonButton: NSButton {
  var primary = false
  override var intrinsicContentSize: NSSize {
    NSSize(
      width: max(
        110,
        (title as NSString).size(withAttributes: [
          .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
        ]).width + 36), height: 43)
  }
  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    (primary
      ? lime.withAlphaComponent(isHighlighted ? 0.7 : 1)
      : NSColor.white.withAlphaComponent(isHighlighted ? 0.12 : 0.055)).setFill()
    path.fill()
    if !primary {
      NSColor.white.withAlphaComponent(0.12).setStroke()
      path.stroke()
    }
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
      .foregroundColor: primary ? ink : paper,
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
    if let pad = ["a": 0, "s": 1, " ": 2][event.charactersIgnoringModifiers?.lowercased() ?? ""] {
      controller?.keyboardHit(
        pad: pad, velocity: event.modifierFlags.contains(.shift) ? 48 : 108,
        hostTime: event.timestamp)
    } else {
      super.keyDown(with: event)
    }
  }
}

final class LabController: NSObject {
  let io = DrumxIO()
  let core: OpaquePointer
  let scene = PracticeView()
  let root = LessonRootView()
  let prepareView = NSView(), reviewView = NSView()
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
  private let history = LessonHistory()
  private var takeID = UUID(), takeSettings: TakeSettings?, endedAt = Date()
  private var takeWindow: DrumxTakeWindow?
  private var finishedNaturally = false
  private var timer: Timer?, lastStatusUpdate = 0.0
  private var showingReview = false
  private var demoEnd = 0.0
  private var lastDemoVisualTime = -Double.infinity
  let window: NSWindow
  private var setupWindow: NSWindow?
  let sourceMenu = NSPopUpButton(), modeMenu = NSPopUpButton()
  let tempoSlider = NSSlider(value: 96, minValue: 48, maxValue: 144, target: nil, action: nil)
  let tempoLabel = NSTextField(labelWithString: "96 BPM")
  let liveToggle = NSButton(checkboxWithTitle: "Live timing", target: nil, action: nil)
  let offsetField = NSTextField(string: "0")
  let soundToggle = NSButton(checkboxWithTitle: "Drum sound", target: nil, action: nil)
  let volumeSlider = NSSlider(value: 0.7, minValue: 0, maxValue: 1, target: nil, action: nil)
  let soundStatus = NSTextField(labelWithString: "Loading drum sounds…")
  let status = NSTextField(labelWithString: "Keyboard ready. Connect a MIDI kit in Kit & sound.")
  let setupStatus = NSTextField(
    labelWithString: "Choose your MIDI input, then play each pad to check its sound.")
  let results = NSTextField(labelWithString: "LISTEN   /   PLAY   /   REMEMBER")
  private let runScoreHUD = RunScoreHUD()
  private let runScoreReview = RunScoreReviewView()
  private var previousBestPoints: Int?
  let play = LessonButton(title: "Stop take", target: nil, action: nil)
  let kitButton = LessonButton(title: "Kit & sound", target: nil, action: nil)
  let homeButton = LessonButton(title: "Lesson", target: nil, action: nil)
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
    window.title = "Drumx · Your first backbeat"
    window.minSize = NSSize(width: 1020, height: 780)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = ink
    window.titlebarAppearsTransparent = true
    if let saved = UserDefaults.standard.array(forKey: "drumx.lab.mapping") as? [[Int]],
      saved.count == 3
    {
      mappings = saved.map { $0.filter { (0...127).contains($0) } }
    }
    let savedOffset = UserDefaults.standard.double(forKey: "drumx.lab.inputOffsetMS")
    calibrationMS = savedOffset.isFinite ? min(200, max(-200, savedOffset)) : 0
    offsetField.stringValue = String(format: "%.0f", calibrationMS)
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
    io.onSourcesChanged = { [weak self] sources in self?.updateSources(sources) }
    io.onStatusChanged = { [weak self] message in self?.setStatus(message) }
    io.onAudioInterrupted = { [weak self] message in
      self?.stopTake()
      self?.setStatus(message)
    }
    updateSources(io.sources)
    resetCore()
    showPage(.prepare)
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

  private func label(
    _ text: String, _ size: CGFloat = 13, weight: NSFont.Weight = .regular,
    color: NSColor = .secondaryLabelColor
  ) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    return l
  }
  private func row(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let r = NSStackView(views: views)
    r.orientation = .horizontal
    r.spacing = spacing
    r.alignment = .centerY
    return r
  }
  private func column(_ views: [NSView], spacing: CGFloat = 16) -> NSStackView {
    let c = NSStackView(views: views)
    c.orientation = .vertical
    c.alignment = .leading
    c.spacing = spacing
    return c
  }
  private func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return v
  }
  private func button(_ title: String, _ action: Selector, primary: Bool = false) -> LessonButton {
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
  private func center(_ child: NSView, in parent: NSView, width: CGFloat = 880) {
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
      [logo, label("FOUNDATIONS  /  01", 10, weight: .semibold), spacer(), results, runScoreHUD, kitButton],
      spacing: 22)
    runScoreHUD.widthAnchor.constraint(equalToConstant: 420).isActive = true
    runScoreHUD.heightAnchor.constraint(equalToConstant: 44).isActive = true
    results.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
    results.textColor = .secondaryLabelColor
    kitButton.target = self
    kitButton.action = #selector(showSetup)
    kitButton.isBordered = false
    play.target = self
    play.action = #selector(stopAction)
    play.isBordered = false
    homeButton.target = self
    homeButton.action = #selector(backToLesson)
    homeButton.isBordered = false
    status.font = .systemFont(ofSize: 11)
    status.lineBreakMode = .byTruncatingMiddle
    status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let bottom = row(
      [status, spacer(), label("A  hi-hat     S  snare     SPACE  kick", 11), homeButton, play],
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
    for page in [prepareView, scene, reviewView] { anchor(page, in: main) }
    buildPreparation()
    buildReview()
  }

  private func buildPreparation() {
    let eyebrow = label("YOUR FIRST GROOVE", 11, weight: .semibold, color: lime)
    let title = label("Your first backbeat.", 52, weight: .bold, color: paper)
    let intro = label(
      "Keep the hi-hat steady. Let the snare carry beats 2 and 4.", 18,
      color: paper.withAlphaComponent(0.75))
    let notation = GrooveNotationView()
    notation.heightAnchor.constraint(equalToConstant: 172).isActive = true
    notation.wantsLayer = true
    notation.layer?.cornerRadius = 14
    notation.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
    notation.setAccessibilityElement(true)
    notation.setAccessibilityRole(.image)
    notation.setAccessibilityLabel(
      "One bar in four-four time. Hi-hat plays eight eighth notes, counted 1 and 2 and 3 and 4 and. Snare plays on beats 2 and 4. Kick plays on beats 1 and 3. Sticking suggestions: right hand hi-hat, left hand snare."
    )
    let plan = row([
      column(
        [
          label("01  HEAR IT", 11, weight: .semibold, color: paper),
          label("Listen, then count out loud.", 13),
        ], spacing: 7), spacer(),
      column(
        [
          label("02  PLAY IT", 11, weight: .semibold, color: paper),
          label("Follow one shared timing line.", 13),
        ], spacing: 7), spacer(),
      column(
        [
          label("03  REMEMBER IT", 11, weight: .semibold, color: paper),
          label("Keep the groove when notes fade.", 13),
        ], spacing: 7),
    ])
    tempoSlider.target = self
    tempoSlider.action = #selector(settingsChanged)
    tempoSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
    tempoSlider.setAccessibilityLabel("Practice tempo")
    tempoLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
    tempoLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true
    modeMenu.addItems(withTitles: modeNames)
    modeMenu.target = self
    modeMenu.action = #selector(settingsChanged)
    modeMenu.setAccessibilityLabel("Visual guidance")
    liveToggle.target = self
    liveToggle.action = #selector(liveChanged(_:))
    liveToggle.state = .on
    liveToggle.toolTip =
      "Shows early/late feedback as you play. Turn off for a click-only memory check."
    let controls = row(
      [
        label("TEMPO", 10, weight: .semibold), tempoSlider, tempoLabel, spacer(), modeMenu,
        liveToggle,
      ], spacing: 16)
    let actions = row(
      [
        button("Start playing", #selector(beginLesson), primary: true),
        button("Hear the groove", #selector(hearDemo)), label("4-beat count-in · 4 short bars", 12),
      ], spacing: 16)
    let stack = column([eyebrow, title, intro, notation, plan, controls, actions], spacing: 23)
    [notation, plan, controls].forEach {
      $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    center(stack, in: prepareView)
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
    let actions = row([
      retryButton, button("Slow it down", #selector(slowerTake)), loopButton, challengeButton,
    ])
    let stack = column(
      [
        label("LISTEN. ADJUST. GO AGAIN.", 11, weight: .semibold, color: lime), reviewConditions,
        reviewTitle, reviewDetail, runScoreReview, stats, scoreCaption, personalBest,
        actions,
      ], spacing: 16)
    [reviewDetail, runScoreReview, stats].forEach {
      $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    center(stack, in: reviewView)
  }

  private enum Page { case prepare, stage, review }
  private func showPage(_ page: Page) {
    showingReview = page == .review
    prepareView.isHidden = page != .prepare
    scene.isHidden = page != .stage
    reviewView.isHidden = page != .review
    kitButton.isHidden = page == .stage
    homeButton.isHidden = page != .review
    play.isHidden = page != .stage
    runScoreHUD.isHidden = page != .stage
    results.isHidden = page == .stage
    if page == .prepare { results.stringValue = "LISTEN   /   PLAY   /   REMEMBER" }
    focusStage()
  }
  private func focusStage() {
    if setupWindow == nil { window.makeFirstResponder(transportActive ? scene : root) }
  }
  private func setStatus(_ text: String) {
    status.stringValue = text
    setupStatus.stringValue = text
  }
  private func resetCore() {
    completed = false
    finishedNaturally = false
    takeWindow = nil
    hitFeedback.reset()
    runScoreHUD.update(score: nil, bestPoints: nil, state: "COUNT-IN")
    lastDemoVisualTime = -Double.infinity
    _ = dx_core_reset(core, tempo, Int32(lessonBars))
    dx_core_set_guidance(core, Int32(mode))
    dx_core_snapshot(core, &snapshot)
    scene.needsDisplay = true
  }
  private func refreshMappingLabels() {
    for pad in 0..<mappingButtons.count {
      mappingButtons[pad].title =
        "\(padNames[pad]): \(mappings[pad].map(String.init).joined(separator: "/"))"
    }
  }
  private func updateSources(_ sources: [MIDISourceInfo]) {
    let previous = (sourceMenu.selectedItem?.representedObject as? NSNumber)?.int32Value
    if let previous, !sources.contains(where: { $0.id == previous }) {
      stopTake()
      setStatus("MIDI disconnected. Reconnect or choose an input in Kit & sound.")
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
  }

  @objc func showSetup() {
    guard !transportActive, setupWindow == nil else { return }
    let panel = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 350), styleMask: [.titled],
      backing: .buffered, defer: false)
    panel.title = "Your kit"
    panel.appearance = window.appearance
    let content = LessonRootView()
    content.controller = self
    panel.contentView = content
    panel.initialFirstResponder = content
    setupStatus.stringValue = "Choose an input. To map a pad, click its button and strike it once."
    sourceMenu.target = self
    sourceMenu.action = #selector(sourceChanged)
    sourceMenu.widthAnchor.constraint(equalToConstant: 260).isActive = true
    if mappingButtons.isEmpty {
      for pad in 0..<3 {
        let b = NSButton(title: "", target: self, action: #selector(learnMapping(_:)))
        b.tag = pad
        mappingButtons.append(b)
      }
    }
    refreshMappingLabels()
    soundToggle.target = self
    soundToggle.action = #selector(soundChanged)
    soundToggle.toolTip =
      "Turn off if you listen to your module's own drum sounds. The lesson demo remains audible."
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeChanged)
    volumeSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
    volumeSlider.setAccessibilityLabel("Drum sound and demo volume")
    offsetField.widthAnchor.constraint(equalToConstant: 58).isActive = true
    offsetField.target = self
    offsetField.action = #selector(offsetChanged)
    offsetField.toolTip =
      "Subtracted from input timestamps before scoring. This does not measure physical kit latency."
    let hands = NSButton(
      checkboxWithTitle: "R / L sticking suggestions", target: self,
      action: #selector(handsChanged(_:)))
    hands.state = showHands ? .on : .off
    soundStatus.font = .systemFont(ofSize: 11)
    setupStatus.font = .systemFont(ofSize: 12)
    setupStatus.lineBreakMode = .byTruncatingTail
    let stack = column(
      [
        row([label("MIDI INPUT", 11, weight: .semibold), sourceMenu, spacer()]),
        row([label("MAP A PAD", 11, weight: .semibold)] + mappingButtons),
        row([soundToggle, label("Volume"), volumeSlider, spacer(), hands]), soundStatus,
        row([label("Input offset (ms)"), offsetField, label("Shift + key plays a softer hit.", 12)]
        ),
        setupStatus, row([spacer(), button("Done", #selector(closeSetup), primary: true)]),
      ], spacing: 18)
    stack.arrangedSubviews.forEach {
      $0.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
    }
    center(stack, in: content, width: 744)
    setupWindow = panel
    window.beginSheet(panel)
    panel.makeFirstResponder(content)
  }
  @objc func closeSetup() {
    offsetChanged()
    learning = nil
    io.setMIDILearnActive(false)
    if let panel = setupWindow {
      window.endSheet(panel)
      panel.orderOut(nil)
    }
    setupWindow = nil
    focusStage()
  }
  @objc func sourceChanged() {
    stopTake()
    completed = false
    learning = nil
    io.setMIDILearnActive(false)
    io.connect(sourceID: (sourceMenu.selectedItem?.representedObject as? NSNumber)?.int32Value)
  }
  @objc func learnMapping(_ sender: NSButton) {
    guard !transportActive else { return }
    completed = false
    learning = sender.tag
    io.setMIDILearnActive(true)
    setStatus("Hit your \(padNames[sender.tag].lowercased()) once to map it.")
  }
  @objc func settingsChanged() {
    guard !transportActive else { return }
    tempo = tempoSlider.doubleValue.rounded()
    tempoLabel.stringValue = "\(Int(tempo)) BPM"
    mode = modeMenu.indexOfSelectedItem
    resetCore()
    focusStage()
  }
  @objc func handsChanged(_ sender: NSButton) {
    showHands = sender.state == .on
    scene.needsDisplay = true
  }
  @objc func liveChanged(_ sender: NSButton) {
    showLive = sender.state == .on
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
  @objc func volumeChanged() { io.setMonitorVolume(Float(volumeSlider.doubleValue)) }
  func dismissOrStop() { setupWindow != nil ? closeSetup() : stopTake() }
  func quickStart() {
    if setupWindow != nil {
      closeSetup()
      return
    }
    guard !transportActive else { return }
    showingReview ? startTake() : beginLesson()
  }
  @objc func beginLesson() {
    lessonBars = 4
    startTake()
  }
  @objc func retryTake() { startTake() }
  @objc func stopAction() { stopTake() }
  @objc func slowerTake() {
    tempo = max(48, tempo - 8)
    tempoSlider.doubleValue = tempo
    tempoLabel.stringValue = "\(Int(tempo)) BPM"
    startTake()
  }
  @objc func repairBar() {
    // This first lesson repeats the same bar. A one-bar take isolates that groove.
    lessonBars = lessonBars == 1 ? 4 : 1
    mode = 0
    modeMenu.selectItem(at: mode)
    startTake()
  }
  @objc func nextChallenge() {
    lessonBars = 4
    if mode == 0 {
      mode = 1
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
    lessonBars = 4
    resetCore()
    showPage(.prepare)
    setStatus(
      "\(io.selectedSourceID == nil ? "Keyboard" : "MIDI kit") ready. Find a comfortable tempo.")
  }
  @objc func hearDemo() {
    guard !transportActive else { return }
    lessonBars = 4
    resetCore()
    learning = nil
    io.setMIDILearnActive(false)
    clickStart = DrumxIO.hostNowSeconds() + 0.75
    practiceStart = clickStart + 240 / tempo
    guard io.startDemo(bpm: tempo, firstBeatHostTime: practiceStart, bars: lessonBars) else {
      setStatus("Couldn't start the drum demo. Check Kit & sound.")
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
    setStatus("Listen for the snare on 2 and 4. Count 1 & 2 & 3 & 4 &.")
  }
  func startTake() {
    guard !transportActive else { return }
    offsetChanged()
    learning = nil
    io.setMIDILearnActive(false)
    io.stopDemo()
    resetCore()
    usedLiveFeedback = showLive
    takeID = UUID()
    takeSettings = TakeSettings(
      tempo: tempo, mode: mode, liveFeedback: showLive, bars: lessonBars,
      calibrationMS: calibrationMS,
      inputIdentity: io.selectedSourceID.map { "midi:\($0)" } ?? "keyboard", mapping: mappings,
      handHints: showHands)
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
        : "\(lessonBars == 1 ? "One-bar practice" : "Four bars") · \(modeNames[mode]) · Esc to stop"
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
    if let pad = learning, !transportActive {
      for i in 0..<3 { mappings[i].removeAll { $0 == note } }
      mappings[pad] = [note]
      learning = nil
      io.setMIDIMapping(mappings)
      io.setMIDILearnActive(false)
      UserDefaults.standard.set(mappings, forKey: "drumx.lab.mapping")
      refreshMappingLabels()
      setStatus("Mapped \(padNames[pad]) to note \(note).")
      return
    }
    guard let pad = mappings.firstIndex(where: { $0.contains(note) }) else { return }
    receive(
      pad: pad, velocity: Double(velocity) / 127, hostTime: time,
      inputIdentity: io.selectedSourceID.map { "midi:\($0)" } ?? "midi:disconnected")
  }
  func keyboardHit(pad: Int, velocity: Int, hostTime: Double) {
    // Capture time stays in the native host clock domain even if UI delivery is late.
    io.playPad(pad: pad, velocity: velocity)
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
  private func updateReview() {
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
      let attempt = history.record(
        id: takeID, settings: settings, snapshot: snapshot, completedNaturally: finishedNaturally,
        endedAt: endedAt)
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
    results.stringValue = finishedNaturally ? "TAKE COMPLETE" : "TAKE STOPPED"
  }
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
      setStatus("That's the backbeat. Keep the hi-hat even and try it yourself.")
    }
    if now - lastStatusUpdate > 0.12 {
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
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationWillTerminate(_ notification: Notification) {
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
