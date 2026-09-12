import AppKit

private enum CourseInk {
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)
  static func label(_ text: String, size: CGFloat, color: NSColor = paper,
                    weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
  }
}

/// A lesson row is a single accessible action. No nested controls or hidden hover actions.
private final class CourseLessonButton: NSButton {
  var lesson: DrumxLessonDefinition?
  var progressText = "New"
  var selected = false
  var number = 1
  override var intrinsicContentSize: NSSize { NSSize(width: 880, height: 70) }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    NSColor.white.withAlphaComponent(isHighlighted ? 0.10 : selected ? 0.065 : 0.025).setFill()
    shape.fill()
    (selected ? CourseInk.lime.withAlphaComponent(0.4) : NSColor.white.withAlphaComponent(0.08)).setStroke()
    shape.stroke()
    func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor,
              _ weight: NSFont.Weight = .medium, right: Bool = false) {
      let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
      let width = (value as NSString).size(withAttributes: attrs).width
      (value as NSString).draw(at: NSPoint(x: right ? x - width : x, y: y), withAttributes: attrs)
    }
    text(String(format: "%02d", number), 21, 24, 14, selected ? CourseInk.lime : CourseInk.muted)
    text(lesson?.title ?? "", 66, 12, 17, CourseInk.paper, .semibold)
    text(lesson?.subtitle ?? "", 66, 39, 12, CourseInk.muted)
    text(progressText, bounds.width - 24, 15, 11, selected ? CourseInk.lime : CourseInk.muted, right: true)
    text(lesson?.practiceMinutes ?? "", bounds.width - 24, 39, 11, CourseInk.muted, right: true)
  }
}

/// Focused course home. The stage replaces it completely when playing.
final class DrumxCourseMenuView: NSView {
  var onSelect: ((String) -> Void)?
  var onContinue: (() -> Void)?
  private let titleLabel = CourseInk.label("Find your rhythm.", size: 42, weight: .bold)
  private let subtitle = CourseInk.label("", size: 15, color: CourseInk.muted)
  private let resumeTitle = CourseInk.label("", size: 23, weight: .semibold)
  private let resumeDetail = CourseInk.label("", size: 13, color: CourseInk.muted)
  private let progressLabel = CourseInk.label("", size: 12, color: CourseInk.lime)
  private let chapterControl = NSSegmentedControl()
  private let lessonStack = NSStackView()
  private var statuses: [String: String] = [:]
  private var selectedID = "pulse"

  override init(frame: NSRect) {
    super.init(frame: frame)
    let eyebrow = CourseInk.label("FOUNDATIONS  /  A LITTLE, OFTEN", size: 11, color: CourseInk.lime, weight: .semibold)
    let resume = NSView()
    resumeDetail.lineBreakMode = .byTruncatingTail
    resumeDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    resume.wantsLayer = true
    resume.layer?.backgroundColor = CourseInk.lime.withAlphaComponent(0.045).cgColor
    resume.layer?.cornerRadius = 14
    resume.layer?.borderColor = CourseInk.lime.withAlphaComponent(0.16).cgColor
    resume.layer?.borderWidth = 1
    let resumeCopy = NSStackView(views: [resumeTitle, resumeDetail])
    resumeCopy.orientation = .vertical; resumeCopy.alignment = .leading; resumeCopy.spacing = 8
    let go = LessonButton(title: "Continue", target: self, action: #selector(continueLesson))
    go.primary = true; go.isBordered = false
    for child in [resumeCopy, go] { child.translatesAutoresizingMaskIntoConstraints = false; resume.addSubview(child) }
    NSLayoutConstraint.activate([
      resume.heightAnchor.constraint(equalToConstant: 94),
      resumeCopy.leadingAnchor.constraint(equalTo: resume.leadingAnchor, constant: 22),
      resumeCopy.centerYAnchor.constraint(equalTo: resume.centerYAnchor),
      resumeCopy.trailingAnchor.constraint(lessThanOrEqualTo: go.leadingAnchor, constant: -16),
      go.trailingAnchor.constraint(equalTo: resume.trailingAnchor, constant: -22),
      go.centerYAnchor.constraint(equalTo: resume.centerYAnchor),
    ])
    chapterControl.segmentCount = DrumxCourse.chapterTitles.count
    chapterControl.trackingMode = .selectOne
    chapterControl.segmentStyle = .rounded
    for (index, name) in DrumxCourse.chapterTitles.enumerated() {
      chapterControl.setLabel("\(index + 1)  \(name)", forSegment: index)
      chapterControl.setWidth(280, forSegment: index)
    }
    chapterControl.selectedSegment = 0
    chapterControl.target = self; chapterControl.action = #selector(chapterChanged)
    chapterControl.setAccessibilityLabel("Foundation chapter")
    lessonStack.orientation = .vertical; lessonStack.alignment = .leading; lessonStack.spacing = 8
    let stack = NSStackView(views: [eyebrow, titleLabel, subtitle, resume, progressLabel, chapterControl, lessonStack])
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.widthAnchor.constraint(equalToConstant: 880),
    ])
    for view in [resume, lessonStack] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
  }

  required init?(coder: NSCoder) { super.init(coder: coder) }

  func update(lesson: DrumxLessonDefinition, player: String, statuses: [String: String], practised: Int) {
    selectedID = lesson.id; self.statuses = statuses
    subtitle.stringValue = "\(player) · \(DrumxCourse.lessons.count) lessons to build a foundation. Take them at your pace."
    resumeTitle.stringValue = lesson.title
    resumeDetail.stringValue = lesson.objective
    progressLabel.stringValue = "\(practised) / \(DrumxCourse.lessons.count) lessons practised · Reading and recall are tracked separately."
    chapterControl.selectedSegment = lesson.chapter
    rebuildLessons()
  }

  @objc private func continueLesson() { onContinue?() }
  @objc private func chapterChanged() { rebuildLessons() }
  @objc private func chooseLesson(_ sender: CourseLessonButton) {
    if let lesson = sender.lesson { onSelect?(lesson.id) }
  }
  private func rebuildLessons() {
    lessonStack.arrangedSubviews.forEach { lessonStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    for (index, lesson) in DrumxCourse.lessons.enumerated() where lesson.chapter == chapterControl.selectedSegment {
      let row = CourseLessonButton(title: lesson.title, target: self, action: #selector(chooseLesson(_:)))
      row.lesson = lesson; row.number = index + 1; row.isBordered = false
      row.progressText = statuses[lesson.id] ?? "New"; row.selected = lesson.id == selectedID
      row.setAccessibilityLabel("Lesson \(index + 1). \(lesson.title). \(lesson.subtitle) \(row.progressText). \(lesson.practiceMinutes) of practice.")
      lessonStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: lessonStack.widthAnchor).isActive = true
      row.heightAnchor.constraint(equalToConstant: 70).isActive = true
    }
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
