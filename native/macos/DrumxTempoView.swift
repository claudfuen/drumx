import AppKit

/// Compact coaching within the accepted preparation layout. It presents the next
/// explicit action; the transport owns the immutable tempo of the current take.
final class DrumxTempoView: NSView {
  private var bpm: Double = 60
  private var cue = ""
  private var detail = ""
  private var checkpoint = false
  private var recalled = false
  private let lime = NSColor(srgbRed: 0.77, green: 0.96, blue: 0.36, alpha: 1)
  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 100) }

  func update(bpm: Double, title: String, detail: String, checkpoint: Bool, recalled: Bool) {
    self.bpm = bpm; cue = title; self.detail = detail
    self.checkpoint = checkpoint; self.recalled = recalled
    setAccessibilityElement(true); setAccessibilityRole(.group)
    setAccessibilityLabel("Guided pulse. Next pace \(Int(bpm)) BPM. \(title) \(detail). "
      + "Checkpoint requires two of three comparable 16-bar takes at 72 BPM: at least 95 percent hits, 90 percent within 50 milliseconds, and at most 2 percent extras. "
      + (checkpoint ? "72 BPM checkpoint earned." : "72 BPM checkpoint still to earn.")
      + (recalled ? " Recalled at 72 BPM." : ""))
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor(white: 0.105, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14).fill()
    lime.withAlphaComponent(0.18).setStroke()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14).stroke()
    text("\(Int(bpm))", rect: NSRect(x: 18, y: 12, width: 75, height: 39), size: 32, weight: .bold, color: .white)
    text("BPM NEXT", rect: NSRect(x: 20, y: 53, width: 80, height: 14), size: 9, weight: .semibold, color: lime)
    let trailWidth: CGFloat = 154
    let cueWidth = max(200, bounds.width - 128 - trailWidth - 22)
    text(cue, rect: NSRect(x: 114, y: 15, width: cueWidth, height: 35), size: 13, weight: .semibold, color: .white)
    text(detail, rect: NSRect(x: 114, y: 55, width: cueWidth, height: 15), size: 10, weight: .regular, color: NSColor(white: 0.65, alpha: 1))
    text("72 BPM checkpoint · 2 in 3 comparable 16-bar takes · ≥95% hits · ≥90% within ±50 ms · ≤2% extras",
      rect: NSRect(x: 20, y: 79, width: bounds.width - 40, height: 14), size: 10,
      weight: .medium, color: NSColor(white: 0.6, alpha: 1))
    let start = bounds.width - trailWidth - 17
    let labels = ["60", "66", "72", "Recall"]
    for index in labels.indices {
      let x = start + CGFloat(index) * 39
      let earned = index < 3 ? checkpoint : recalled
      let current = index < 3 ? bpm == [60.0, 66, 72][index] : checkpoint && !recalled
      if index < 3 {
        NSColor(white: 0.27, alpha: 1).setStroke()
        let connector = NSBezierPath(); connector.move(to: NSPoint(x: x + 8, y: 30)); connector.line(to: NSPoint(x: x + 39, y: 30)); connector.stroke()
      }
      (earned || current ? lime : NSColor(white: 0.3, alpha: 1)).setFill()
      NSBezierPath(ovalIn: NSRect(x: x, y: 26, width: 8, height: 8)).fill()
      text(labels[index], rect: NSRect(x: x - 9, y: 43, width: 38, height: 15), size: 10,
        weight: current ? .bold : .medium, color: earned || current ? lime : NSColor(white: 0.6, alpha: 1))
    }
  }

  private func text(_ value: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color, .paragraphStyle: paragraph])
  }
}
