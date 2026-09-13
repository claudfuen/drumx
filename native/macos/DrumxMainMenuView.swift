import AppKit

private enum MainMenuInk {
  static let background = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)

  static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                    color: NSColor = paper) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }
}

/// Native controls retain keyboard and accessibility activation. The highlighted
/// menu selection also works when the window routes game-style arrow keys here.
private final class MainMenuAction: NSButton {
  var primary = false
  var drawingScale: CGFloat = 1 { didSet { needsDisplay = true } }
  var subtitle = "" { didSet { needsDisplay = true } }
  var selected = false { didSet { needsDisplay = true } }
  var onNavigate: ((Int) -> Void)?
  var onFocus: (() -> Void)?
  private var hovered = false
  private var hoverTracking: NSTrackingArea?

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { isEnabled }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let tracking = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(tracking)
    hoverTracking = tracking
  }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { onFocus?(); needsDisplay = true }
    return accepted
  }
  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    needsDisplay = true
    return accepted
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 125 { onNavigate?(1); return }
    if event.keyCode == 126 { onNavigate?(-1); return }
    if event.keyCode == 36 || event.keyCode == 76 { performClick(nil); return }
    super.keyDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    // The native button frame grows with the drawing. Only paint coordinates
    // use the authored scale; hit testing and accessibility stay in real points.
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let scale = drawingScale
    (AffineTransform(scale: scale) as NSAffineTransform).concat()
    let drawBounds = NSRect(x: 0, y: 0, width: bounds.width / scale, height: bounds.height / scale)
    let active = hovered || selected || window?.firstResponder === self
    let shape = NSBezierPath(roundedRect: drawBounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
    if primary {
      MainMenuInk.lime.withAlphaComponent(isHighlighted ? 0.76 : active ? 1 : 0.91).setFill()
      shape.fill()
    } else if active {
      MainMenuInk.paper.withAlphaComponent(isHighlighted ? 0.10 : 0.045).setFill()
      shape.fill()
    }
    if selected || window?.firstResponder === self {
      MainMenuInk.lime.withAlphaComponent(primary ? 0.6 : 0.9).setFill()
      NSBezierPath(roundedRect: NSRect(x: 0, y: primary ? 19 : 14, width: 3,
                                      height: drawBounds.height - (primary ? 38 : 28)),
                   xRadius: 1.5, yRadius: 1.5).fill()
      if primary {
        MainMenuInk.lime.withAlphaComponent(0.34).setStroke()
        let focus = NSBezierPath(roundedRect: drawBounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        focus.lineWidth = 1
        focus.stroke()
      }
    }
    let foreground = primary ? MainMenuInk.background : active ? MainMenuInk.paper : MainMenuInk.muted
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    let titleAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: primary ? 24 : 18, weight: primary ? .semibold : .medium),
      .foregroundColor: foreground, .paragraphStyle: paragraph,
    ]
    (title as NSString).draw(in: NSRect(x: 22, y: primary ? 15 : subtitle.isEmpty ? 14 : 6,
                                      width: drawBounds.width - 76, height: 31), withAttributes: titleAttributes)
    if !subtitle.isEmpty {
      (subtitle as NSString).draw(in: NSRect(x: 23, y: primary ? 49 : 31,
                                            width: drawBounds.width - 78, height: 19),
        withAttributes: [.font: NSFont.systemFont(ofSize: primary ? 12 : 11, weight: .medium),
                         .foregroundColor: foreground.withAlphaComponent(primary ? 0.76 : 0.85),
                         .paragraphStyle: paragraph])
    }
    if primary || active {
      let x = drawBounds.width - 29, y = drawBounds.midY
      let arrow = NSBezierPath()
      arrow.move(to: NSPoint(x: x - 11, y: y)); arrow.line(to: NSPoint(x: x + 1, y: y))
      arrow.move(to: NSPoint(x: x - 4, y: y - 5)); arrow.line(to: NSPoint(x: x + 1, y: y))
      arrow.line(to: NSPoint(x: x - 4, y: y + 5))
      arrow.lineWidth = 1.6; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
      foreground.setStroke(); arrow.stroke()
    }
  }
}

/// Original vector percussion study. Static artwork has no timer, fake loading
/// state, or dependency on the transport/rendering clock.
private final class MainMenuDrumArtwork: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    guard bounds.width > 0 && bounds.height > 0 else { return }
    NSGraphicsContext.saveGraphicsState()
    let scale = min(bounds.width / 460, bounds.height / 560)
    var transform = AffineTransform(translationByX: (bounds.width - 460 * scale) / 2,
                                    byY: (bounds.height - 560 * scale) / 2)
    transform.scale(scale)
    (transform as NSAffineTransform).concat()

    let halo = NSBezierPath(ovalIn: NSRect(x: 12, y: 67, width: 440, height: 440))
    NSGradient(starting: MainMenuInk.lime.withAlphaComponent(0.085),
               ending: MainMenuInk.lime.withAlphaComponent(0))?
      .draw(in: halo, relativeCenterPosition: NSPoint(x: 0.2, y: 0))

    // A quiet suggestion of the note highway recedes behind the instrument.
    for fraction in [-1.0, -0.5, 0, 0.5, 1.0] {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: 251 + fraction * 28, y: 43))
      line.line(to: NSPoint(x: 251 + fraction * 188, y: 490))
      MainMenuInk.lime.withAlphaComponent(fraction == 0 ? 0.10 : 0.045).setStroke()
      line.lineWidth = 0.8; line.stroke()
    }
    for (y, width) in [(92.0, 76.0), (129, 105), (179, 142)] {
      let rail = NSBezierPath()
      rail.move(to: NSPoint(x: 251 - width / 2, y: y))
      rail.line(to: NSPoint(x: 251 + width / 2, y: y))
      MainMenuInk.lime.withAlphaComponent(0.08).setStroke()
      rail.lineWidth = 1; rail.stroke()
    }

    let shell = NSBezierPath()
    shell.move(to: NSPoint(x: 54, y: 302))
    shell.curve(to: NSPoint(x: 432, y: 302), controlPoint1: NSPoint(x: 54, y: 180), controlPoint2: NSPoint(x: 432, y: 180))
    shell.line(to: NSPoint(x: 432, y: 351))
    shell.curve(to: NSPoint(x: 54, y: 351), controlPoint1: NSPoint(x: 432, y: 496), controlPoint2: NSPoint(x: 54, y: 496))
    shell.close()
    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.17, alpha: 1),
               ending: MainMenuInk.background)?.draw(in: shell, angle: 90)
    MainMenuInk.paper.withAlphaComponent(0.10).setStroke(); shell.lineWidth = 1; shell.stroke()

    let lowerRim = NSBezierPath(ovalIn: NSRect(x: 54, y: 235, width: 378, height: 235))
    MainMenuInk.paper.withAlphaComponent(0.14).setStroke(); lowerRim.lineWidth = 1.3; lowerRim.stroke()
    let head = NSBezierPath(ovalIn: NSRect(x: 48, y: 183, width: 390, height: 244))
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.24, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.105, blue: 0.10, alpha: 1))?
      .draw(in: head, angle: 62)
    MainMenuInk.lime.withAlphaComponent(0.6).setStroke(); head.lineWidth = 1.8; head.stroke()
    for inset in [7.0, 13.0, 26.0] {
      let ring = NSBezierPath(ovalIn: NSRect(x: 48 + inset, y: 183 + inset * 0.64,
                                            width: 390 - inset * 2, height: 244 - inset * 1.28))
      MainMenuInk.paper.withAlphaComponent(inset == 7 ? 0.30 : 0.07).setStroke()
      ring.lineWidth = 0.8; ring.stroke()
    }
    // Front tension rods give the illustration a recognisable physical shell.
    for angle in stride(from: 0.20, through: Double.pi - 0.19, by: 0.46) {
      let x = 243 + cos(angle) * 184, y = 305 + sin(angle) * 117
      let rod = NSBezierPath()
      rod.move(to: NSPoint(x: x, y: y + 5)); rod.line(to: NSPoint(x: x, y: y + 40))
      rod.lineWidth = 3; rod.lineCapStyle = .round
      MainMenuInk.paper.withAlphaComponent(0.20).setStroke(); rod.stroke()
      MainMenuInk.paper.withAlphaComponent(0.38).setFill()
      NSBezierPath(ovalIn: NSRect(x: x - 3, y: y - 2, width: 6, height: 5)).fill()
    }
    let centerRing = NSBezierPath(ovalIn: NSRect(x: 213, y: 285, width: 60, height: 38))
    MainMenuInk.lime.withAlphaComponent(0.15).setStroke(); centerRing.lineWidth = 0.7; centerRing.stroke()

    func stick(from start: NSPoint, to end: NSPoint, light: Bool) {
      let shadow = NSShadow()
      shadow.shadowOffset = NSSize(width: 2, height: 11); shadow.shadowBlurRadius = 14
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
      NSGraphicsContext.saveGraphicsState(); shadow.set()
      let path = NSBezierPath(); path.move(to: start); path.line(to: end)
      path.lineWidth = 8; path.lineCapStyle = .round
      MainMenuInk.paper.withAlphaComponent(light ? 0.83 : 0.44).setStroke(); path.stroke()
      NSGraphicsContext.restoreGraphicsState()
      let glint = NSBezierPath()
      glint.move(to: NSPoint(x: start.x - 1, y: start.y - 1))
      glint.line(to: NSPoint(x: end.x - 1, y: end.y - 1))
      glint.lineWidth = 1.2; glint.lineCapStyle = .round
      MainMenuInk.paper.withAlphaComponent(0.35).setStroke(); glint.stroke()
    }
    stick(from: NSPoint(x: 114, y: 147), to: NSPoint(x: 319, y: 381), light: false)
    stick(from: NSPoint(x: 385, y: 124), to: NSPoint(x: 161, y: 365), light: true)

    let caption = "LISTEN   /   PLAY   /   REMEMBER"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 9, weight: .medium), .kern: 2.0,
      .foregroundColor: MainMenuInk.muted.withAlphaComponent(0.7),
    ]
    let size = (caption as NSString).size(withAttributes: attributes)
    (caption as NSString).draw(at: NSPoint(x: 243 - size.width / 2, y: 514), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
  }
}

/// The title menu is intentionally separate from the course browser and player.
/// Root owns navigation, transport, profile selection, and persistence.
final class DrumxMainMenuView: NSView {
  var onContinue: (() -> Void)?
  var onExplore: (() -> Void)?
  var onSongs: (() -> Void)?
  var onSettings: (() -> Void)?

  private let content = NSView()
  private let headline = NSTextField(wrappingLabelWithString: "Find your\nrhythm.")
  private let invitation = MainMenuInk.label("Build a rhythm that stays with you.", size: 16,
                                              color: MainMenuInk.muted)
  private let artwork = MainMenuDrumArtwork()
  private let playerLabel = MainMenuInk.label("YOUR PRACTICE", size: 11, weight: .medium, color: MainMenuInk.muted)
  private let chapterLabel = MainMenuInk.label("FOUNDATIONS", size: 10, weight: .medium, color: MainMenuInk.lime)
  private let progressLabel = MainMenuInk.label("", size: 11, color: MainMenuInk.muted)
  private let continueButton = MainMenuAction(title: "Continue", target: nil, action: nil)
  private let exploreButton = MainMenuAction(title: "Learn", target: nil, action: nil)
  private let songsButton = MainMenuAction(title: "Songs", target: nil, action: nil)
  private let settingsButton = MainMenuAction(title: "Settings", target: nil, action: nil)
  private var selectedIndex = 0
  private var actions: [MainMenuAction] { [continueButton, exploreButton, songsButton, settingsButton] }

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(content)
    headline.maximumNumberOfLines = 2
    headline.lineBreakMode = .byWordWrapping
    // Wrapping labels default to selectable. This title must never enter the
    // field editor, which would replace its display typography on a click.
    headline.isEditable = false
    headline.isSelectable = false
    artwork.setAccessibilityElement(false)
    for view in [playerLabel, headline, invitation, chapterLabel, continueButton,
                 exploreButton, songsButton, settingsButton, progressLabel, artwork] {
      content.addSubview(view)
    }
    continueButton.primary = true
    exploreButton.subtitle = "Explore foundations · \(DrumxCourse.lessons.count) lessons"
    songsButton.subtitle = "Your song library · Full-kit drums"
    songsButton.target = self; songsButton.action = #selector(openSongs)
    continueButton.target = self; continueButton.action = #selector(continuePractice)
    exploreButton.target = self; exploreButton.action = #selector(exploreFoundations)
    settingsButton.target = self; settingsButton.action = #selector(openSettings)
    for (index, button) in actions.enumerated() {
      button.isBordered = false; button.focusRingType = .none
      button.setAccessibilityRole(.button)
      button.onNavigate = { [weak self] offset in self?.moveSelection(offset) }
      button.onFocus = { [weak self] in self?.select(index) }
    }
    continueButton.nextKeyView = exploreButton
    exploreButton.nextKeyView = songsButton
    songsButton.nextKeyView = settingsButton
    settingsButton.nextKeyView = continueButton
    exploreButton.setAccessibilityLabel("Learn. Explore foundations, \(DrumxCourse.lessons.count) drum lessons.")
    songsButton.setAccessibilityLabel("Songs. Browse imported songs and choose your drum difficulty.")
    settingsButton.setAccessibilityLabel("Settings. Configure your kit, sound, and player preferences.")
    select(0)
  }

  required init?(coder: NSCoder) { nil }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    guard bounds.width > 0, bounds.height > 0 else { return }
    let margin = max(24, min(120, bounds.width * 0.045))
    let usableWidth = max(1, bounds.width - margin * 2)
    let usableHeight = max(1, bounds.height - 32)
    let scale = min(1.55, max(0.85, min(usableWidth / 920, usableHeight / 580)))
    let width = min(1920, usableWidth, max(920 * scale, bounds.width * 0.86))
    let leftWidth = 424 * scale
    let artWidth = min(860, width - leftWidth - 32 * scale, usableHeight * 0.91 * 460 / 560)
    let artHeight = artWidth * 560 / 460
    let height = max(580 * scale, artHeight)
    content.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                           width: width, height: height)
    let textBottom = (height - 580 * scale) / 2
    func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
      view.frame = NSRect(x: x * scale, y: textBottom + y * scale,
                          width: w * scale, height: h * scale)
      view.needsDisplay = true
    }
    place(playerLabel, 4, 543, 416, 20)
    place(headline, 0, 366, 432, 164)
    place(invitation, 4, 333, 422, 26)
    place(chapterLabel, 4, 276, 416, 20)
    place(continueButton, 0, 196, 424, 80)
    place(exploreButton, 0, 140, 424, 50)
    place(songsButton, 0, 84, 424, 50)
    place(settingsButton, 0, 28, 424, 50)
    place(progressLabel, 4, 0, 424, 20)
    artwork.frame = NSRect(x: width - artWidth, y: (height - artHeight) / 2,
                           width: artWidth, height: artHeight)
    artwork.needsDisplay = true
    playerLabel.font = .systemFont(ofSize: 11 * scale, weight: .medium)
    chapterLabel.font = .systemFont(ofSize: 10 * scale, weight: .medium)
    progressLabel.font = .systemFont(ofSize: 11 * scale)
    invitation.font = .systemFont(ofSize: 16 * scale)
    let headlineFont = NSFont.systemFont(ofSize: 69 * scale, weight: .semibold)
    headline.font = headlineFont
    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = -4 * scale
    headline.attributedStringValue = NSAttributedString(string: "Find your\nrhythm.", attributes: [
      .font: headlineFont,
      .foregroundColor: MainMenuInk.paper, .kern: -2.8 * scale, .paragraphStyle: paragraph,
    ])
    for button in actions { button.drawingScale = scale }
  }

  func update(lesson: DrumxLessonDefinition, player: String, unlocked: Int, cleared: Int) {
    playerLabel.stringValue = "\(player.uppercased())  /  YOUR PRACTICE"
    let chapter = DrumxCourse.chapterTitles.indices.contains(lesson.chapter)
      ? DrumxCourse.chapterTitles[lesson.chapter] : "Foundations"
    chapterLabel.stringValue = "CHAPTER \(lesson.chapter + 1)  /  \(chapter.uppercased())"
    continueButton.subtitle = lesson.title
    continueButton.setAccessibilityLabel("Continue \(lesson.title). \(chapter). \(lesson.subtitle)")
    let total = DrumxCourse.lessons.count
    let available = min(total, max(0, unlocked)), completed = min(total, max(0, cleared))
    progressLabel.stringValue = "\(completed) / \(total) lessons cleared   ·   \(available) available"
    // A refresh must not highlight Continue while a different native button
    // still owns Return. Otherwise, a newly opened menu begins at Continue.
    select(actions.firstIndex { window?.firstResponder === $0 } ?? 0)
  }

  func moveSelection(_ offset: Int) {
    let count = actions.count
    select((selectedIndex + offset % count + count) % count)
    window?.makeFirstResponder(actions[selectedIndex])
  }

  func activateSelection() { actions[selectedIndex].performClick(nil) }

  private func select(_ index: Int) {
    selectedIndex = index
    for (offset, button) in actions.enumerated() { button.selected = offset == index }
  }
  @objc private func continuePractice() { select(0); onContinue?() }
  @objc private func exploreFoundations() { select(1); onExplore?() }
  @objc private func openSongs() { select(2); onSongs?() }
  @objc private func openSettings() { select(3); onSettings?() }
}
