import AppKit

/// One bar derived from the same attacks used by playback and scoring. Each voice
/// spells a numbered beat as a quarter, two eighths, or the corresponding rests.
final class DrumxNotationView: NSView {
  var lesson: DrumxLessonDefinition? {
    didSet {
      updateAccessibility()
      needsDisplay = true
    }
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 880, height: 172) }

  private let background = NSColor(calibratedRed: 0.055, green: 0.076, blue: 0.082, alpha: 1)
  private let ink = NSColor(calibratedRed: 0.921, green: 0.938, blue: 0.900, alpha: 1)
  private let muted = NSColor(calibratedRed: 0.574, green: 0.649, blue: 0.645, alpha: 1)
  private let padNames = ["Hi-hat", "Snare", "Kick"]

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    updateAccessibility()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    updateAccessibility()
  }

  private var supportedEvents: [DrumxLessonNote]? {
    guard let events = lesson?.events else { return nil }
    guard events.allSatisfy({
      $0.beat.isFinite && (0..<4).contains($0.beat) && (0..<3).contains($0.pad)
        && abs($0.beat * 2 - ($0.beat * 2).rounded()) < 0.000001
    }) else { return nil }
    let keys = events.map { Int(($0.beat * 2).rounded()) * 3 + $0.pad }
    guard Set(keys).count == keys.count else { return nil }
    return events
  }

  private func updateAccessibility() {
    guard let lesson else {
      setAccessibilityLabel("One-bar drum notation. Choose a lesson to read its rhythm.")
      return
    }
    guard let events = supportedEvents else {
      setAccessibilityLabel("\(lesson.title). Notation is unavailable for this rhythm.")
      return
    }
    let eighths = events.contains { Int(($0.beat * 2).rounded()) % 2 == 1 }
    let groups = Dictionary(grouping: events, by: { Int(($0.beat * 2).rounded()) })
    let counts = stride(from: 0, to: 8, by: eighths ? 1 : 2).map { tick in
      let count = tick.isMultiple(of: 2) ? "Count \(tick / 2 + 1)" : "And of \(tick / 2 + 1)"
      let instruments = (groups[tick] ?? []).sorted { $0.pad < $1.pad }.map { padNames[$0.pad] }
      let hands = Set((groups[tick] ?? []).filter { $0.pad != 2 }.compactMap(\.hand)).sorted()
      let suggestion = hands.isEmpty ? "" : "; suggested hands \(hands.joined(separator: " and "))"
      return "\(count): \(instruments.isEmpty ? "no strike" : instruments.joined(separator: " and "))\(suggestion)"
    }
    setAccessibilityLabel("\(lesson.title). One bar of four-four time. \(counts.joined(separator: ". ")). Hi-hat and snare share the upper voice; kick uses the lower voice when present.")
  }

  private func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 11,
                    color: NSColor? = nil, centered: Bool = false) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color ?? muted,
    ]
    let string = value as NSString
    let width = string.size(withAttributes: attributes).width
    string.draw(at: NSPoint(x: centered ? x - width / 2 : x, y: y), withAttributes: attributes)
  }

  private func line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat,
                    color: NSColor? = nil, width: CGFloat = 1.1) {
    (color ?? ink).setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x1, y: y1))
    path.line(to: NSPoint(x: x2, y: y2))
    path.lineWidth = width
    path.stroke()
  }

  private func notehead(x: CGFloat, y: CGFloat, cross: Bool = false) {
    if cross {
      line(x1: x - 4, y1: y - 3.5, x2: x + 4, y2: y + 3.5, width: 1.5)
      line(x1: x - 4, y1: y + 3.5, x2: x + 4, y2: y - 3.5, width: 1.5)
      return
    }
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x, yBy: y)
    transform.rotate(byDegrees: -17)
    transform.concat()
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: -5.5, y: -3.5, width: 11, height: 7)).fill()
    NSGraphicsContext.restoreGraphicsState()
  }

  private func quarterRest(x: CGFloat, y: CGFloat) {
    let rest = NSBezierPath()
    rest.move(to: NSPoint(x: x + 1, y: y - 17))
    rest.line(to: NSPoint(x: x + 7, y: y - 9))
    rest.line(to: NSPoint(x: x + 2, y: y - 3))
    rest.line(to: NSPoint(x: x + 7, y: y + 4))
    rest.curve(to: NSPoint(x: x - 4, y: y + 6),
               controlPoint1: NSPoint(x: x + 1, y: y + 1),
               controlPoint2: NSPoint(x: x - 4, y: y + 2))
    rest.curve(to: NSPoint(x: x + 1, y: y + 16),
               controlPoint1: NSPoint(x: x - 4, y: y + 10),
               controlPoint2: NSPoint(x: x - 1, y: y + 13))
    rest.curve(to: NSPoint(x: x - 8, y: y + 5),
               controlPoint1: NSPoint(x: x - 4, y: y + 13),
               controlPoint2: NSPoint(x: x - 8, y: y + 9))
    rest.curve(to: NSPoint(x: x - 1, y: y - 1),
               controlPoint1: NSPoint(x: x - 8, y: y + 1),
               controlPoint2: NSPoint(x: x - 4, y: y - 2))
    rest.line(to: NSPoint(x: x - 5, y: y - 7))
    rest.line(to: NSPoint(x: x + 1, y: y - 13))
    rest.line(to: NSPoint(x: x - 2, y: y - 18))
    rest.close()
    ink.setFill()
    rest.fill()
  }

  private func eighthRest(x: CGFloat, y: CGFloat) {
    // One hook and dot distinguish this half-beat rest from a quarter rest.
    let hook = NSBezierPath()
    hook.move(to: NSPoint(x: x - 4, y: y + 12))
    hook.line(to: NSPoint(x: x + 4, y: y - 11))
    hook.curve(to: NSPoint(x: x - 5, y: y - 6),
               controlPoint1: NSPoint(x: x + 1, y: y - 5),
               controlPoint2: NSPoint(x: x - 3, y: y - 3))
    ink.setStroke()
    hook.lineWidth = 1.7
    hook.stroke()
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 8, y: y - 9, width: 6, height: 6)).fill()
  }

  private func eighthFlag(stemX: CGFloat, endY: CGFloat, down: Bool) {
    let sign: CGFloat = down ? -1 : 1
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
      NSPoint(x: stemX + sign * x, y: endY + sign * y)
    }
    let flag = NSBezierPath()
    flag.move(to: p(0, 0))
    flag.curve(to: p(10, 11), controlPoint1: p(2, 6), controlPoint2: p(10, 7))
    flag.curve(to: p(5, 24), controlPoint1: p(12, 16), controlPoint2: p(8, 22))
    flag.curve(to: p(6, 12), controlPoint1: p(9, 17), controlPoint2: p(9, 14))
    flag.curve(to: p(0, 7), controlPoint1: p(1, 11), controlPoint2: p(1, 9))
    flag.close()
    ink.setFill()
    flag.fill()
  }

  private func drawVoice(events: [DrumxLessonNote], down: Bool, staffTop: CGFloat,
                         noteStart: CGFloat, step: CGFloat, restY: CGFloat) {
    let groups = Dictionary(grouping: events, by: { Int(($0.beat * 2).rounded()) })
    let ys = [staffTop - 5, staffTop + 15, staffTop + 35]
    func chord(_ notes: [DrumxLessonNote], at x: CGFloat, endY: CGFloat, flagged: Bool) {
      for note in notes { notehead(x: x, y: ys[note.pad], cross: note.pad == 0) }
      let stemX = x + (down ? -5 : 4.5)
      let startY = down ? notes.map { ys[$0.pad] }.min()! : notes.map { ys[$0.pad] }.max()!
      line(x1: stemX, y1: startY, x2: stemX, y2: endY)
      if flagged { eighthFlag(stemX: stemX, endY: endY, down: down) }
    }
    for beat in 0..<4 {
      let first = groups[beat * 2] ?? [], second = groups[beat * 2 + 1] ?? []
      let x = noteStart + CGFloat(beat * 2) * step
      guard !first.isEmpty || !second.isEmpty else {
        quarterRest(x: x, y: restY)
        continue
      }
      let notes = first + second
      let endY = down ? ys[2] + 31 : notes.map { ys[$0.pad] }.min()! - 30
      if second.isEmpty {
        chord(first, at: x, endY: endY, flagged: false)
      } else if first.isEmpty {
        eighthRest(x: x, y: restY)
        chord(second, at: x + step, endY: endY, flagged: true)
      } else {
        chord(first, at: x, endY: endY, flagged: false)
        chord(second, at: x + step, endY: endY, flagged: false)
        ink.setFill()
        NSRect(x: x + (down ? -5 : 4.5), y: endY - (down ? 3.6 : 0),
               width: step + 0.5, height: 3.6).fill()
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    background.setFill()
    bounds.fill()
    guard bounds.width >= 320, bounds.height >= 168 else {
      text("Enlarge this view to read the bar.", x: 16, y: 12)
      return
    }
    guard lesson != nil, let events = supportedEvents else {
      text(lesson == nil ? "Choose a lesson to read its rhythm." : "Notation is unavailable for this rhythm.",
           x: 24, y: 24)
      return
    }
    let offset = max(0, (bounds.height - 172) / 2)
    let left: CGFloat = 24, right = bounds.width - 24
    let staffTop = offset + 54
    let noteStart: CGFloat = 114
    let step = (right - noteStart - 18) / 8
    let upper = events.filter { $0.pad != 2 }, lower = events.filter { $0.pad == 2 }
    let eighths = events.contains { Int(($0.beat * 2).rounded()) % 2 == 1 }
    text("ONE BAR / 4/4", x: left, y: offset + 6)
    for row in 0..<5 {
      let y = staffTop + CGFloat(row) * 10
      line(x1: left, y1: y, x2: right, y2: y, color: muted.withAlphaComponent(0.55), width: 0.65)
    }
    line(x1: left, y1: staffTop, x2: left, y2: staffTop + 40, color: muted.withAlphaComponent(0.65), width: 0.8)
    line(x1: right - 4, y1: staffTop, x2: right - 4, y2: staffTop + 40, width: 0.8)
    line(x1: right, y1: staffTop, x2: right, y2: staffTop + 40, width: 2)
    ink.setFill()
    NSRect(x: left + 13, y: staffTop + 8, width: 3, height: 24).fill()
    NSRect(x: left + 21, y: staffTop + 8, width: 3, height: 24).fill()
    text("4", x: left + 51, y: staffTop - 4, size: 22, color: ink, centered: true)
    text("4", x: left + 51, y: staffTop + 17, size: 22, color: ink, centered: true)

    // Omit an entirely absent part instead of manufacturing a silent second voice.
    if !upper.isEmpty || lower.isEmpty {
      drawVoice(events: upper, down: false, staffTop: staffTop, noteStart: noteStart,
                step: step, restY: staffTop + (lower.isEmpty ? 20 : 9))
    }
    if !lower.isEmpty {
      drawVoice(events: lower, down: true, staffTop: staffTop, noteStart: noteStart,
                step: step, restY: staffTop + (upper.isEmpty ? 20 : 52))
    }
    for tick in stride(from: 0, to: 8, by: eighths ? 1 : 2) {
      text(tick.isMultiple(of: 2) ? String(tick / 2 + 1) : "&",
           x: noteStart + CGFloat(tick) * step, y: offset + 132, size: 12,
           color: tick.isMultiple(of: 2) ? ink : muted, centered: true)
    }
    let pads = Array(Set(events.map(\.pad))).sorted()
    // Keep the staff and count geometry stable. The compact key lives in the
    // heading; authored sticking sits directly below its musical count.
    let keyWidth: CGFloat = bounds.width < 540 ? 57 : 88
    let keyStart = right - CGFloat(pads.count) * keyWidth
    for (index, pad) in pads.enumerated() {
      let x = keyStart + CGFloat(index) * keyWidth
      notehead(x: x + 6, y: offset + 13, cross: pad == 0)
      text(bounds.width < 540 ? ["HAT", "SN", "KICK"][pad] : padNames[pad],
           x: x + 17, y: offset + 6, size: bounds.width < 540 ? 10 : 11)
    }
    let handGroups = Dictionary(grouping: events.filter { $0.pad != 2 && $0.hand != nil },
                                by: { Int(($0.beat * 2).rounded()) })
    if !handGroups.isEmpty {
      text("R/L suggested", x: left, y: offset + 153, size: 10)
      for tick in 0..<8 {
        let hands = Set((handGroups[tick] ?? []).compactMap(\.hand)).sorted()
        text(hands.joined(separator: "+"), x: noteStart + CGFloat(tick) * step,
             y: offset + 152, size: 11, color: ink, centered: true)
      }
    }
  }
}
