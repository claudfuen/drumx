import AppKit
import CoreMIDI
import Darwin

private let padNames = ["Hi-hat", "Snare", "Kick"]

final class PracticeView: NSView {
  weak var controller: LabController?
  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { true }

  override func keyDown(with event: NSEvent) {
    guard !event.isARepeat else { return }
    if event.keyCode == 53 {
      controller?.stopTake()
      return
    }
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if let pad = ["a": 0, "s": 1, " ": 2][key] {
      controller?.keyboardHit(
        pad: pad, velocity: event.modifierFlags.contains(.shift) ? 48 : 108,
        hostTime: event.timestamp)
    } else {
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

  private func text(
    _ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 12,
    color: NSColor = .secondaryLabelColor, centered: Bool = false
  ) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color,
    ]
    let string = value as NSString
    let width = string.size(withAttributes: attrs).width
    string.draw(at: NSPoint(x: centered ? x - width / 2 : x, y: y), withAttributes: attrs)
  }

  private func line(_ a: NSPoint, _ b: NSPoint, color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    let p = NSBezierPath()
    p.move(to: a)
    p.line(to: b)
    p.lineWidth = width
    p.stroke()
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    guard let c = controller else { return }
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let hat =
      dark
      ? NSColor(calibratedRed: 0.58, green: 0.80, blue: 0.86, alpha: 1)
      : NSColor(calibratedRed: 0.15, green: 0.43, blue: 0.49, alpha: 1)
    let snare =
      dark
      ? NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
      : NSColor(calibratedRed: 0.27, green: 0.43, blue: 0.10, alpha: 1)
    let kick =
      dark
      ? NSColor(calibratedRed: 0.91, green: 0.68, blue: 0.40, alpha: 1)
      : NSColor(calibratedRed: 0.64, green: 0.31, blue: 0.10, alpha: 1)
    let memoryColor = NSColor.systemPurple
    let colors = [hat, snare, kick]
    let now = DrumxIO.hostNowSeconds()
    let rawTime = c.running ? now - c.practiceStart : 0
    let songTime = max(0, rawTime)
    let beat = songTime * c.tempo / 60
    let look = 4.0 * 60 / c.tempo
    let top: CGFloat = 49
    let strike = max(200, bounds.height - 190)
    let center = bounds.midX
    let bottomWidth = min(790, bounds.width - 110)
    let topWidth = bottomWidth * 0.48
    func half(_ depth: CGFloat) -> CGFloat { (topWidth + (bottomWidth - topWidth) * depth) / 2 }
    func yy(_ depth: CGFloat) -> CGFloat { top + (strike - top) * depth }
    func handX(_ pad: Int, _ depth: CGFloat) -> CGFloat {
      center - half(depth) + (CGFloat(pad == 0 ? 0 : 2) + 0.5) * half(depth) * 2 / 7
    }
    func surface(_ low: CGFloat, _ high: CGFloat) -> NSBezierPath {
      let p = NSBezierPath()
      p.move(to: NSPoint(x: center - half(low), y: yy(low)))
      p.line(to: NSPoint(x: center + half(low), y: yy(low)))
      p.line(to: NSPoint(x: center + half(high), y: yy(high)))
      p.line(to: NSPoint(x: center - half(high), y: yy(high)))
      p.close()
      return p
    }
    let memory =
      c.running && rawTime >= 0 && (c.mode == 2 || (c.mode == 1 && Int(beat / 4) % 2 == 1))
    text(
      c.running
        ? (rawTime < 0 ? "Count-in" : memory ? "From memory" : "Keep the backbeat")
        : "Hold a steady backbeat.", x: 20, y: 8, size: 16, color: .labelColor)
    text("\(Int(c.tempo)) BPM · \(c.modeNames[c.mode])", x: bounds.width - 240, y: 12)
    NSColor.controlBackgroundColor.setFill()
    surface(0, 1).fill()
    if c.mode == 2 {
      memoryColor.withAlphaComponent(0.07).setFill()
      surface(0, 1).fill()
    } else if c.mode == 1 {
      for bar in [1, 3] {
        let start = Double(bar * 4) * 60 / c.tempo
        let end = start + 4 * 60 / c.tempo
        let near = max(0, start - songTime)
        let far = min(look, end - songTime)
        if far <= near || near >= look || far <= 0 { continue }
        let d0 = CGFloat(1 - far / look)
        let d1 = CGFloat(1 - near / look)
        memoryColor.withAlphaComponent(0.09).setFill()
        surface(d0, d1).fill()
        if yy(d1) - yy(d0) > 28 {
          text(
            "FROM MEMORY", x: center, y: yy(d1) - 24, size: 11, color: memoryColor, centered: true)
        }
      }
    }
    for lane in 0...7 {
      line(
        NSPoint(x: center - topWidth / 2 + CGFloat(lane) * topWidth / 7, y: top),
        NSPoint(x: center - bottomWidth / 2 + CGFloat(lane) * bottomWidth / 7, y: strike),
        color: NSColor.separatorColor.withAlphaComponent(0.55))
    }
    if c.mode != 2 {
      for i in 0...16 {
        let t = Double(i) * 60 / c.tempo
        let ahead = t - songTime
        if ahead < 0 || ahead > look { continue }
        let d = CGFloat(1 - ahead / look)
        let y = yy(d)
        line(
          NSPoint(x: center - half(d), y: y), NSPoint(x: center + half(d), y: y),
          color: NSColor.separatorColor.withAlphaComponent(0.5), width: i % 4 == 0 ? 1.5 : 0.7)
      }
    } else {
      text(
        "FROM MEMORY", x: center, y: top + (strike - top) * 0.45, size: 13, color: memoryColor,
        centered: true)
    }
    line(
      NSPoint(x: center - bottomWidth / 2 - 8, y: strike),
      NSPoint(x: center + bottomWidth / 2 + 8, y: strike), color: .labelColor, width: 1.5)
    for pad in 0..<3 {
      let flash = max(0, 1 - (now - c.flashes[pad]) / 0.18)
      if flash > 0 {
        colors[pad].withAlphaComponent(flash * 0.45).setFill()
        let rect =
          pad == 2
          ? NSRect(x: center - bottomWidth / 2, y: strike - 4, width: bottomWidth, height: 8)
          : NSRect(x: handX(pad, 1) - 34, y: strike - 11, width: 68, height: 22)
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
      }
    }
    // All visual events come from the scoring core's expected-event list.
    for index in 0..<dx_core_event_count(c.core) {
      var event = DXEvent()
      guard dx_core_event(c.core, index, &event) == 1 else { continue }
      let ahead = event.time_seconds - songTime
      if ahead < -0.015 || ahead > look { continue }
      if c.mode == 2 || (c.mode == 1 && Int(event.time_seconds * c.tempo / 240) % 2 == 1) {
        continue
      }
      let d = CGFloat(max(0, 1 - ahead / look))
      let y = yy(d)
      let pad = Int(event.pad)
      let alpha: CGFloat = event.hit == 1 ? 0.25 : 1
      colors[pad].withAlphaComponent(alpha).setFill()
      if pad == 2 {
        NSBezierPath(
          roundedRect: NSRect(x: center - half(d) + 3, y: y - 3, width: 2 * half(d) - 6, height: 6),
          xRadius: 3, yRadius: 3
        ).fill()
        NSBezierPath(
          roundedRect: NSRect(x: center - 3, y: y - 4, width: 6, height: 13), xRadius: 2, yRadius: 2
        ).fill()
      } else {
        let x = handX(pad, d)
        let width = (pad == 0 ? 42.0 : 48.0) * (0.7 + 0.3 * d)
        NSBezierPath(
          roundedRect: NSRect(x: x - width / 2, y: y - 10, width: width, height: 20),
          xRadius: pad == 0 ? 3 : 9, yRadius: pad == 0 ? 3 : 9
        ).fill()
        if c.showHands {
          text(
            pad == 0 ? "R" : "L", x: x, y: y - 7, size: 11, color: dark ? .black : .white,
            centered: true)
        }
      }
    }
    // Fixed starter kit profile. Inactive surfaces keep their space from day one.
    let surfaces = ["HI-HAT · A", "CRASH", "SNARE · S", "TOM 1", "TOM 2", "FLOOR", "RIDE"]
    for slot in 0..<surfaces.count {
      let x = center - bottomWidth / 2 + (CGFloat(slot) + 0.5) * bottomWidth / 7
      let color: NSColor = slot == 0 ? hat : slot == 2 ? snare : .tertiaryLabelColor
      text(surfaces[slot], x: x, y: strike + 20, size: 11, color: color, centered: true)
    }
    text("KICK  ·  SPACE", x: center, y: strike + 43, color: kick, centered: true)
    if c.running && rawTime < 0 {
      let count = min(4, max(1, Int((now - c.clickStart) * c.tempo / 60) + 1))
      text(String(count), x: center, y: top + 50, size: 72, color: .labelColor, centered: true)
    }
    let meterY = strike + 91
    let meterLeft = center - 100
    let meterRight = center + 100
    if c.showLive || !c.running {
      text("EARLY", x: meterLeft, y: meterY - 23, size: 11)
      text("ON TIME", x: center, y: meterY - 23, size: 11, centered: true)
      text("LATE", x: meterRight - 28, y: meterY - 23, size: 11)
      let biases = [c.snapshot.bias.0, c.snapshot.bias.1, c.snapshot.bias.2]
      for pad in 0..<3 {
        let bias = biases[pad]
        let rowY = meterY + CGFloat(pad) * 23
        text(padNames[pad], x: meterLeft - 82, y: rowY - 7, size: 11, color: colors[pad])
        line(
          NSPoint(x: meterLeft, y: rowY), NSPoint(x: meterRight, y: rowY), color: .separatorColor)
        line(
          NSPoint(x: center, y: rowY - 4), NSPoint(x: center, y: rowY + 4),
          color: .tertiaryLabelColor)
        if bias.sample_count >= 4 && bias.state != 5 {
          let x = center + CGFloat(min(80, max(-80, bias.offset_ms))) / 80 * 100
          colors[pad].setFill()
          NSBezierPath(ovalIn: NSRect(x: x - 3, y: rowY - 3, width: 6, height: 6)).fill()
        }
        let label: String
        switch bias.state {
        case 0: label = "\(bias.sample_count)/4 hits"
        case 4: label = "Uneven timing"
        case 5: label = "Waiting for hits"
        default: label = String(format: "%+.0f ms", bias.offset_ms)
        }
        text(label, x: meterRight + 15, y: rowY - 7, size: 11)
      }
    } else {
      text("Timing feedback after the phrase", x: center, y: meterY, size: 12, centered: true)
    }
  }
}

final class LabController: NSObject {
  let io = DrumxIO()
  let core: OpaquePointer
  let scene = PracticeView()
  var snapshot = DXSnapshot()
  var running = false, completed = false
  var usedLiveFeedback = false
  var tempo = 96.0, mode = 0, showHands = true, showLive = true
  var practiceStart = 0.0, clickStart = 0.0, calibrationMS = 0.0
  var flashes = [Double](repeating: -100, count: 3)
  var mappings = [[42, 44, 46], [38, 40], [35, 36]]
  var learning: Int?
  var drumSound = true
  let soundToggle = NSButton(checkboxWithTitle: "Drum sound", target: nil, action: nil)
  let volumeSlider = NSSlider(value: 0.7, minValue: 0, maxValue: 1, target: nil, action: nil)
  let soundStatus = NSTextField(labelWithString: "Loading drum sounds…")
  let modeNames = ["Guided", "Hidden bars", "From memory"]
  private var timer: Timer?
  private var lastStatusUpdate = 0.0
  let window: NSWindow
  let sourceMenu = NSPopUpButton(), modeMenu = NSPopUpButton()
  let tempoSlider = NSSlider(value: 96, minValue: 48, maxValue: 144, target: nil, action: nil)
  let tempoLabel = NSTextField(labelWithString: "96 BPM")
  let offsetField = NSTextField(string: "0")
  let status = NSTextField(labelWithString: "Choose MIDI input or use A, S and Space.")
  let results = NSTextField(labelWithString: "Four bars · steady eighth-note hi-hat")
  let play = NSButton(title: "Play", target: nil, action: nil)
  var mappingButtons: [NSButton] = []
  var configurationRows: [NSView] = []

  override init() {
    guard let core = dx_core_create() else { fatalError("Could not create scoring core") }
    self.core = core
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init()
    window.title = "Drumx · Native timing prototype"
    window.minSize = NSSize(width: 1000, height: 730)
    if let saved = UserDefaults.standard.array(forKey: "drumx.lab.mapping") as? [[Int]],
      saved.count == 3
    {
      mappings = saved
    }
    calibrationMS = UserDefaults.standard.double(forKey: "drumx.lab.inputOffsetMS")
    offsetField.stringValue = String(format: "%.0f", calibrationMS)
    buildUI()
    scene.controller = self
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
    io.onStatusChanged = { [weak self] message in self?.status.stringValue = message }
    io.onAudioInterrupted = { [weak self] message in
      self?.stopTake()
      self?.status.stringValue = message
    }
    updateSources(io.sources)
    resetCore()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
      self?.tick()
    }
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(scene)
  }

  deinit {
    timer?.invalidate()
    io.stopClick()
    dx_core_destroy(core)
  }

  private func label(_ text: String, _ size: CGFloat = 12) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size)
    return l
  }
  private func row(_ views: [NSView]) -> NSStackView {
    let r = NSStackView(views: views)
    r.orientation = .horizontal
    r.spacing = 12
    r.alignment = .centerY
    return r
  }
  private func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return v
  }

  private func buildUI() {
    let root = NSView()
    window.contentView = root
    let logo = label("drumx", 26)
    logo.font = .systemFont(ofSize: 26, weight: .semibold)
    let heading = row([logo, label("NATIVE TIMING PROTOTYPE", 11), spacer(), results])
    sourceMenu.target = self
    sourceMenu.action = #selector(sourceChanged)
    sourceMenu.widthAnchor.constraint(equalToConstant: 250).isActive = true
    var inputs: [NSView] = [label("Input"), sourceMenu]
    for pad in 0..<3 {
      let b = NSButton(title: "", target: self, action: #selector(learnMapping(_:)))
      b.tag = pad
      mappingButtons.append(b)
      inputs.append(b)
    }
    inputs.append(spacer())
    let mappingRow = row(inputs)
    refreshMappingLabels()
    tempoSlider.target = self
    tempoSlider.action = #selector(settingsChanged)
    tempoSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
    modeMenu.addItems(withTitles: modeNames)
    modeMenu.target = self
    modeMenu.action = #selector(settingsChanged)
    let hands = NSButton(
      checkboxWithTitle: "L/R hints", target: self, action: #selector(handsChanged(_:)))
    hands.state = .on
    let live = NSButton(
      checkboxWithTitle: "Live timing", target: self, action: #selector(liveChanged(_:)))
    live.state = .on
    offsetField.widthAnchor.constraint(equalToConstant: 48).isActive = true
    offsetField.target = self
    offsetField.action = #selector(offsetChanged)
    offsetField.toolTip =
      "Fixed input offset in milliseconds, subtracted before scoring. This does not measure physical kit latency."
    let settings = row([
      tempoSlider, tempoLabel, modeMenu, hands, live, spacer(), label("Input offset (ms)"),
      offsetField,
    ])
    soundToggle.target = self
    soundToggle.action = #selector(soundChanged)
    soundToggle.toolTip = "Turn off when listening to the drum module's own sounds."
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeChanged)
    volumeSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true
    volumeSlider.setAccessibilityLabel("Drum sound volume")
    soundStatus.font = .systemFont(ofSize: 11)
    let audioRow = row([
      soundToggle, label("Volume"), volumeSlider, soundStatus, spacer(),
      label("Shift + key: softer hit", 11),
    ])
    let top = NSStackView(views: [heading, mappingRow, settings, audioRow])
    configurationRows = [mappingRow, settings, audioRow]
    top.orientation = .vertical
    top.alignment = .leading
    top.spacing = 13
    [heading, mappingRow, settings, audioRow].forEach {
      $0.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true
    }
    play.target = self
    play.action = #selector(togglePlay)
    play.bezelStyle = .rounded
    play.widthAnchor.constraint(equalToConstant: 125).isActive = true
    status.font = .systemFont(ofSize: 11)
    status.lineBreakMode = .byTruncatingMiddle
    let bottom = row([
      status, spacer(), label("A: hi-hat   S: snare   Space: kick   Esc: stop", 11), play,
    ])
    for view in [top, scene, bottom] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
      top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      scene.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
      scene.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      scene.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
      scene.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -8),
      bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
      bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
    ])
  }

  private func resetCore() {
    completed = false
    _ = dx_core_reset(core, tempo, 4)
    dx_core_set_guidance(core, Int32(mode))
    dx_core_snapshot(core, &snapshot)
    scene.needsDisplay = true
  }
  private func refreshMappingLabels() {
    for pad in 0..<3 {
      mappingButtons[pad].title =
        "\(padNames[pad]): \(mappings[pad].map(String.init).joined(separator:"/"))"
    }
  }
  private func updateSources(_ sources: [MIDISourceInfo]) {
    let previous = (sourceMenu.selectedItem?.representedObject as? NSNumber)?.int32Value
    if let previous, !sources.contains(where: { $0.id == previous }) {
      stopTake()
      status.stringValue = "MIDI source disconnected. Reconnect or choose another input."
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
  @objc func sourceChanged() {
    stopTake()
    learning = nil
    io.setMIDILearnActive(false)
    io.connect(sourceID: (sourceMenu.selectedItem?.representedObject as? NSNumber)?.int32Value)
    window.makeFirstResponder(scene)
  }
  @objc func learnMapping(_ sender: NSButton) {
    guard !running else { return }
    learning = sender.tag
    io.setMIDILearnActive(true)
    status.stringValue = "Hit your \(padNames[sender.tag].lowercased()) once to map it."
    window.makeFirstResponder(scene)
  }
  @objc func settingsChanged() {
    guard !running else { return }
    tempo = tempoSlider.doubleValue.rounded()
    tempoLabel.stringValue = "\(Int(tempo)) BPM"
    mode = modeMenu.indexOfSelectedItem
    resetCore()
    window.makeFirstResponder(scene)
  }
  @objc func handsChanged(_ sender: NSButton) {
    showHands = sender.state == .on
    scene.needsDisplay = true
    window.makeFirstResponder(scene)
  }
  @objc func liveChanged(_ sender: NSButton) {
    showLive = sender.state == .on
    scene.needsDisplay = true
    window.makeFirstResponder(scene)
  }
  @objc func offsetChanged() {
    guard !running else { return }
    let proposed = Double(offsetField.stringValue) ?? 0
    calibrationMS = proposed.isFinite ? min(200, max(-200, proposed)) : 0
    offsetField.stringValue = String(format: "%.0f", calibrationMS)
    UserDefaults.standard.set(calibrationMS, forKey: "drumx.lab.inputOffsetMS")
    window.makeFirstResponder(scene)
  }
  @objc func togglePlay() { running ? stopTake() : startTake() }

  private func setControls(_ enabled: Bool) {
    configurationRows.forEach { $0.isHidden = !enabled }
    tempoSlider.isEnabled = enabled
    modeMenu.isEnabled = enabled
    sourceMenu.isEnabled = enabled
    offsetField.isEnabled = enabled
    mappingButtons.forEach { $0.isEnabled = enabled }
  }
  func startTake() {
    offsetChanged()
    learning = nil
    io.setMIDILearnActive(false)
    resetCore()
    completed = false
    usedLiveFeedback = showLive
    clickStart = DrumxIO.hostNowSeconds() + 0.75
    practiceStart = clickStart + 240 / tempo
    guard io.startClick(bpm: tempo, firstBeatHostTime: clickStart, beats: 20) else {
      status.stringValue = io.statusDescription
      return
    }
    running = true
    setControls(false)
    play.title = "Stop"
    status.stringValue =
      drumSound
      ? "Drum sound on · keep the backbeat." : "Drum sound off · listening through your module."
    window.makeFirstResponder(scene)
  }
  func stopTake() {
    guard running else { return }
    dx_core_finish(core, DrumxIO.hostNowSeconds() - practiceStart)
    running = false
    completed = true  // Allow delayed events captured before the core's stop cutoff.
    io.stopClick()
    setControls(true)
    play.title = "Play again"
    dx_core_snapshot(core, &snapshot)
    updateResult()
    scene.needsDisplay = true
  }
  private func midi(note: Int, velocity: Int, time: Double) {
    if let pad = learning, !running {
      for i in 0..<3 { mappings[i].removeAll { $0 == note } }
      mappings[pad] = [note]
      learning = nil
      io.setMIDIMapping(mappings)
      io.setMIDILearnActive(false)
      UserDefaults.standard.set(mappings, forKey: "drumx.lab.mapping")
      refreshMappingLabels()
      status.stringValue = "Mapped \(padNames[pad]) to note \(note)."
      return
    }
    guard let pad = mappings.firstIndex(where: { $0.contains(note) }) else { return }
    receive(pad: pad, velocity: Double(velocity) / 127, hostTime: time)
  }
  @objc func soundChanged() {
    drumSound = soundToggle.state == .on
    io.setMonitoring(enabled: drumSound)
    UserDefaults.standard.set(drumSound, forKey: "drumx.lab.drumSound")
    window.makeFirstResponder(scene)
  }
  @objc func volumeChanged() {
    io.setMonitorVolume(Float(volumeSlider.doubleValue))
    window.makeFirstResponder(scene)
  }
  func keyboardHit(pad: Int, velocity: Int, hostTime: Double) {
    // AppKit's event timestamp is uptime seconds in the native host clock domain.
    // Keep capture time even if main-thread delivery or sample scheduling was late.
    io.playPad(pad: pad, velocity: velocity)
    receive(pad: pad, velocity: Double(velocity) / 127, hostTime: hostTime)
  }
  func receive(pad: Int, velocity: Double, hostTime: Double) {
    flashes[pad] = DrumxIO.hostNowSeconds()
    let songTime = hostTime - practiceStart - calibrationMS / 1000
    if running || completed, songTime >= -0.125, songTime <= dx_core_duration(core) + 0.125 {
      _ = dx_core_input(core, Int32(pad), songTime, velocity)
      dx_core_snapshot(core, &snapshot)
    }
    scene.needsDisplay = true
  }
  private func updateResult() {
    let s = snapshot.total
    results.stringValue = "\(s.matched) hits · \(s.missed) misses · \(s.extra) extras"
  }
  private func tick() {
    let now = DrumxIO.hostNowSeconds()
    if running {
      let song = now - practiceStart
      dx_core_advance(core, song)
      dx_core_snapshot(core, &snapshot)
      if song > dx_core_duration(core) + 0.15 {
        running = false
        completed = true
        io.stopClick()
        setControls(true)
        play.title = "Play again"
        status.stringValue =
          "Take complete · \(modeNames[mode]) · \(usedLiveFeedback ? "live feedback" : "feedback after phrase"). Play again to retry."
      }
    }
    if now - lastStatusUpdate > 0.12 {
      if showLive || !running {
        updateResult()
      } else {
        results.stringValue = "Feedback after the phrase"
      }
      let phase = running ? (now < practiceStart ? "Count-in" : "Playing") : "Ready"
      scene.setAccessibilityLabel(
        "Practice rail. \(phase). \(modeNames[mode]). \(results.stringValue). Hi-hat A, snare S, kick Space. Shift for a softer hit."
      )
      lastStatusUpdate = now
    }
    scene.needsDisplay = true
  }
}

final class LabAppDelegate: NSObject, NSApplicationDelegate {
  var controller: LabController?
  func applicationDidFinishLaunching(_ notification: Notification) {
    controller = LabController()
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
