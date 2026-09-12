import AppKit

private enum CourseInk {
  static let ink = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)
  static func label(_ value: String, size: CGFloat, color: NSColor = paper,
                    weight: NSFont.Weight = .regular, wrapping: Bool = false) -> NSTextField {
    let field = wrapping ? NSTextField(wrappingLabelWithString: value) : NSTextField(labelWithString: value)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = wrapping ? .byWordWrapping : .byTruncatingTail
    return field
  }
  static func text(_ value: String, in rect: NSRect, size: CGFloat, color: NSColor,
                   weight: NSFont.Weight = .medium, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment; paragraph.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color, .paragraphStyle: paragraph,
    ])
  }
}

/// Native action tracking, focus, and accessible frames are never transformed.
private final class CoursePathButton: NSButton {
  var selected = false { didSet { needsDisplay = true } }
  var cleared = false { didSet { needsDisplay = true } }
  var available = true { didSet { needsDisplay = true } }
  var primary = false
  var drawingScale: CGFloat = 1 { didSet { needsDisplay = true } }
  private var hovered = false
  private var tracking: NSTrackingArea?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { isEnabled }
  override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); needsDisplay = true; return result }
  override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); needsDisplay = true; return result }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area); tracking = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76 { performClick(nil) }
    else { super.keyDown(with: event) }
  }
  override func draw(_ dirtyRect: NSRect) {
    let scale = drawingScale
    let focused = window?.firstResponder === self
    let active = hovered || isHighlighted || focused
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8 * scale, yRadius: 8 * scale)
    if primary {
      (isEnabled ? CourseInk.lime.withAlphaComponent(isHighlighted ? 0.76 : 1)
        : CourseInk.paper.withAlphaComponent(0.08)).setFill()
    } else {
      (selected ? CourseInk.lime.withAlphaComponent(0.14)
        : CourseInk.paper.withAlphaComponent(active ? 0.07 : 0.025)).setFill()
    }
    path.fill()
    (focused || selected ? CourseInk.lime : CourseInk.paper.withAlphaComponent(active ? 0.3 : 0.10)).setStroke()
    path.lineWidth = focused ? 2 : 1; path.stroke()
    let color = primary && isEnabled ? CourseInk.ink : available ? CourseInk.paper : CourseInk.muted
    CourseInk.text(title, in: NSRect(x: 8 * scale, y: bounds.midY - (primary ? 12 : 11) * scale,
      width: bounds.width - 16 * scale, height: 28 * scale), size: (primary ? 18 : 17) * scale,
      color: color, weight: .semibold, alignment: .center)
    if !primary {
      let width: CGFloat = cleared ? 20 : 12
      let marker = NSBezierPath(roundedRect: NSRect(x: bounds.midX - width * scale / 2,
        y: bounds.maxY - 9 * scale, width: width * scale, height: 2.5 * scale), xRadius: scale, yRadius: scale)
      (cleared ? CourseInk.lime : available ? CourseInk.lime.withAlphaComponent(0.5)
        : CourseInk.muted.withAlphaComponent(0.22)).setFill()
      marker.fill()
    }
  }
}

private final class CourseStarsView: NSView {
  var conditions = "" { didSet { needsDisplay = true } }
  var stars = 0 { didSet { needsDisplay = true } }
  var hasRecordedScore = false { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) {
    let scale = min(bounds.width / 290, bounds.height / 146)
    guard scale > 0 else { return }
    let inset = (bounds.width - 290 * scale) / 2
    CourseInk.text(hasRecordedScore ? "BEST RECORDED" : "YOUR NEXT GOAL", in: NSRect(x: 0, y: 4 * scale, width: bounds.width, height: 18 * scale),
      size: 10 * scale, color: CourseInk.muted, alignment: .center)
    for index in 0..<5 {
      let center = NSPoint(x: inset + (29 + CGFloat(index) * 58) * scale, y: 65 * scale)
      let path = NSBezierPath()
      for point in 0..<10 {
        let angle = -Double.pi / 2 + Double(point) * Double.pi / 5
        let radius = (point.isMultiple(of: 2) ? 23.0 : 10.0) * scale
        let position = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if point == 0 { path.move(to: position) } else { path.line(to: position) }
      }
      path.close()
      if index < stars { CourseInk.lime.setFill(); path.fill() }
      else { CourseInk.paper.withAlphaComponent(0.18).setStroke(); path.lineWidth = scale; path.stroke() }
    }
    CourseInk.text(hasRecordedScore ? conditions : "Score and checkpoint are separate.", in: NSRect(x: 0, y: 112 * scale, width: bounds.width, height: 24 * scale),
      size: 12 * scale, color: CourseInk.paper, alignment: .center)
  }
}

/// One featured step, one launch action, and a compact inspectable learning path.
/// Unlock rules and score evidence remain owned by the controller and models.
final class DrumxCourseMenuView: NSView {
  var onSelect: ((String) -> Void)?
  var onContinue: (() -> Void)?
  private let content = NSView()
  private let titleLabel = CourseInk.label("One step at a time.", size: 38, weight: .bold)
  private let subtitle = CourseInk.label("", size: 14, color: CourseInk.muted)
  private let progressLabel = CourseInk.label("", size: 12, color: CourseInk.muted)
  private let stepLabel = CourseInk.label("", size: 11, color: CourseInk.lime, weight: .medium)
  private let lessonTitle = CourseInk.label("", size: 36, weight: .semibold, wrapping: true)
  private let objective = CourseInk.label("", size: 16, color: CourseInk.muted, wrapping: true)
  private let stepHint = CourseInk.label("", size: 12, color: CourseInk.muted, wrapping: true)
  private let trailLabel = CourseInk.label("YOUR LEARNING PATH", size: 11, color: CourseInk.muted, weight: .medium)
  private let trailHint = CourseInk.label("Select a step to inspect it.", size: 11, color: CourseInk.muted)
  private let playButton = CoursePathButton(title: "Play this step", target: nil, action: nil)
  private let starsView = CourseStarsView()
  private var chapterLabels: [NSTextField] = []
  private var nodes: [CoursePathButton] = []
  private var availableIDs = Set<String>()
  private var clearedIDs = Set<String>()
  private var lockReasons: [String: String] = [:]
  private var bestStarsByID: [String: Int] = [:]
  private var bestConditionsByID: [String: String] = [:]
  private var featuredID = ""
  private var contextID = ""
  private var displayedPlayer = ""

  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(content)
    for view in [titleLabel, subtitle, progressLabel, stepLabel, lessonTitle, objective, stepHint,
                 trailLabel, trailHint, playButton, starsView] { content.addSubview(view) }
    progressLabel.alignment = .right; trailHint.alignment = .right
    lessonTitle.maximumNumberOfLines = 2; objective.maximumNumberOfLines = 3; stepHint.maximumNumberOfLines = 2
    playButton.primary = true; playButton.isBordered = false; playButton.focusRingType = .none
    playButton.target = self; playButton.action = #selector(playFeatured)
    starsView.setAccessibilityElement(true); starsView.setAccessibilityRole(.image)
    for (index, title) in DrumxCourse.chapterTitles.enumerated() {
      let field = CourseInk.label("\(index + 1)  \(title)", size: 11, color: CourseInk.muted, weight: .medium)
      chapterLabels.append(field); content.addSubview(field)
    }
    for (index, lesson) in DrumxCourse.lessons.enumerated() {
      let node = CoursePathButton(title: String(format: "%02d", index + 1), target: self, action: #selector(inspectStep(_:)))
      node.tag = index; node.isBordered = false; node.focusRingType = .none
      node.toolTip = lesson.title
      nodes.append(node); content.addSubview(node)
    }
  }
  required init?(coder: NSCoder) { nil }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    guard bounds.width > 0, bounds.height > 0 else { return }
    let margin = max(24, min(112, bounds.width * 0.045))
    let availableWidth = max(1, bounds.width - margin * 2)
    let scale = min(1.4, max(0.85, min(availableWidth / 920, (bounds.height - 32) / 548)))
    let width = min(1640, availableWidth, max(920 * scale, bounds.width * 0.86))
    let height = 548 * scale
    content.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                           width: width, height: height)
    func place(_ view: NSView, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) {
      view.frame = NSRect(x: x, y: height - (top + h) * scale, width: w, height: h * scale)
      view.needsDisplay = true
    }
    let leftWidth = min(width * 0.64, 780 * scale)
    place(titleLabel, 0, 0, width * 0.72, 49)
    place(subtitle, 2 * scale, 54, width * 0.75, 22)
    place(progressLabel, width - 236 * scale, 18, 236 * scale, 22)
    place(stepLabel, 2 * scale, 113, leftWidth, 20)
    place(lessonTitle, 0, 141, leftWidth, 90)
    place(objective, 2 * scale, 235, leftWidth - 12 * scale, 64)
    place(playButton, 0, 319, 250 * scale, 54)
    place(stepHint, 270 * scale, 323, width - 270 * scale, 46)
    let starWidth = min(340 * scale, width - leftWidth - 32 * scale)
    place(starsView, width - starWidth, 155, starWidth, 146)
    place(trailLabel, 2 * scale, 416, 240 * scale, 20)
    place(trailHint, width - 240 * scale, 416, 240 * scale, 20)
    let groupGap = 28 * scale
    let groupWidth = (width - groupGap * 2) / 3
    for (chapter, label) in chapterLabels.enumerated() {
      let groupX = CGFloat(chapter) * (groupWidth + groupGap)
      place(label, groupX, 448, groupWidth, 20)
      let chapterNodes = nodes.filter { DrumxCourse.lessons[$0.tag].chapter == chapter }
      let gap = 8 * scale
      let nodeWidth = (groupWidth - gap * CGFloat(max(0, chapterNodes.count - 1))) / CGFloat(max(1, chapterNodes.count))
      for (index, node) in chapterNodes.enumerated() {
        place(node, groupX + CGFloat(index) * (nodeWidth + gap), 482, nodeWidth, 54)
        node.drawingScale = scale
      }
    }
    titleLabel.font = .systemFont(ofSize: 38 * scale, weight: .bold)
    subtitle.font = .systemFont(ofSize: 14 * scale)
    progressLabel.font = .systemFont(ofSize: 12 * scale)
    stepLabel.font = .systemFont(ofSize: 11 * scale, weight: .medium)
    lessonTitle.font = .systemFont(ofSize: 36 * scale, weight: .semibold)
    objective.font = .systemFont(ofSize: 16 * scale)
    stepHint.font = .systemFont(ofSize: 12 * scale)
    trailLabel.font = .systemFont(ofSize: 11 * scale, weight: .medium)
    trailHint.font = .systemFont(ofSize: 11 * scale)
    for label in chapterLabels { label.font = .systemFont(ofSize: 11 * scale, weight: .medium) }
    playButton.drawingScale = scale
  }

  func update(lesson: DrumxLessonDefinition, player: String, statuses: [String: String], practised: Int,
              availability: Set<String>? = nil, cleared: Set<String> = [], lockReasons: [String: String] = [:],
              recommendedID: String? = nil, bestStarsByID: [String: Int] = [:],
              bestConditionsByID: [String: String] = [:]) {
    let available = availability ?? Set(DrumxCourse.lessons.map(\.id))
    let recommended = recommendedID.flatMap { available.contains($0) ? DrumxCourse.lesson(id: $0) : nil }
      ?? DrumxCourse.lessons.first { available.contains($0.id) && !cleared.contains($0.id) }
      ?? lesson
    if displayedPlayer != player || contextID != recommended.id || featuredID.isEmpty {
      featuredID = recommended.id
    }
    displayedPlayer = player; contextID = recommended.id
    availableIDs = available; clearedIDs = cleared; self.lockReasons = lockReasons
    self.bestStarsByID = bestStarsByID; self.bestConditionsByID = bestConditionsByID
    subtitle.stringValue = "\(player)’s foundations. A steady pulse, then your first fill."
    progressLabel.stringValue = "\(cleared.count) / \(DrumxCourse.lessons.count) steps complete"
    progressLabel.setAccessibilityValue("\(cleared.count) steps complete. \(practised) lessons practised.")
    refreshFeature()
    needsLayout = true
  }

  private func refreshFeature() {
    guard let lesson = DrumxCourse.lesson(id: featuredID),
          let index = DrumxCourse.lessons.firstIndex(where: { $0.id == featuredID }) else { return }
    let available = availableIDs.contains(featuredID)
    let complete = clearedIDs.contains(featuredID)
    stepLabel.stringValue = "STEP \(String(format: "%02d", index + 1))  /  \(DrumxCourse.chapterTitles[lesson.chapter].uppercased())"
    lessonTitle.stringValue = lesson.title
    objective.stringValue = lesson.objective
    playButton.title = available ? complete ? "Play this step again" : "Play this step" : "Step locked"
    playButton.isEnabled = available
    playButton.setAccessibilityLabel(available ? "\(playButton.title). \(lesson.title)." : "\(lesson.title) is locked.")
    stepHint.stringValue = available ? complete ? "Step complete. Repeat for a steadier score, or explore your next step."
      : "Your playing and reading check move you to the next step."
      : lockReasons[featuredID] ?? "Complete the previous step to open this lesson."
    if available && lesson.version == DrumxTempoCoach.lessonVersion {
      stepHint.stringValue = complete
        ? "72 BPM checkpoint earned. Scores, reading and recall remain separate."
        : "Play the coached pulse to earn the 72 BPM checkpoint. Earlier access stays available."
    }
    starsView.stars = min(5, max(0, bestStarsByID[featuredID] ?? 0))
    starsView.hasRecordedScore = bestStarsByID[featuredID] != nil
    starsView.conditions = bestConditionsByID[featuredID] ?? "Recorded game score"
    starsView.setAccessibilityLabel(starsView.hasRecordedScore
      ? "\(starsView.stars) of 5 stars recorded for \(lesson.title). \(starsView.conditions). Score is separate from the checkpoint."
      : "Build toward five stars for \(lesson.title).")
    for node in nodes {
      let definition = DrumxCourse.lessons[node.tag]
      node.selected = definition.id == featuredID
      node.available = availableIDs.contains(definition.id)
      node.cleared = clearedIDs.contains(definition.id)
      let state = node.cleared ? "Step complete" : node.available ? "Available" : "Locked"
      node.setAccessibilityLabel("Inspect step \(node.tag + 1). \(definition.title). \(state).")
      node.setAccessibilityHelp(node.available ? definition.objective : lockReasons[definition.id])
      node.toolTip = "\(definition.title). \(state). \(node.available ? "" : lockReasons[definition.id] ?? "")"
    }
    window?.recalculateKeyViewLoop()
    needsLayout = true
  }
  @objc private func inspectStep(_ sender: CoursePathButton) {
    guard DrumxCourse.lessons.indices.contains(sender.tag) else { return }
    featuredID = DrumxCourse.lessons[sender.tag].id
    refreshFeature()
  }
  @objc private func playFeatured() {
    guard availableIDs.contains(featuredID) else { return }
    onSelect?(featuredID)
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
