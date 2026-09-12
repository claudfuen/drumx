import AppKit

private enum DrumxControlInk {
  static let ink = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
  static let surface = NSColor(calibratedRed: 0.085, green: 0.108, blue: 0.114, alpha: 1)
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)

  static func focused(_ control: NSControl) -> Bool {
    if control.window?.firstResponder === control { return true }
    guard let field = control as? NSTextField, let editor = field.currentEditor() else { return false }
    return control.window?.firstResponder === editor
  }

  static func focus(in rect: NSRect, control: NSControl, radius: CGFloat = 7) {
    guard control.isEnabled, focused(control) else { return }
    lime.withAlphaComponent(0.9).setStroke()
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
                            xRadius: radius, yRadius: radius)
    path.lineWidth = 1.5
    path.stroke()
  }
}

/// Hover changes only decoration. AppKit continues to own mouse tracking,
/// keyboard edits, accessibility values, target/action, and menu selection.
private final class DrumxControlHover: NSObject {
  private weak var control: NSControl?
  private var tracking: NSTrackingArea?
  private(set) var isInside = false

  init(_ control: NSControl) { self.control = control }

  func update() {
    guard let control else { return }
    if let tracking { control.removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    control.addTrackingArea(area)
    tracking = area
  }

  @objc func mouseEntered(with event: NSEvent) { isInside = true; control?.needsDisplay = true }
  @objc func mouseExited(with event: NSEvent) { isInside = false; control?.needsDisplay = true }
}

private final class DrumxSliderCell: NSSliderCell {
  override func drawBar(inside rect: NSRect, flipped: Bool) {
    guard sliderType == .linear else { super.drawBar(inside: rect, flipped: flipped); return }
    let track: NSRect
    if isVertical {
      track = NSRect(x: rect.midX - 2, y: rect.minY, width: 4, height: rect.height)
    } else {
      track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
    }
    DrumxControlInk.paper.withAlphaComponent(isEnabled ? 0.17 : 0.07).setFill()
    NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
    let range = maxValue - minValue
    let fraction = range.isFinite && range > 0 && doubleValue.isFinite
      ? min(1, max(0, (doubleValue - minValue) / range)) : 0
    var fill = track
    if isVertical {
      fill.size.height *= fraction
      if flipped { fill.origin.y = track.maxY - fill.height }
    } else {
      fill.size.width *= fraction
      if controlView?.userInterfaceLayoutDirection == .rightToLeft { fill.origin.x = track.maxX - fill.width }
    }
    DrumxControlInk.lime.withAlphaComponent(isEnabled ? 0.82 : 0.22).setFill()
    NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
  }

  override func drawKnob(_ knobRect: NSRect) {
    guard sliderType == .linear else { super.drawKnob(knobRect); return }
    let hovered = (controlView as? DrumxSlider)?.isHovered == true
    let diameter: CGFloat = isHighlighted && isEnabled ? 17 : 16
    let knob = NSRect(x: knobRect.midX - diameter / 2, y: knobRect.midY - diameter / 2,
                      width: diameter, height: diameter)
    if (hovered || isHighlighted) && isEnabled {
      DrumxControlInk.lime.withAlphaComponent(isHighlighted ? 0.17 : 0.10).setFill()
      NSBezierPath(ovalIn: knob.insetBy(dx: -4, dy: -4)).fill()
    }
    (isEnabled ? DrumxControlInk.lime : DrumxControlInk.muted.withAlphaComponent(0.4)).setFill()
    NSBezierPath(ovalIn: knob).fill()
    DrumxControlInk.ink.withAlphaComponent(0.5).setStroke()
    let border = NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5))
    border.lineWidth = 1; border.stroke()
  }
}

/// Drop-in NSSlider API, including init(value:minValue:maxValue:target:action:).
final class DrumxSlider: NSSlider {
  override class var cellClass: AnyClass? {
    get { DrumxSliderCell.self }
    set { }
  }
  private lazy var hover = DrumxControlHover(self)
  fileprivate var isHovered: Bool { hover.isInside }

  private weak var valueLabel: NSTextField?
  private var valueFormatter: ((Double) -> String)?

  /// Display units without replacing AppKit's tracking or sending extra actions.
  func attachValueLabel(_ label: NSTextField, formatter: @escaping (Double) -> String) {
    valueLabel = label; valueFormatter = formatter; refreshValueDescription()
  }
  private func refreshValueDescription() {
    guard let valueFormatter else { return }
    let value = valueFormatter(doubleValue)
    valueLabel?.stringValue = value
    setAccessibilityValueDescription(value)
  }
  override var doubleValue: Double {
    get { super.doubleValue }
    set { super.doubleValue = newValue; refreshValueDescription() }
  }
  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    refreshValueDescription()
    return super.sendAction(action, to: target)
  }

  override init(frame: NSRect) { super.init(frame: frame); focusRingType = .none }
  required init?(coder: NSCoder) { super.init(coder: coder); focusRingType = .none }
  override func updateTrackingAreas() { super.updateTrackingAreas(); hover.update() }
  override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); needsDisplay = true; return accepted }
  override func resignFirstResponder() -> Bool { let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    DrumxControlInk.focus(in: bounds, control: self)
  }
}

/// A native switch-style NSButton with a branded track and a visible checkmark.
/// State remains .off/.on/.mixed; AppKit provides toggle actions and VoiceOver.
final class DrumxToggle: NSButton {
  private lazy var hover = DrumxControlHover(self)

  override init(frame: NSRect) { super.init(frame: frame); configure() }
  required init?(coder: NSCoder) { super.init(coder: coder); configure() }
  private func configure() { setButtonType(.switch); isBordered = false; focusRingType = .none }
  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize {
    let textWidth = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]).width
    return NSSize(width: ceil(textWidth) + 54, height: 30)
  }
  override func updateTrackingAreas() { super.updateTrackingAreas(); hover.update() }
  override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); needsDisplay = true; return accepted }
  override func resignFirstResponder() -> Bool { let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted }
  override func resetCursorRects() {
    if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
  }

  override func draw(_ dirtyRect: NSRect) {
    let active = state != .off
    let alpha: CGFloat = isEnabled ? 1 : 0.4
    let track = NSRect(x: 4, y: bounds.midY - 10, width: 36, height: 20)
    let path = NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10)
    (active ? DrumxControlInk.lime.withAlphaComponent(alpha * (isHighlighted ? 0.65 : 0.9))
      : DrumxControlInk.paper.withAlphaComponent(alpha * (hover.isInside ? 0.22 : 0.13))).setFill()
    path.fill()
    DrumxControlInk.paper.withAlphaComponent(alpha * 0.17).setStroke(); path.lineWidth = 0.8; path.stroke()
    let centerX = state == .mixed ? track.midX : state == .on ? track.maxX - 10 : track.minX + 10
    let knob = NSRect(x: centerX - 7, y: track.midY - 7, width: 14, height: 14)
    (active ? DrumxControlInk.ink : DrumxControlInk.paper).withAlphaComponent(alpha).setFill()
    NSBezierPath(ovalIn: knob).fill()
    if active {
      let mark = NSBezierPath()
      if state == .mixed {
        mark.move(to: NSPoint(x: centerX - 3, y: track.midY))
        mark.line(to: NSPoint(x: centerX + 3, y: track.midY))
      } else {
        mark.move(to: NSPoint(x: centerX - 3, y: track.midY))
        mark.line(to: NSPoint(x: centerX - 1, y: track.midY + 2))
        mark.line(to: NSPoint(x: centerX + 3, y: track.midY - 2))
      }
      mark.lineWidth = 1.3; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
      DrumxControlInk.lime.withAlphaComponent(alpha).setStroke(); mark.stroke()
    }
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let textFont = font ?? .systemFont(ofSize: 13)
    let textHeight = textFont.ascender - textFont.descender + textFont.leading + 2
    (title as NSString).draw(in: NSRect(x: 49, y: bounds.midY - textHeight / 2,
                                      width: max(0, bounds.width - 53), height: textHeight),
      withAttributes: [.font: textFont, .foregroundColor: DrumxControlInk.paper.withAlphaComponent(alpha),
                       .paragraphStyle: paragraph])
    DrumxControlInk.focus(in: bounds, control: self)
  }
}

private final class DrumxPopUpCell: NSPopUpButtonCell {
  override func draw(withFrame frame: NSRect, in controlView: NSView) {
    let button = controlView as? DrumxPopUpButton
    let alpha: CGFloat = isEnabled ? 1 : 0.42
    let rect = frame.insetBy(dx: 1, dy: 1)
    let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
    (isHighlighted ? DrumxControlInk.paper.withAlphaComponent(0.11) : DrumxControlInk.surface).setFill()
    path.fill()
    let engaged = isHighlighted || button?.isHovered == true
    (engaged ? DrumxControlInk.lime.withAlphaComponent(alpha * 0.55)
      : DrumxControlInk.paper.withAlphaComponent(alpha * 0.16)).setStroke()
    path.lineWidth = 1; path.stroke()
    let value = (button?.pullsDown == true ? title : button?.titleOfSelectedItem ?? title) ?? ""
    let textFont = button?.font ?? font ?? .systemFont(ofSize: 13)
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let textHeight = textFont.ascender - textFont.descender + textFont.leading + 2
    (value as NSString).draw(in: NSRect(x: rect.minX + 12, y: rect.midY - textHeight / 2,
                                      width: max(0, rect.width - 40), height: textHeight),
      withAttributes: [.font: textFont, .foregroundColor: DrumxControlInk.paper.withAlphaComponent(alpha),
                       .paragraphStyle: paragraph])
    let x = rect.maxX - 16, y = rect.midY
    let chevron = NSBezierPath()
    let direction: CGFloat = controlView.isFlipped ? 1 : -1
    chevron.move(to: NSPoint(x: x - 3.5, y: y - direction * 1.5))
    chevron.line(to: NSPoint(x: x, y: y + direction * 2))
    chevron.line(to: NSPoint(x: x + 3.5, y: y - direction * 1.5))
    chevron.lineWidth = 1.4; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
    DrumxControlInk.lime.withAlphaComponent(alpha * 0.85).setStroke(); chevron.stroke()
    if let button { DrumxControlInk.focus(in: frame, control: button) }
  }
}

/// Keeps the real NSPopUpButton menu, represented objects, keyboard selection,
/// and accessibility. Only its closed appearance is branded.
final class DrumxPopUpButton: NSPopUpButton {
  override class var cellClass: AnyClass? {
    get { DrumxPopUpCell.self }
    set { }
  }
  private lazy var hover = DrumxControlHover(self)
  fileprivate var isHovered: Bool { hover.isInside }

  override init(frame: NSRect) { super.init(frame: frame); focusRingType = .none }
  override init(frame: NSRect, pullsDown flag: Bool) { super.init(frame: frame, pullsDown: flag); focusRingType = .none }
  required init?(coder: NSCoder) { super.init(coder: coder); focusRingType = .none }
  override var intrinsicContentSize: NSSize {
    let native = super.intrinsicContentSize
    return NSSize(width: max(76, native.width + 14), height: max(32, native.height))
  }
  override func updateTrackingAreas() { super.updateTrackingAreas(); hover.update() }
  override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); needsDisplay = true; return accepted }
  override func resignFirstResponder() -> Bool { let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted }
  override func resetCursorRects() {
    if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
  }
}

/// A padded editor using the same surface and focus treatment as the other
/// controls. AppKit still owns selection, editing, keyboard commands and actions.
final class DrumxTextFieldCell: NSTextFieldCell {
  override init(textCell string: String) {
    super.init(textCell: string)
    isBezeled = false; isBordered = false; drawsBackground = false
    isEditable = true; isSelectable = true; usesSingleLineMode = true
    font = .monospacedSystemFont(ofSize: 14, weight: .medium)
    textColor = DrumxControlInk.paper; alignment = .right
  }
  required init(coder: NSCoder) { super.init(coder: coder) }

  private func contentRect(_ frame: NSRect) -> NSRect {
    let height = ceil((font?.ascender ?? 13) - (font?.descender ?? -3)) + 2
    return NSRect(x: frame.minX + 12, y: frame.midY - height / 2,
      width: max(0, frame.width - 24), height: height)
  }
  override func draw(withFrame frame: NSRect, in controlView: NSView) {
    let surface = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
    DrumxControlInk.surface.withAlphaComponent(isEnabled ? 1 : 0.45).setFill(); surface.fill()
    DrumxControlInk.paper.withAlphaComponent(isEnabled ? 0.18 : 0.07).setStroke(); surface.stroke()
    super.drawInterior(withFrame: contentRect(frame), in: controlView)
    if let control = controlView as? NSControl { DrumxControlInk.focus(in: frame, control: control, radius: 8) }
  }
  override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                     delegate: Any?, event: NSEvent?) {
    super.edit(withFrame: contentRect(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    controlView.needsDisplay = true
  }
  override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, start selStart: Int, length selLength: Int) {
    super.select(withFrame: contentRect(rect), in: controlView, editor: textObj,
      delegate: delegate, start: selStart, length: selLength)
    controlView.needsDisplay = true
  }
  override func endEditing(_ textObj: NSText) {
    super.endEditing(textObj); controlView?.needsDisplay = true
  }
}
