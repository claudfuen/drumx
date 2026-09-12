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
  private let caption = NSTextField(labelWithString: "Get comfortable. Then get playing.")
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    heading.textColor = SetupInk.paper; caption.textColor = SetupInk.muted
    addSubview(heading); addSubview(caption)
  }
  required init?(coder: NSCoder) { nil }
  func install(tabs: [LessonButton], panels: [NSView]) {
    self.tabs = tabs; self.panels = panels
    (tabs as [NSView] + panels).forEach { addSubview($0) }
    needsLayout = true
  }
  override func layout() {
    super.layout()
    let width = min(1500, max(800, bounds.width - 88))
    let x = (bounds.width - width) / 2
    let scale = min(1.3, max(1, (bounds.height - 40) / 660))
    let totalHeight = min(bounds.height - 24, 740 * scale)
    let top = max(12, (bounds.height - totalHeight) / 2)
    heading.font = .systemFont(ofSize: 36 * scale, weight: .bold)
    caption.font = .systemFont(ofSize: 14 * scale)
    heading.frame = NSRect(x: x, y: top, width: width / 2, height: 50 * scale)
    caption.frame = NSRect(x: x + width / 2, y: top + 21 * scale, width: width / 2, height: 24 * scale)
    caption.alignment = .right
    let tabY = top + 65 * scale, tabHeight = 48 * scale
    for (index, tab) in tabs.enumerated() {
      tab.frame = NSRect(x: x + CGFloat(index) * (width + 12) / 4, y: tabY,
        width: (width - 36) / 4, height: tabHeight)
    }
    let panelRect = NSRect(x: x, y: tabY + tabHeight + 22 * scale, width: width,
      height: max(360, totalHeight - 140 * scale))
    panels.forEach { $0.frame = panelRect }
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

private final class KitPad: NSButton {
  var pad = 0
  var selected = false
  var checked = false
  var pulsing = false
  var learning = false
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
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
    color.withAlphaComponent(pulsing ? 0.26 : selected ? 0.11 : 0.045).setFill(); shape.fill()
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
  var lastPad: Int?
  var lastVelocity = 0
  var lastInput = "Strike a pad to see its signal."
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
  }
  func showHit(pad: Int?, velocity: Int, description: String) {
    lastPad = pad; lastVelocity = velocity; lastInput = description
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
    pads.forEach { $0.pulsing = false; $0.needsDisplay = true }
    needsDisplay = true
  }
  private func refreshPads() {
    for pad in pads {
      pad.selected = pad.pad == selectedPad; pad.checked = confirmed.contains(pad.pad)
      pad.learning = pad.pad == learningPad
      pad.setAccessibilityValue(pad.learning ? "Waiting for MIDI mapping" : pad.checked ? "Input received" : "Waiting for input")
      pad.needsDisplay = true
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    SetupInk.text("YOUR FOUNDATION KIT", in: NSRect(x: 24, y: 20, width: bounds.width - 48, height: 18), size: 11, color: SetupInk.muted, weight: .semibold)
    SetupInk.text(lastInput, in: NSRect(x: 24, y: bounds.height - 37, width: bounds.width - 48, height: 18), size: 12,
      color: lastPad == nil && lastVelocity > 0 ? .systemOrange : SetupInk.paper)
    let track = NSRect(x: 24, y: bounds.height - 14, width: bounds.width - 48, height: 3)
    NSColor.white.withAlphaComponent(0.06).setFill(); NSBezierPath(rect: track).fill()
    var signal = track; signal.size.width *= CGFloat(lastVelocity) / 127
    (lastPad.map { SetupInk.pads[$0] } ?? SetupInk.muted).setFill(); NSBezierPath(rect: signal).fill()
  }
}
