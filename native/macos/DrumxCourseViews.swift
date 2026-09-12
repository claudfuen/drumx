import AppKit

private enum CourseInk {
  static let ink = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)
  static let chapterColors = [lime,
    NSColor(calibratedRed: 0.49, green: 0.79, blue: 0.77, alpha: 1),
    NSColor(calibratedRed: 0.77, green: 0.70, blue: 0.93, alpha: 1)]
  static func label(_ text: String, size: CGFloat, color: NSColor = paper,
                    weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
  }
  static func text(_ value: String, in rect: NSRect, size: CGFloat,
                   color: NSColor = paper, weight: NSFont.Weight = .regular,
                   alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.alignment = alignment
    (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                   .foregroundColor: color, .paragraphStyle: paragraph])
  }
  static func line(_ points: [NSPoint], color: NSColor, width: CGFloat = 1) {
    guard let first = points.first else { return }
    let path = NSBezierPath(); path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
    color.setStroke(); path.stroke()
  }
  static func circle(_ rect: NSRect, color: NSColor, filled: Bool = true) {
    let path = NSBezierPath(ovalIn: rect)
    if filled { color.setFill(); path.fill() } else { color.setStroke(); path.lineWidth = 1.3; path.stroke() }
  }
}

/// Hover and keyboard focus belong to the whole card, never an undisclosed action.
private class JourneyCardButton: NSButton {
  private var tracking: NSTrackingArea?
  private(set) var hovered = false
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { isEnabled }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                             owner: self, userInfo: nil)
    addTrackingArea(area); tracking = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func resetCursorRects() {
    if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
  }
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder(); needsDisplay = true; return result
  }
  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder(); needsDisplay = true; return result
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76 { performClick(nil) }
    else { super.keyDown(with: event) }
  }
  func surface(selected: Bool, accent: NSColor, radius: CGFloat = 18) {
    let rect = bounds.insetBy(dx: 1, dy: 1)
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let active = isEnabled && (hovered || isHighlighted)
    let top = selected ? accent.withAlphaComponent(active ? 0.17 : 0.105)
      : NSColor.white.withAlphaComponent(active ? 0.085 : 0.045)
    let bottom = selected ? accent.withAlphaComponent(0.025) : NSColor.white.withAlphaComponent(0.012)
    NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: 90)
    (selected ? accent.withAlphaComponent(0.65)
      : NSColor.white.withAlphaComponent(active ? 0.23 : 0.09)).setStroke()
    shape.lineWidth = 1; shape.stroke()
    if window?.firstResponder === self {
      let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: radius - 3, yRadius: radius - 3)
      accent.setStroke(); focus.lineWidth = 2; focus.stroke()
    }
  }
}

/// Three original rhythm diagrams give chapters distinct identities without implying new instruments.
private final class CourseChapterButton: JourneyCardButton {
  var chapter = 0
  var selected = false
  var clearedSteps: [Bool] = [false, false, false, false]
  var availableSteps: [Bool] = [true, false, false, false]
  override var intrinsicContentSize: NSSize { NSSize(width: 282, height: 166) }

  override func draw(_ dirtyRect: NSRect) {
    let accent = CourseInk.chapterColors[chapter]
    surface(selected: selected, accent: accent)
    CourseInk.text(String(format: "%02d", chapter + 1), in: NSRect(x: 20, y: 18, width: 38, height: 28),
                   size: 23, color: selected ? accent : CourseInk.muted, weight: .light)
    drawRhythm(in: NSRect(x: bounds.width - 125, y: 14, width: 101, height: 48), color: accent)
    CourseInk.text(DrumxCourse.chapterTitles[chapter], in: NSRect(x: 20, y: 71, width: bounds.width - 40, height: 47),
                   size: 20, weight: .semibold)
    let complete = clearedSteps.filter { $0 }.count
    let caption = complete == 4 ? "4 / 4 steps complete" : availableSteps.contains(true) ? "\(complete) / 4 steps complete" : "Explore what’s ahead"
    CourseInk.text(caption, in: NSRect(x: 20, y: 132, width: bounds.width - 124, height: 16),
                   size: 10, color: selected ? accent : CourseInk.muted, weight: .medium)
    for index in 0..<4 {
      let x = bounds.width - 74 + CGFloat(index) * 13
      CourseInk.circle(NSRect(x: x, y: 136, width: 6, height: 6),
        color: clearedSteps[index] ? accent : accent.withAlphaComponent(availableSteps[index] ? 0.35 : 0.15),
        filled: clearedSteps[index] || availableSteps[index])
    }
  }

  private func drawRhythm(in rect: NSRect, color: NSColor) {
    let faint = color.withAlphaComponent(0.23)
    if chapter == 0 {
      let center = NSPoint(x: rect.midX, y: rect.midY)
      for size: CGFloat in [43, 29, 13] {
        CourseInk.circle(NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                         color: size == 13 ? color : faint, filled: size == 13)
      }
      CourseInk.line([NSPoint(x: rect.minX, y: rect.midY), NSPoint(x: rect.minX + 20, y: rect.midY)], color: faint)
      CourseInk.line([NSPoint(x: rect.maxX - 20, y: rect.midY), NSPoint(x: rect.maxX, y: rect.midY)], color: faint)
    } else if chapter == 1 {
      for lane in 0..<3 {
        let y = rect.minY + 9 + CGFloat(lane) * 15
        CourseInk.line([NSPoint(x: rect.minX, y: y), NSPoint(x: rect.maxX, y: y)], color: faint)
        for beat in 0..<4 where lane == 0 || (lane == 1 ? beat % 2 == 1 : beat % 2 == 0) {
          let x = rect.minX + 8 + CGFloat(beat) * 28
          CourseInk.circle(NSRect(x: x, y: y - 3, width: 6, height: 6), color: color.withAlphaComponent(lane == 0 ? 0.9 : 0.6))
        }
      }
    } else {
      let y = rect.midY
      CourseInk.line([NSPoint(x: rect.minX, y: y), NSPoint(x: rect.maxX, y: y)], color: faint)
      for beat in 0..<5 {
        let x = rect.minX + 2 + CGFloat(beat) * 23
        let lift: CGFloat = beat % 2 == 0 ? 9 : -9
        CourseInk.line([NSPoint(x: x + 3, y: y), NSPoint(x: x + 3, y: y + lift)], color: faint)
        CourseInk.circle(NSRect(x: x, y: y + lift - 3, width: 6, height: 6),
          color: color.withAlphaComponent(beat < 3 ? 0.9 : 0.5), filled: beat < 3)
      }
    }
  }
}

/// Each lesson is one action. A locked card remains readable but cannot start a lesson.
private final class CourseLessonButton: JourneyCardButton {
  var lesson: DrumxLessonDefinition?
  var progressText = "New"
  var selected = false
  var cleared = false
  var lockReason: String?
  var number = 1
  override var intrinsicContentSize: NSSize { NSSize(width: 211, height: 230) }

  override func draw(_ dirtyRect: NSRect) {
    guard let lesson else { return }
    let accent = CourseInk.chapterColors[lesson.chapter]
    surface(selected: selected && isEnabled, accent: accent, radius: 15)
    let quiet = !isEnabled
    let contentColor = quiet ? CourseInk.paper.withAlphaComponent(0.63) : CourseInk.paper
    CourseInk.circle(NSRect(x: 18, y: 17, width: 25, height: 25),
      color: cleared ? accent : NSColor.white.withAlphaComponent(0.065))
    if cleared {
      CourseInk.line([NSPoint(x: 25, y: 29), NSPoint(x: 29, y: 33), NSPoint(x: 36, y: 25)], color: CourseInk.ink, width: 1.6)
    } else {
      CourseInk.text(String(format: "%02d", number), in: NSRect(x: 18, y: 22, width: 25, height: 15),
                     size: 10, color: contentColor, weight: .semibold, alignment: .center)
    }
    let practised = progressText.contains("Practised") || progressText.localizedCaseInsensitiveContains("recall")
    let state = quiet ? "LOCKED" : cleared ? "STEP COMPLETE" : selected ? "YOUR CURRENT STEP" : practised ? "PRACTISED" : "READY TO PLAY"
    CourseInk.text(state, in: NSRect(x: 51, y: 24, width: bounds.width - 67, height: 14), size: 9,
                   color: quiet ? CourseInk.muted : accent, weight: .semibold)
    CourseInk.text(lesson.title, in: NSRect(x: 18, y: 60, width: bounds.width - 36, height: 48),
                   size: 19, color: contentColor, weight: .semibold)
    CourseInk.text(lesson.subtitle, in: NSRect(x: 18, y: 111, width: bounds.width - 36, height: 34),
                   size: 12, color: CourseInk.muted)
    if quiet {
      drawLock(at: NSPoint(x: 19, y: 162))
      CourseInk.text(lockReason ?? "Complete the previous step to unlock.",
        in: NSRect(x: 39, y: 157, width: bounds.width - 55, height: 60), size: 11, color: CourseInk.muted)
    } else {
      drawBeatMap(lesson, in: NSRect(x: 19, y: 157, width: bounds.width - 39, height: 17), color: accent)
      let action = selected ? "Continue" : cleared ? "Play again" : "Play lesson"
      CourseInk.text(action, in: NSRect(x: 18, y: 195, width: 110, height: 17), size: 12, color: accent, weight: .semibold)
      let x = bounds.width - 29
      CourseInk.line([NSPoint(x: x - 7, y: 202), NSPoint(x: x + 3, y: 202)], color: accent, width: 1.4)
      CourseInk.line([NSPoint(x: x, y: 199), NSPoint(x: x + 3, y: 202), NSPoint(x: x, y: 205)], color: accent, width: 1.4)
    }
  }

  private func drawBeatMap(_ lesson: DrumxLessonDefinition, in rect: NSRect, color: NSColor) {
    // A small preview of authored attack density, not a replacement notation system.
    for step in 0..<8 {
      let voices = lesson.events.filter { abs($0.beat - Double(step) * 0.5) < 0.01 }.count
      let x = rect.minX + CGFloat(step) * (rect.width - 5) / 7
      let height = CGFloat(max(1, voices)) * 4
      let path = NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - height / 2, width: 4, height: height), xRadius: 2, yRadius: 2)
      color.withAlphaComponent(voices == 0 ? 0.12 : step % 2 == 0 ? 0.7 : 0.4).setFill(); path.fill()
    }
  }

  private func drawLock(at origin: NSPoint) {
    let body = NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y + 5, width: 11, height: 9), xRadius: 2, yRadius: 2)
    CourseInk.muted.setStroke(); body.lineWidth = 1.2; body.stroke()
    let shackle = NSBezierPath()
    shackle.move(to: NSPoint(x: origin.x + 2.5, y: origin.y + 5))
    shackle.line(to: NSPoint(x: origin.x + 2.5, y: origin.y + 2))
    shackle.curve(to: NSPoint(x: origin.x + 8.5, y: origin.y + 2),
      controlPoint1: NSPoint(x: origin.x + 2.5, y: origin.y - 2), controlPoint2: NSPoint(x: origin.x + 8.5, y: origin.y - 2))
    shackle.line(to: NSPoint(x: origin.x + 8.5, y: origin.y + 5))
    shackle.lineWidth = 1.2; shackle.stroke()
  }
}

private final class CourseStepPath: NSView {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let cardWidth = (bounds.width - 36) / 4
    for index in 0..<3 {
      let x = (cardWidth + 12) * CGFloat(index) + cardWidth
      CourseInk.line([NSPoint(x: x + 2, y: 29), NSPoint(x: x + 10, y: 29)],
                     color: CourseInk.muted.withAlphaComponent(0.35))
    }
  }
}

/// A browsable chapter journey. Resuming a session belongs to the separate main menu.
final class DrumxCourseMenuView: NSView {
  var onSelect: ((String) -> Void)?
  // Retained for controller compatibility; this page has no duplicate resume action.
  var onContinue: (() -> Void)?
  private let titleLabel = CourseInk.label("Your foundation.", size: 38, weight: .bold)
  private let subtitle = CourseInk.label("", size: 15, color: CourseInk.muted)
  private let progressLabel = CourseInk.label("", size: 12, color: CourseInk.muted)
  private let chapterHeading = CourseInk.label("", size: 21, weight: .semibold)
  private let chapterDescription = CourseInk.label("", size: 12, color: CourseInk.muted)
  private var chapterButtons: [CourseChapterButton] = []
  private let lessonStack = NSStackView()
  private var statuses: [String: String] = [:]
  private var availableIDs = Set(DrumxCourse.lessons.map(\.id))
  private var clearedIDs: Set<String> = []
  private var lockReasons: [String: String] = [:]
  private var selectedID = ""
  private var selectedChapter = 0
  private var displayedPlayer = ""

  override init(frame: NSRect) {
    super.init(frame: frame)
    let heading = NSView()
    for child in [titleLabel, subtitle, progressLabel] {
      child.translatesAutoresizingMaskIntoConstraints = false; heading.addSubview(child)
    }
    subtitle.lineBreakMode = .byTruncatingTail
    NSLayoutConstraint.activate([
      heading.heightAnchor.constraint(equalToConstant: 68),
      titleLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      titleLabel.topAnchor.constraint(equalTo: heading.topAnchor),
      subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      subtitle.bottomAnchor.constraint(equalTo: heading.bottomAnchor),
      subtitle.trailingAnchor.constraint(lessThanOrEqualTo: heading.trailingAnchor),
      progressLabel.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
      progressLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 4),
    ])
    let chapters = NSStackView()
    chapters.orientation = .horizontal; chapters.distribution = .fillEqually; chapters.spacing = 16
    for (index, name) in DrumxCourse.chapterTitles.enumerated() {
      let card = CourseChapterButton(title: name, target: self, action: #selector(chapterChanged(_:)))
      card.chapter = index; card.tag = index; card.isBordered = false; card.focusRingType = .none
      card.setAccessibilityLabel("Chapter \(index + 1). \(name)")
      card.setAccessibilityHelp("Show this chapter’s four lesson steps, including locked lessons.")
      chapters.addArrangedSubview(card); chapterButtons.append(card)
    }
    chapters.heightAnchor.constraint(equalToConstant: 166).isActive = true
    let chapterCopy = NSStackView(views: [chapterHeading, chapterDescription])
    chapterCopy.orientation = .vertical; chapterCopy.alignment = .leading; chapterCopy.spacing = 7
    chapterCopy.heightAnchor.constraint(equalToConstant: 54).isActive = true
    lessonStack.orientation = .horizontal; lessonStack.distribution = .fillEqually; lessonStack.spacing = 12
    let path = CourseStepPath()
    lessonStack.translatesAutoresizingMaskIntoConstraints = false; path.addSubview(lessonStack)
    NSLayoutConstraint.activate([
      path.heightAnchor.constraint(equalToConstant: 230),
      lessonStack.topAnchor.constraint(equalTo: path.topAnchor),
      lessonStack.bottomAnchor.constraint(equalTo: path.bottomAnchor),
      lessonStack.leadingAnchor.constraint(equalTo: path.leadingAnchor),
      lessonStack.trailingAnchor.constraint(equalTo: path.trailingAnchor),
    ])
    let stack = NSStackView(views: [heading, chapters, chapterCopy, path])
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.widthAnchor.constraint(equalToConstant: 880),
    ])
    for view in [heading, chapters, chapterCopy, path] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
  }

  required init?(coder: NSCoder) { super.init(coder: coder) }

  func update(lesson: DrumxLessonDefinition, player: String, statuses: [String: String], practised: Int,
              availability: Set<String>? = nil, cleared: Set<String> = [], lockReasons: [String: String] = [:]) {
    if selectedID != lesson.id || displayedPlayer != player { selectedChapter = lesson.chapter }
    selectedID = lesson.id; displayedPlayer = player; self.statuses = statuses
    availableIDs = availability ?? Set(DrumxCourse.lessons.map(\.id))
    clearedIDs = cleared; self.lockReasons = lockReasons
    subtitle.stringValue = "\(player)’s journey from a steady pulse to your first fill."
    progressLabel.stringValue = "\(cleared.count) / \(DrumxCourse.lessons.count) steps complete"
    progressLabel.setAccessibilityValue("\(cleared.count) steps complete. \(practised) lessons practised. Completion unlocks practice; it does not certify technique.")
    rebuildLessons()
  }

  @objc private func chapterChanged(_ sender: CourseChapterButton) {
    selectedChapter = sender.chapter; rebuildLessons()
  }
  @objc private func chooseLesson(_ sender: CourseLessonButton) {
    if let lesson = sender.lesson, availableIDs.contains(lesson.id) { onSelect?(lesson.id) }
  }
  private func rebuildLessons() {
    for card in chapterButtons {
      let lessons = DrumxCourse.lessons.filter { $0.chapter == card.chapter }
      card.selected = card.chapter == selectedChapter
      card.clearedSteps = lessons.map { clearedIDs.contains($0.id) }
      card.availableSteps = lessons.map { availableIDs.contains($0.id) }
      card.setAccessibilityValue("\(card.selected ? "Selected. " : "")\(card.clearedSteps.filter { $0 }.count) of 4 steps complete.")
      card.needsDisplay = true
    }
    chapterHeading.stringValue = String(format: "%02d", selectedChapter + 1) + "  " + DrumxCourse.chapterTitles[selectedChapter]
    chapterDescription.stringValue = [
      "Start with space, pulse, and a steady count. One small step at a time.",
      "Bring your hands and foot together. Build the groove one layer at a time.",
      "Change the pattern, leave some space, and make your first fill.",
    ][selectedChapter]
    lessonStack.arrangedSubviews.forEach { lessonStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    for (index, lesson) in DrumxCourse.lessons.enumerated() where lesson.chapter == selectedChapter {
      let card = CourseLessonButton(title: lesson.title, target: self, action: #selector(chooseLesson(_:)))
      card.lesson = lesson; card.number = index + 1; card.isBordered = false; card.focusRingType = .none
      card.progressText = statuses[lesson.id] ?? "New"; card.selected = lesson.id == selectedID
      card.cleared = clearedIDs.contains(lesson.id); card.isEnabled = availableIDs.contains(lesson.id)
      card.lockReason = lockReasons[lesson.id]
      let state = card.isEnabled ? card.cleared ? "Step complete." : "Available. \(card.progressText)."
        : "Locked. \(card.lockReason ?? "Complete the previous step to unlock.")"
      card.setAccessibilityLabel("Lesson \(index + 1). \(lesson.title). \(lesson.subtitle) \(state) \(lesson.practiceMinutes) of practice.")
      card.setAccessibilityHelp(card.isEnabled ? lesson.objective : card.lockReason)
      card.toolTip = card.isEnabled ? lesson.objective : card.lockReason
      lessonStack.addArrangedSubview(card)
    }
    window?.recalculateKeyViewLoop()
  }
}

/// Original static visual for the welcome page, with no startup loading fiction.
final class DrumxWelcomeMark: NSView {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let mid = bounds.midX
    for index in 0..<5 {
      let size = CGFloat(80 + index * 35)
      CourseInk.lime.withAlphaComponent(0.2 - Double(index) * 0.034).setStroke()
      let ring = NSBezierPath(ovalIn: NSRect(x: mid - size / 2, y: bounds.midY - size / 2, width: size, height: size))
      ring.lineWidth = 1; ring.stroke()
    }
    CourseInk.lime.setFill()
    NSBezierPath(ovalIn: NSRect(x: mid - 26, y: bounds.midY - 26, width: 52, height: 52)).fill()
    NSColor(calibratedWhite: 0.06, alpha: 1).setStroke()
    for x in [-8.0, 8.0] {
      let stick = NSBezierPath()
      stick.move(to: NSPoint(x: mid + x - 5, y: bounds.midY - 12))
      stick.line(to: NSPoint(x: mid + x + 5, y: bounds.midY + 12))
      stick.lineWidth = 3; stick.lineCapStyle = .round; stick.stroke()
    }
  }
}
