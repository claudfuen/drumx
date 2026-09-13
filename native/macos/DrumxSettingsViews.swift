import AppKit

private enum SetupInk {
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)
  static let pads = [NSColor(calibratedRed: 0.54, green: 0.792, blue: 0.808, alpha: 1),
    NSColor(calibratedRed: 0.807, green: 0.917, blue: 0.578, alpha: 1),
    NSColor(calibratedRed: 0.865, green: 0.683, blue: 0.442, alpha: 1)]
  static func text(_ value: String, in rect: NSRect, size: CGFloat, color: NSColor = paper,
                   weight: NSFont.Weight = .medium, center: Bool = false) {
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
    style.alignment = center ? .center : .left
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color, .paragraphStyle: style])
  }
}

/// Uses real view frames throughout, so pointer and accessibility geometry follow resize.
final class DrumxSettingsPage: NSView {
  var tabs: [LessonButton] = []
  var panels: [NSView] = []
  private let heading = NSTextField(labelWithString: "Settings")
  private let viewport = NSScrollView()
  private let content = NSStackView()
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    heading.textColor = SetupInk.paper
    viewport.drawsBackground = false; viewport.borderType = .noBorder
    viewport.hasVerticalScroller = true; viewport.autohidesScrollers = true
    viewport.scrollerStyle = .overlay
    content.orientation = .vertical; content.alignment = .leading
    content.spacing = 0; content.detachesHiddenViews = true
    viewport.documentView = content
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: viewport.contentView.leadingAnchor),
      content.topAnchor.constraint(equalTo: viewport.contentView.topAnchor),
      content.widthAnchor.constraint(equalTo: viewport.contentView.widthAnchor),
      content.heightAnchor.constraint(greaterThanOrEqualTo: viewport.contentView.heightAnchor),
    ])
    addSubview(heading); addSubview(viewport)
  }
  required init?(coder: NSCoder) { nil }
  func install(tabs: [LessonButton], panels: [NSView]) {
    self.tabs.forEach { $0.removeFromSuperview() }
    self.panels.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
    self.tabs = tabs; self.panels = panels
    tabs.forEach { addSubview($0) }
    for panel in panels {
      content.addArrangedSubview(panel)
      panel.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }
    needsLayout = true
  }
  func revealSelectedSection() {
    needsLayout = true; needsDisplay = true
    viewport.contentView.scroll(to: .zero)
    viewport.reflectScrolledClipView(viewport.contentView)
  }
  override func layout() {
    super.layout()
    let width = min(1120, max(0, bounds.width - 88))
    let x = (bounds.width - width) / 2
    let top = min(44, max(24, bounds.height * 0.045))
    heading.font = .systemFont(ofSize: 36, weight: .bold)
    heading.frame = NSRect(x: x, y: top, width: width, height: 48)
    let tabY = top + 62, tabHeight: CGFloat = 48
    let gap: CGFloat = 16
    let tabWidth = min(136, max(0, (width - gap * CGFloat(max(0, tabs.count - 1))) / CGFloat(max(1, tabs.count))))
    for (index, tab) in tabs.enumerated() {
      tab.frame = NSRect(x: x + CGFloat(index) * (tabWidth + gap), y: tabY,
        width: tabWidth, height: tabHeight)
    }
    let panelY = tabY + tabHeight + 32
    viewport.frame = NSRect(x: x, y: panelY, width: width,
      height: max(0, bounds.height - panelY - 28))
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let first = tabs.first else { return }
    let y = first.frame.maxY + 2
    SetupInk.paper.withAlphaComponent(0.09).setFill()
    NSBezierPath(rect: NSRect(x: first.frame.minX, y: y, width: viewport.frame.width, height: 1)).fill()
    for tab in tabs where tab.state == .on {
      SetupInk.lime.setFill()
      NSBezierPath(rect: NSRect(x: tab.frame.minX + 14, y: y - 1, width: max(0, tab.frame.width - 28), height: 2)).fill()
    }
  }
}

final class DrumxSettingsSurface: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true; layer?.cornerRadius = 18
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
    layer?.borderWidth = 1; layer?.borderColor = NSColor.white.withAlphaComponent(0.065).cgColor
  }
  required init?(coder: NSCoder) { nil }
}

final class DrumxSettingsRowSurface: NSView {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    SetupInk.paper.withAlphaComponent(0.085).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: max(0, bounds.height - 1), width: bounds.width, height: 1)).fill()
  }
}

private final class KitPad: NSButton {
  var pad = 0
  var selected = false
  var checked = false
  var pulsing = false
  var learning = false
  private var hovered = false
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { isEnabled }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
  override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
  override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
  override func draw(_ dirtyRect: NSRect) {
    let color = SetupInk.pads[pad]
    let disc = NSRect(x: 12, y: 10, width: bounds.width - 24, height: bounds.height - 50)
    let shape = NSBezierPath(ovalIn: disc)
    if pulsing {
      color.withAlphaComponent(0.14).setFill()
      NSBezierPath(ovalIn: disc.insetBy(dx: -8, dy: -8)).fill()
    }
    color.withAlphaComponent(pulsing ? 0.26 : selected ? 0.14 : hovered ? 0.09 : 0.045).setFill(); shape.fill()
    color.withAlphaComponent(selected || pulsing || learning ? 0.95 : 0.3).setStroke()
    shape.lineWidth = selected || window?.firstResponder === self ? 2 : 1; shape.stroke()
    for fraction in pad == 0 ? [0.12, 0.22, 0.34] : [0.07] {
      let ring = NSBezierPath(ovalIn: disc.insetBy(dx: disc.width * fraction, dy: disc.height * fraction))
      color.withAlphaComponent(0.18).setStroke(); ring.lineWidth = 1; ring.stroke()
    }
    if pad == 0 {
      color.withAlphaComponent(0.6).setFill()
      NSBezierPath(ovalIn: NSRect(x: disc.midX - 4, y: disc.midY - 4, width: 8, height: 8)).fill()
    } else if pad == 2 {
      let pedal = NSBezierPath(roundedRect: NSRect(x: disc.midX - 10, y: disc.midY - 16, width: 20, height: 32), xRadius: 6, yRadius: 6)
      color.withAlphaComponent(0.17).setFill(); pedal.fill()
    }
    if selected {
      SetupInk.text("EDITING", in: NSRect(x: disc.minX, y: disc.maxY - 16, width: disc.width, height: 13),
        size: 8, color: color, weight: .bold, center: true)
    }
    if window?.firstResponder === self {
      SetupInk.paper.withAlphaComponent(0.85).setStroke()
      let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
      focus.lineWidth = 1.5; focus.stroke()
    }
    SetupInk.text(["HI-HAT", "SNARE", "KICK"][pad],
      in: NSRect(x: 0, y: bounds.height - 35, width: bounds.width, height: 19), size: 12, color: color, weight: .semibold, center: true)
    SetupInk.text(learning ? "Strike it to add a note" : checked ? "Input received ✓" : "Waiting for a strike",
      in: NSRect(x: 0, y: bounds.height - 16, width: bounds.width, height: 17), size: 10,
      color: learning ? SetupInk.lime : SetupInk.muted, center: true)
  }
}

/// A setup diagram, never another timing destination. Only the three supported
/// foundation surfaces appear; pad colours match the practice rail.
final class DrumxKitCheckView: NSView {
  var onSelect: ((Int) -> Void)?
  var selectedPad = 1 { didSet { refreshPads() } }
  var confirmed: Set<Int> = [] { didSet { refreshPads() } }
  var learningPad: Int? { didSet { refreshPads() } }
  private(set) var lastPad: Int?
  private(set) var lastVelocity = 0
  private(set) var lastInput = "Strike a pad to see its signal."
  private let signalLabel = NSTextField(labelWithString: "Strike a pad to see its signal.")
  private var pads: [KitPad] = []
  private var pulseTimer: Timer?
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    for index in 0..<3 {
      let pad = KitPad(title: ["Hi-hat", "Snare", "Kick"][index], target: self, action: #selector(selectPad(_:)))
      pad.pad = index; pad.tag = index; pad.isBordered = false; pad.focusRingType = .none
      pad.setAccessibilityLabel("Select \(pad.title) mapping")
      pads.append(pad); addSubview(pad)
    }
    signalLabel.font = .systemFont(ofSize: 12)
    signalLabel.textColor = SetupInk.paper
    signalLabel.lineBreakMode = .byTruncatingMiddle
    signalLabel.setAccessibilityLabel("Latest kit signal")
    addSubview(signalLabel)
    refreshPads()
  }
  required init?(coder: NSCoder) { nil }
  @objc private func selectPad(_ sender: NSButton) { onSelect?(sender.tag) }
  override func layout() {
    super.layout()
    let size = min(175, bounds.width * 0.35, max(100, (bounds.height - 80) * 0.43))
    pads[0].frame = NSRect(x: bounds.width * 0.11, y: 49, width: size, height: size * 0.88)
    pads[1].frame = NSRect(x: bounds.width * 0.53, y: 89, width: size, height: size)
    pads[2].frame = NSRect(x: bounds.width * 0.33, y: bounds.height - size * 0.8 - 60, width: size * 0.8, height: size * 0.8)
    signalLabel.frame = NSRect(x: 24, y: bounds.height - 37, width: max(0, bounds.width - 48), height: 18)
  }
  func showHit(pad: Int?, velocity: Int, description: String) {
    let pad = pad.flatMap { (0..<3).contains($0) ? $0 : nil }
    lastPad = pad; lastVelocity = min(127, max(0, velocity)); lastInput = description
    signalLabel.stringValue = description
    signalLabel.textColor = pad == nil && lastVelocity > 0 ? .systemOrange : SetupInk.paper
    signalLabel.setAccessibilityLabel("Latest kit signal. Velocity \(lastVelocity) of 127.")
    signalLabel.toolTip = description
    pulseTimer?.invalidate()
    for item in pads { item.pulsing = item.pad == pad; item.needsDisplay = true }
    needsDisplay = true
    pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
      self?.pads.forEach { $0.pulsing = false; $0.needsDisplay = true }
    }
  }
  func clearSignal() {
    pulseTimer?.invalidate(); pulseTimer = nil
    lastPad = nil; lastVelocity = 0; lastInput = "Strike a pad to see its signal."
    signalLabel.stringValue = lastInput; signalLabel.textColor = SetupInk.paper
    signalLabel.setAccessibilityLabel("Latest kit signal"); signalLabel.toolTip = nil
    pads.forEach { $0.pulsing = false; $0.needsDisplay = true }
    needsDisplay = true
  }
  private func refreshPads() {
    for pad in pads {
      pad.selected = pad.pad == selectedPad; pad.checked = confirmed.contains(pad.pad)
      pad.learning = pad.pad == learningPad
      pad.setAccessibilityValue((pad.selected ? "Selected. " : "") + (pad.learning ? "Waiting for MIDI mapping" : pad.checked ? "Input received" : "Waiting for input"))
      pad.needsDisplay = true
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    SetupInk.text("FOUNDATION KIT", in: NSRect(x: 24, y: 20, width: bounds.width - 48, height: 18), size: 11, color: SetupInk.muted, weight: .semibold)
    let track = NSRect(x: 24, y: bounds.height - 14, width: bounds.width - 48, height: 3)
    NSColor.white.withAlphaComponent(0.06).setFill(); NSBezierPath(rect: track).fill()
    var signal = track; signal.size.width *= CGFloat(lastVelocity) / 127
    (lastPad.map { SetupInk.pads[$0] } ?? SetupInk.muted).setFill(); NSBezierPath(rect: signal).fill()
  }
}
