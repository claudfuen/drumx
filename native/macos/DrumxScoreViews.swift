import AppKit

private enum ScoreStyle {
  static let ink = NSColor(calibratedRed: 0.921, green: 0.938, blue: 0.900, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.574, green: 0.649, blue: 0.645, alpha: 1)
  static let quiet = NSColor(calibratedRed: 0.240, green: 0.315, blue: 0.320, alpha: 1)
  static let gold = NSColor(calibratedRed: 0.920, green: 0.751, blue: 0.449, alpha: 1)

  static func points(_ value: Int) -> String {
    max(0, value).formatted(.number.grouping(.automatic))
  }

  static func text(
    _ value: String, at point: NSPoint, size: CGFloat = 11,
    color: NSColor = muted, weight: NSFont.Weight = .medium,
    monospaced: Bool = false, alignment: NSTextAlignment = .left
  ) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: monospaced ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color,
    ]
    let string = value as NSString
    let width = string.size(withAttributes: attributes).width
    let x = alignment == .right ? point.x - width : alignment == .center ? point.x - width / 2 : point.x
    string.draw(at: NSPoint(x: x, y: point.y), withAttributes: attributes)
  }

  // Authored vector stars remain identical across fonts and display scales.
  static func star(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for vertex in 0..<10 {
      let angle = -Double.pi / 2 + Double(vertex) * Double.pi / 5
      let r = radius * (vertex.isMultiple(of: 2) ? 1 : 0.46)
      let point = NSPoint(x: center.x + CGFloat(cos(angle)) * r,
                         y: center.y + CGFloat(sin(angle)) * r)
      if vertex == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    path.lineJoinStyle = .round
    return path
  }

  static func stars(_ count: Int, origin: NSPoint, radius: CGFloat, spacing: CGFloat) {
    for index in 0..<5 {
      let path = star(center: NSPoint(x: origin.x + radius + CGFloat(index) * spacing,
                                     y: origin.y + radius), radius: radius)
      if index < count {
        gold.setFill()
        path.fill()
      } else {
        quiet.withAlphaComponent(0.28).setFill()
        path.fill()
        muted.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
      }
    }
  }

  static func bar(_ rect: NSRect, color: NSColor) {
    guard rect.width > 0, rect.height > 0 else { return }
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: min(2, rect.width / 2),
                 yRadius: min(2, rect.height / 2)).fill()
  }
}

/// A compact take header. The caller supplies nil throughout unscored/hidden states.
final class RunScoreHUD: NSView {
  private var score: DrumxRunScore?
  private var bestPoints: Int?
  private var state = "COUNT-IN"

  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 420, height: 44) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("Take score. Count-in.")
  }

  required init?(coder: NSCoder) { super.init(coder: coder) }

  func update(score: DrumxRunScore?, bestPoints: Int?, state: String) {
    self.score = score
    self.bestPoints = bestPoints
    self.state = state
    if let score {
      var description = "Take score: \(ScoreStyle.points(score.points)) points, \(score.stars) of 5 stars. Current combo \(score.combo)."
      if let bestPoints { description += " Previous comparable best \(ScoreStyle.points(bestPoints)) points." }
      if let next = score.nextStarPoints {
        description += " Next star at \(ScoreStyle.points(next)) points."
      }
      setAccessibilityLabel(description)
      toolTip = description
    } else {
      setAccessibilityLabel(state)
      toolTip = state
    }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let score else {
      ScoreStyle.text(state, at: NSPoint(x: 0, y: 14), size: 11,
                      color: ScoreStyle.muted, weight: .semibold)
      return
    }
    ScoreStyle.stars(score.stars, origin: NSPoint(x: 1, y: 5), radius: 8, spacing: 20)
    let track = NSRect(x: 1, y: 33, width: 96, height: 2)
    ScoreStyle.bar(track, color: ScoreStyle.quiet.withAlphaComponent(0.65))
    let progress = score.progressToNextStar.isFinite ? min(1, max(0, score.progressToNextStar)) : 0
    ScoreStyle.bar(NSRect(x: track.minX, y: track.minY,
                         width: track.width * CGFloat(progress), height: track.height),
                   color: ScoreStyle.gold.withAlphaComponent(0.82))
    ScoreStyle.text(ScoreStyle.points(score.points), at: NSPoint(x: 118, y: 0),
                    size: 25, color: ScoreStyle.ink, weight: .semibold, monospaced: true)
    ScoreStyle.text("POINTS", at: NSPoint(x: 119, y: 29), size: 11)
    ScoreStyle.text("\(score.combo) COMBO", at: NSPoint(x: 274, y: 4),
                    size: 13, color: ScoreStyle.ink, weight: .semibold, monospaced: true)
    if let bestPoints {
      ScoreStyle.text("BEST \(ScoreStyle.points(bestPoints))", at: NSPoint(x: 274, y: 25),
                      size: 11, monospaced: true)
    }
  }
}

/// Comparison values use the shared score model and only the comparable attempts supplied.
/// No animation is used, so reduced-motion settings require no alternate behavior.
final class RunScoreReviewView: NSView {
  private var score: DrumxRunScore?
  private var recent: [LessonAttempt] = []
  private var currentID: UUID?
  private var bestPoints: Int?

  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 880, height: 130) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("Take results. Complete a take to start your comparison.")
  }

  required init?(coder: NSCoder) { super.init(coder: coder) }

  func update(score: DrumxRunScore, recent: [LessonAttempt], currentID: UUID?, bestPoints: Int?) {
    self.score = score
    // Controller passes newest first. Display only real attempts, oldest at the left.
    self.recent = Array(recent.prefix(6).reversed())
    self.currentID = currentID
    self.bestPoints = bestPoints
    var description = "Take result: \(ScoreStyle.points(score.points)) points, \(score.stars) of 5 stars. Best combo \(score.bestCombo)."
    if score.isComplete && currentID == nil { description += " This result has not been saved." }
    if let bestPoints { description += " Previous comparable best \(ScoreStyle.points(bestPoints)) points." }
    if self.recent.isEmpty {
      description += " No saved comparable takes yet."
    } else {
      description += " Last \(self.recent.count) comparable takes, oldest first: "
      description += self.recent.enumerated().map { index, attempt in
        let label = attempt.id == currentID ? "current take" : "take \(index + 1)"
        return "\(label), \(ScoreStyle.points(DrumxRunScore(attempt: attempt).points)) points"
      }.joined(separator: "; ") + "."
    }
    setAccessibilityLabel(description)
    toolTip = description
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let score else { return }
    ScoreStyle.stars(score.stars, origin: NSPoint(x: 0, y: 8), radius: 14, spacing: 34)
    ScoreStyle.text(ScoreStyle.points(score.points), at: NSPoint(x: 199, y: 0),
                    size: 34, color: ScoreStyle.ink, weight: .semibold, monospaced: true)
    ScoreStyle.text("/ 10,000", at: NSPoint(x: 342, y: 20), size: 12, monospaced: true)

    let comparisonX = max(456, bounds.width - 328)
    let saved = score.isComplete && currentID != nil
    if let bestPoints {
      ScoreStyle.text("PREVIOUS BEST  \(ScoreStyle.points(bestPoints))",
                      at: NSPoint(x: comparisonX, y: 5), size: 11, monospaced: true)
      let difference = score.points - bestPoints
      let comparison = !saved ? (score.isComplete ? "Result not saved. See the message below." : "Finish the phrase to save a result.")
        : difference > 0 ? "+\(ScoreStyle.points(difference)) · NEW PERSONAL BEST"
        : difference == 0 ? "PERSONAL BEST MATCHED"
        : "\(ScoreStyle.points(-difference)) points to your best"
      ScoreStyle.text(comparison, at: NSPoint(x: comparisonX, y: 25),
                      size: 12, color: saved && difference >= 0 ? ScoreStyle.gold : ScoreStyle.muted)
    } else {
      ScoreStyle.text(saved ? "FIRST COMPARABLE TAKE" : score.isComplete ? "TAKE NOT SAVED" : "YOUR NEXT BENCHMARK",
                      at: NSPoint(x: comparisonX, y: 5), size: 11)
      ScoreStyle.text(saved ? "Complete another take to compare."
                        : score.isComplete ? "See the message below to restore saving."
                        : "Complete a take to start your comparison.",
                      at: NSPoint(x: comparisonX, y: 25), size: 12)
    }

    ScoreStyle.text("RECENT TAKES", at: NSPoint(x: 0, y: 78), size: 11)
    ScoreStyle.text("Same lesson and settings", at: NSPoint(x: 0, y: 96), size: 11)
    guard !recent.isEmpty else {
      ScoreStyle.text("No saved comparable takes yet.", at: NSPoint(x: 200, y: 89), size: 12)
      return
    }
    let startX: CGFloat = 204
    let cellWidth = max(50, (bounds.width - startX - 8) / 6)
    for (index, attempt) in recent.enumerated() {
      let points = DrumxRunScore(attempt: attempt).points
      let current = attempt.id == currentID
      let x = startX + CGFloat(index) * cellWidth + cellWidth / 2
      let color = current ? ScoreStyle.gold : ScoreStyle.muted
      ScoreStyle.text(ScoreStyle.points(points), at: NSPoint(x: x, y: 63), size: 11,
                      color: current ? ScoreStyle.ink : ScoreStyle.muted,
                      monospaced: true, alignment: .center)
      // Every take uses the same 0...10,000 scale, including zero-point takes.
      let height = CGFloat(min(10_000, max(0, points))) / 10_000 * 26
      let width = min(54, cellWidth - 22)
      ScoreStyle.bar(NSRect(x: x - width / 2, y: 106, width: width, height: 1),
                     color: ScoreStyle.quiet.withAlphaComponent(0.70))
      ScoreStyle.bar(NSRect(x: x - width / 2, y: 106 - height, width: width, height: height),
                     color: color.withAlphaComponent(current ? 0.88 : 0.46))
      ScoreStyle.text(current ? "NOW" : String(index + 1), at: NSPoint(x: x, y: 113),
                      size: 11, color: color, weight: current ? .semibold : .medium,
                      alignment: .center)
    }
  }
}
