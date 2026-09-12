import AppKit

private enum PracticePalette {
  static let background = NSColor(calibratedRed: 0.055, green: 0.076, blue: 0.082, alpha: 1)
  static let far = NSColor(calibratedRed: 0.078, green: 0.112, blue: 0.121, alpha: 1)
  static let near = NSColor(calibratedRed: 0.120, green: 0.178, blue: 0.186, alpha: 1)
  static let ink = NSColor(calibratedRed: 0.921, green: 0.938, blue: 0.900, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.574, green: 0.649, blue: 0.645, alpha: 1)
  static let quiet = NSColor(calibratedRed: 0.280, green: 0.351, blue: 0.351, alpha: 1)
  static let line = NSColor(calibratedRed: 0.240, green: 0.315, blue: 0.320, alpha: 1)
  static let hat = NSColor(calibratedRed: 0.540, green: 0.792, blue: 0.808, alpha: 1)
  static let snare = NSColor(calibratedRed: 0.807, green: 0.917, blue: 0.578, alpha: 1)
  static let kick = NSColor(calibratedRed: 0.865, green: 0.683, blue: 0.442, alpha: 1)
  static let memory = NSColor(calibratedRed: 0.694, green: 0.614, blue: 0.798, alpha: 1)
  static let extra = NSColor(calibratedRed: 0.940, green: 0.451, blue: 0.395, alpha: 1)
  static let pads = [hat, snare, kick]
}

final class PracticeView: NSView {
  weak var controller: LabController?
  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { true }
  override var isOpaque: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Drum practice. All notes share one NOW line. Fixed instrument positions: hi-hat, crash, snare, two toms, floor tom and ride. Kick spans the rail.")
  }

  required init?(coder: NSCoder) { super.init(coder: coder) }

  override func keyDown(with event: NSEvent) {
    guard !event.isARepeat else { return }
    if event.keyCode == 53 { controller?.dismissOrStop(); return }
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if let pad = ["a": 0, "s": 1, " ": 2][key] {
      controller?.keyboardHit(
        pad: pad, velocity: event.modifierFlags.contains(.shift) ? 48 : 108,
        hostTime: event.timestamp)
    } else {
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

  private func text(
    _ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 11,
    color: NSColor = PracticePalette.muted, alignment: NSTextAlignment = .left,
    weight: NSFont.Weight = .medium
  ) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ]
    let string = value as NSString
    let width = string.size(withAttributes: attributes).width
    let origin = alignment == .center ? x - width / 2 : alignment == .right ? x - width : x
    string.draw(at: NSPoint(x: origin, y: y), withAttributes: attributes)
  }

  private func line(_ from: NSPoint, _ to: NSPoint, color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.stroke()
  }

  private func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    return path
  }

  private typealias ActiveHit = (pulse: DrumxHitPulse, progress: Double)

  // Slot seven is the foot catcher. Its center shares beat zero with every hand.
  // Only the transient response is deformed; the permanent projected outline stays fixed.
  private func catcherPath(
    slot: Int, projection: DrumxProjection, scaleX: CGFloat = 1, scaleY: CGFloat = 1
  ) -> NSBezierPath {
    let lateral = slot == 7 ? 0 : projection.laneCenter(slot)
    let center = projection.project(lateral: lateral, beatDistance: 0)
    let vertices: [DrumxProjectedPoint]
    if slot == 7 {
      vertices = projection.rectangle(centerLateral: 0, beatDistance: 0,
                                      worldWidth: 0.99, worldDepth: 0.065)
    } else if [0, 1, 6].contains(slot) {
      vertices = projection.cymbal(centerLateral: lateral, beatDistance: 0,
                                   worldWidth: 0.75 / 7, worldDepth: 0.16)
    } else {
      vertices = projection.drum(centerLateral: lateral, beatDistance: 0,
                                 worldWidth: 0.75 / 7, worldDepth: 0.16)
    }
    return polygon(vertices.map {
      NSPoint(x: center.x + ($0.x - center.x) * Double(scaleX),
              y: center.y + ($0.y - center.y) * Double(scaleY))
    })
  }

  private func drawCatchers(
    slots: [Int], projection: DrumxProjection, hits: [ActiveHit], reduceMotion: Bool
  ) {
    for slot in slots {
      let pad = slot == 0 ? 0 : slot == 2 ? 1 : slot == 7 ? 2 : -1
      let used = pad >= 0
      let color = used ? PracticePalette.pads[pad] : PracticePalette.quiet
      let outline = catcherPath(slot: slot, projection: projection)
      NSGraphicsContext.saveGraphicsState()
      let depth = NSShadow(); depth.shadowColor = NSColor.black.withAlphaComponent(used ? 0.36 : 0.15)
      depth.shadowBlurRadius = used ? 5 : 2; depth.shadowOffset = NSSize(width: 0, height: -2)
      depth.set()
      PracticePalette.background.withAlphaComponent(0.90).setFill()
      outline.fill()
      NSGraphicsContext.restoreGraphicsState()
      if used {
        NSGradient(starting: color.withAlphaComponent(0.20), ending: color.withAlphaComponent(0.025))?
          .draw(in: outline, angle: 90)
      }
      color.withAlphaComponent(used ? 0.65 : 0.47).setStroke()
      outline.lineWidth = used ? 1.5 : 1
      outline.stroke()
      guard used, let hit = hits.last(where: { $0.pulse.pad == pad }) else { continue }
      let age = hit.progress * DrumxHitFeedback.duration
      // Brief physical contact is neutral. It is identical for matched, extra,
      // and hidden-feedback strikes, so this light never reveals a judgment.
      if age < 0.065 {
        NSColor.white.withAlphaComponent(0.22 * CGFloat(1 - age / 0.065)).setFill()
        outline.fill()
      }
      let envelope = CGFloat(max(0, 1 - age / 0.27))
      guard envelope > 0 else { continue }
      let strength = envelope * (0.65 + CGFloat(hit.pulse.velocity) * 0.35)
      var scaleX: CGFloat = 1, scaleY: CGFloat = 1
      if !reduceMotion {
        // A fast compression and small rebound acknowledge input without moving NOW.
        let compression = max(0, 1 - age / 0.07)
        let rebound = max(0, 1 - abs(age - 0.105) / 0.075)
        scaleX += CGFloat(0.035 * rebound - 0.015 * compression)
        scaleY += CGFloat(0.10 * rebound - 0.18 * compression)
      }
      let response = catcherPath(slot: slot, projection: projection,
                                 scaleX: scaleX, scaleY: scaleY)
      NSGraphicsContext.saveGraphicsState()
      let glow = NSShadow()
      glow.shadowColor = color.withAlphaComponent(0.48 * strength)
      glow.shadowBlurRadius = reduceMotion ? 6 : 11
      glow.shadowOffset = .zero
      glow.set()
      color.withAlphaComponent(0.25 * strength).setFill()
      response.fill()
      color.withAlphaComponent(0.94 * strength).setStroke()
      response.lineWidth = 1.8
      response.stroke()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  private func drawHitBursts(
    pads: [Int], projection: DrumxProjection, hits: [ActiveHit],
    reveal: Bool, reduceMotion: Bool
  ) {
    guard reveal else { return }
    for hit in hits where pads.contains(hit.pulse.pad) {
      guard hit.pulse.kind != .strike else { continue }
      let age = hit.progress * DrumxHitFeedback.duration
      let progress = CGFloat(age / 0.30)
      guard progress < 1 else { continue }
      let pad = hit.pulse.pad
      let lateral = pad == 2 ? 0 : projection.laneCenter(pad == 0 ? 0 : 2)
      let center = projection.project(lateral: lateral, beatDistance: 0)
      let x = CGFloat(center.x), y = CGFloat(center.y)
      let alpha = (1 - progress) * (0.65 + CGFloat(hit.pulse.velocity) * 0.35)
      let color = hit.pulse.kind == .extra ? PracticePalette.extra : PracticePalette.pads[pad]
      if pad == 2 {
        // A central kick burst would sit underneath the reserved middle tom.
        // Light the entire foot catcher and release energy at its outer tips.
        color.withAlphaComponent(0.78 * alpha).setStroke()
        let foot = catcherPath(slot: 7, projection: projection)
        foot.lineWidth = 2.2
        foot.stroke()
        if !reduceMotion {
          for side in [-1.0, 1.0] {
            let sign = CGFloat(side)
            let edge = x + sign * CGFloat(projection.nearWidth) * 0.505
            let rise: CGFloat = 7 + 22 * progress
            if hit.pulse.kind == .matched {
              line(NSPoint(x: edge, y: y - 4),
                   NSPoint(x: edge + sign * 4 * progress, y: y - rise),
                   color: color.withAlphaComponent(alpha), width: 2)
            } else {
              color.withAlphaComponent(alpha).setFill()
              polygon([
                NSPoint(x: edge + sign * 6 * progress, y: y - rise),
                NSPoint(x: edge + sign * (6 + 9 * progress), y: y - rise + 5),
                NSPoint(x: edge + sign * (2 + 6 * progress), y: y - rise + 10),
              ]).fill()
            }
          }
        }
        continue
      }
      if reduceMotion {
        // Static, local acknowledgement retains the distinction without motion.
        let slot = pad == 2 ? 7 : pad == 0 ? 0 : 2
        color.withAlphaComponent(0.70 * alpha).setStroke()
        let path = catcherPath(slot: slot, projection: projection)
        path.lineWidth = 2
        path.stroke()
      } else if hit.pulse.kind == .matched {
        let ringWidth: CGFloat = 42 + 35 * progress
        let ringHeight: CGFloat = 10 + 11 * progress
        let ring = NSBezierPath(ovalIn: NSRect(x: x - ringWidth / 2,
          y: y - ringHeight / 2, width: ringWidth, height: ringHeight))
        color.withAlphaComponent(0.46 * alpha).setStroke()
        ring.lineWidth = 1.25
        ring.stroke()
        for side in -1...1 {
          let dx = CGFloat(side) * (11 + 17 * progress)
          let rise: CGFloat = 9 + 28 * progress
          line(NSPoint(x: x + dx * 0.80, y: y - rise + 5),
               NSPoint(x: x + dx, y: y - rise - 2),
               color: color.withAlphaComponent(0.80 * alpha), width: 1.6)
        }
      } else {
        // An extra strike splits locally, never flashes or shakes the whole stage.
        let halfWidth: CGFloat = pad == 2 ? 25 : CGFloat(projection.nearWidth) * 0.40 / 7
        for side in [-1.0, 1.0] {
          let sign = CGFloat(side)
          let dx = halfWidth + 5 + 13 * progress
          let split = polygon([
            NSPoint(x: x + sign * dx, y: y - 5 - 7 * progress),
            NSPoint(x: x + sign * (dx + 5), y: y - 1 - 7 * progress),
            NSPoint(x: x + sign * (dx + 2), y: y + 3 - 7 * progress),
          ])
          color.withAlphaComponent(0.90 * alpha).setFill()
          split.fill()
        }
      }
    }
  }

  private func drawExtraLabels(projection: DrumxProjection, hits: [ActiveHit], reveal: Bool) {
    guard reveal else { return }
    for pad in 0..<2 {
      // Bursts remain per strike, but repeated extras never stack their text.
      guard let hit = hits.last(where: { $0.pulse.pad == pad && $0.pulse.kind == .extra }) else { continue }
      let alpha = CGFloat(min(1, (1 - hit.progress) * 2))
      let lateral = pad == 2 ? 0 : projection.laneCenter(pad == 0 ? 0 : 2)
      let center = projection.project(lateral: lateral, beatDistance: 0)
      let x = CGFloat(center.x), y = CGFloat(center.y) + 12
      PracticePalette.background.withAlphaComponent(0.96 * alpha).setFill()
      NSRect(x: x - 23, y: y, width: 46, height: 14).fill()
      text("EXTRA", x: x, y: y, size: 11,
           color: PracticePalette.extra.withAlphaComponent(alpha), alignment: .center, weight: .semibold)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    PracticePalette.background.setFill()
    bounds.fill()
    guard let c = controller, bounds.width > 200, bounds.height > 260 else { return }

    let now = DrumxIO.hostNowSeconds()
    let active = c.transportActive
    let demo = c.demonstrating
    let reveal = c.showLive && !demo
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let hits: [ActiveHit] = c.hitFeedback.pulses.compactMap { pulse in
      guard (0..<3).contains(pulse.pad), let progress = pulse.progress(at: now) else { return nil }
      return (pulse, progress)
    }
    let bpm = max(1, c.tempo)
    let duration = dx_core_duration(c.core)
    let rawTime = active ? now - c.practiceStart : (c.completed ? duration : 0)
    let songTime = rawTime
    let beat = songTime * bpm / 60
    let countIn = active && rawTime < 0
    let strictMemory = c.mode == 2 && !demo
    let fade = c.mode == 1 && !demo
    let inMemoryBar = active && !countIn && !demo
      && (strictMemory || (fade && Int(beat / 4) % 2 == 1))
    let top: CGFloat = 55
    let strike = max(top + 160, bounds.height - 193)
    let center = bounds.midX
    let nearWidth = min(870, bounds.width - 132)
    let look = 4 * 60 / bpm
    let projection = DrumxProjection(centerX: Double(center), nearWidth: Double(nearWidth),
                                    topY: Double(top), strikeY: Double(strike))
    let farWidth = nearWidth * CGFloat(projection.farScale)

    // Every instrument uses this same projection. No instrument-specific time axis.
    func depth(_ ahead: Double) -> CGFloat {
      let point = projection.project(lateral: 0, beatDistance: ahead * bpm / 60)
      return (CGFloat(point.y) - top) / (strike - top)
    }
    func yy(_ d: CGFloat) -> CGFloat { top + (strike - top) * d }
    func span(_ d: CGFloat) -> CGFloat { farWidth + (nearWidth - farWidth) * d }
    func slotX(_ slot: Int, _ d: CGFloat) -> CGFloat {
      center - span(d) / 2 + (CGFloat(slot) + 0.5) * span(d) / 7
    }
    func surface(_ far: CGFloat, _ near: CGFloat) -> NSBezierPath {
      polygon([
        NSPoint(x: center - span(far) / 2, y: yy(far)),
        NSPoint(x: center + span(far) / 2, y: yy(far)),
        NSPoint(x: center + span(near) / 2, y: yy(near)),
        NSPoint(x: center - span(near) / 2, y: yy(near)),
      ])
    }

    let title = demo ? "Listen to the groove" : countIn ? "Settle into the click"
      : inMemoryBar ? "From memory" : c.completed ? "Take complete" : c.lesson.title
    text(title, x: 28, y: 15, size: 15, color: PracticePalette.ink)
    let mode = demo ? "Demonstration" : c.modeNames[min(max(0, c.mode), c.modeNames.count - 1)]
    text("\(Int(bpm)) BPM  ·  \(mode)", x: bounds.width - 28, y: 18, alignment: .right)

    let road = surface(0, 1)
    NSGraphicsContext.saveGraphicsState()
    let roadShadow = NSShadow()
    roadShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    roadShadow.shadowBlurRadius = 18
    roadShadow.shadowOffset = NSSize(width: 0, height: -7)
    roadShadow.set()
    PracticePalette.far.setFill()
    road.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    road.addClip()
    NSGradient(starting: PracticePalette.far, ending: PracticePalette.near)?.draw(
      from: NSPoint(x: center, y: top), to: NSPoint(x: center, y: strike), options: [])
    NSGraphicsContext.restoreGraphicsState()

    // All seven slots exist from the first lesson. Quiet slots retain full width.
    for slot in [1, 3, 4, 5, 6] {
      PracticePalette.background.withAlphaComponent(0.33).setFill()
      polygon([
        NSPoint(x: center - farWidth / 2 + CGFloat(slot) * farWidth / 7, y: top),
        NSPoint(x: center - farWidth / 2 + CGFloat(slot + 1) * farWidth / 7, y: top),
        NSPoint(x: center - nearWidth / 2 + CGFloat(slot + 1) * nearWidth / 7, y: strike),
        NSPoint(x: center - nearWidth / 2 + CGFloat(slot) * nearWidth / 7, y: strike),
      ]).fill()
    }

    if strictMemory {
      PracticePalette.memory.withAlphaComponent(0.075).setFill()
      road.fill()
    } else if fade {
      for bar in stride(from: 1, to: max(1, c.lessonBars), by: 2) {
        let start = Double(bar * 4) * 60 / bpm
        let end = start + look
        let near = max(0, start - songTime)
        let far = min(look, end - songTime)
        guard far > near, near < look, far > 0 else { continue }
        let dFar = depth(far), dNear = depth(near)
        PracticePalette.memory.withAlphaComponent(0.115).setFill()
        surface(dFar, dNear).fill()
        if yy(dNear) - yy(dFar) > 40 {
          text("FROM MEMORY", x: center, y: (yy(dNear) + yy(dFar)) / 2 - 7,
               color: PracticePalette.memory, alignment: .center)
        }
      }
    }
    for slot in 0...7 {
      line(
        NSPoint(x: center - farWidth / 2 + CGFloat(slot) * farWidth / 7, y: top),
        NSPoint(x: center - nearWidth / 2 + CGFloat(slot) * nearWidth / 7, y: strike),
        color: PracticePalette.line.withAlphaComponent(slot == 0 || slot == 7 ? 0.72 : 0.44),
        width: slot == 0 || slot == 7 ? 1 : 0.7)
    }
    if !strictMemory {
      for i in 0...(max(1, c.lessonBars) * 4) {
        let ahead = Double(i) * 60 / bpm - songTime
        guard ahead >= 0, ahead <= look else { continue }
        let d = depth(ahead), y = yy(d), width = span(d)
        line(NSPoint(x: center - width / 2, y: y), NSPoint(x: center + width / 2, y: y),
             color: PracticePalette.line.withAlphaComponent(i % 4 == 0 ? 0.82 : 0.51),
             width: i % 4 == 0 ? 1.25 : 0.65)
        if i < c.lessonBars * 4 {
          text(String(i % 4 + 1), x: center - width / 2 - 17, y: y - 7,
               color: PracticePalette.muted.withAlphaComponent(0.76), alignment: .center)
        }
      }
    } else if !countIn {
      text("FROM MEMORY", x: center, y: top + (strike - top) * 0.44,
           size: 13, color: PracticePalette.memory, alignment: .center)
    }

    // The lower edge is depth decoration. The bright top edge is the only NOW line.
    PracticePalette.line.withAlphaComponent(0.48).setFill()
    polygon([
      NSPoint(x: center - nearWidth / 2, y: strike), NSPoint(x: center + nearWidth / 2, y: strike),
      NSPoint(x: center + nearWidth / 2 - 8, y: strike + 7), NSPoint(x: center - nearWidth / 2 + 8, y: strike + 7),
    ]).fill()
    line(NSPoint(x: center - nearWidth / 2, y: strike), NSPoint(x: center + nearWidth / 2, y: strike),
         color: PracticePalette.ink.withAlphaComponent(0.78), width: 1.5)
    text("NOW", x: center - nearWidth / 2 - 32, y: strike - 7, alignment: .center)

    // The complete foot layer sits behind hand catchers and all hand notes.
    drawCatchers(slots: [7], projection: projection, hits: hits, reduceMotion: reduceMotion)
    for renderPad in [2, 0, 1] {
      if renderPad == 0 {
        drawHitBursts(pads: [2], projection: projection, hits: hits,
                      reveal: reveal, reduceMotion: reduceMotion)
        drawCatchers(slots: Array(0..<7), projection: projection, hits: hits, reduceMotion: reduceMotion)
      }
      if !strictMemory {
        for index in 0..<dx_core_event_count(c.core) {
          var event = DXEvent()
          guard dx_core_event(c.core, index, &event) == 1, event.pad == renderPad else { continue }
          // Only revealed matches consume a target. Memory and demonstrations stay ungraded.
          if reveal && event.hit == 1 { continue }
          let ahead = event.time_seconds - songTime
          guard ahead >= -0.015, ahead <= look else { continue }
          if fade && Int((event.time_seconds * bpm / 60 + 0.000001) / 4) % 2 == 1 { continue }
          let beatDistance = DrumxProjection.beatDistance(
            eventTimeSeconds: event.time_seconds, timelineSeconds: songTime, bpm: bpm)
          let pad = Int(event.pad)
          let lateral = pad == 2 ? 0 : projection.laneCenter(pad == 0 ? 0 : 2)
          let noteCenter = projection.project(lateral: lateral, beatDistance: beatDistance)
          let x = CGFloat(noteCenter.x), y = CGFloat(noteCenter.y)
          let alpha = CGFloat(projection.farVisibility(at: beatDistance))
          let color = PracticePalette.pads[pad].withAlphaComponent(alpha)
          color.setFill()
          if pad == 2 {
            let vertices = projection.rectangle(centerLateral: 0, beatDistance: beatDistance,
                                                worldWidth: 0.99, worldDepth: 0.04)
            polygon(vertices.map { NSPoint(x: $0.x, y: $0.y) }).fill()
          } else {
            let vertices = pad == 0
              ? projection.cymbal(centerLateral: lateral, beatDistance: beatDistance,
                                   worldWidth: 0.66 / 7, worldDepth: 0.12)
              : projection.drum(centerLateral: lateral, beatDistance: beatDistance,
                                 worldWidth: 0.66 / 7, worldDepth: 0.12)
            let note = polygon(vertices.map { NSPoint(x: $0.x, y: $0.y) })
            let width = note.bounds.width, height = note.bounds.height
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18 * alpha)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            note.fill()
            NSGraphicsContext.restoreGraphicsState()
            if pad == 0 && !c.showHands {
              let a = projection.project(lateral: lateral - 0.022, beatDistance: beatDistance + 0.015)
              let b = projection.project(lateral: lateral + 0.022, beatDistance: beatDistance + 0.015)
              line(NSPoint(x: a.x, y: a.y), NSPoint(x: b.x, y: b.y),
                   color: PracticePalette.background.withAlphaComponent(0.25 * alpha), width: 1)
            }
            // Sticking text is a screen-space teaching annotation, not note geometry.
            if c.showHands && width >= 24 && height >= 13,
               let hand = c.handHint(pad: pad, seconds: event.time_seconds) {
              text(hand, x: x, y: y - 7, size: 11,
                   color: PracticePalette.background.withAlphaComponent(alpha), alignment: .center)
            }
          }
        }
      }
    }
    drawHitBursts(pads: [0, 1], projection: projection, hits: hits,
                  reveal: reveal, reduceMotion: reduceMotion)

    // Feather the whole far surface as one scene, so its rail edges, grid and
    // notes dissolve into the same atmosphere without changing their geometry.
    let featherHeight = max(38, (strike - top) * 0.18)
    PracticePalette.background.setFill()
    NSRect(x: 0, y: top - 14, width: bounds.width, height: 14).fill()
    NSGraphicsContext.saveGraphicsState()
    NSRect(x: 0, y: top, width: bounds.width, height: featherHeight).clip()
    NSGradient(starting: PracticePalette.background,
               ending: PracticePalette.background.withAlphaComponent(0))?.draw(
      from: NSPoint(x: center, y: top),
      to: NSPoint(x: center, y: top + featherHeight), options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Static silhouettes below NOW explain the kit. They are never timed destinations.
    let names = ["HI-HAT", "CRASH", "SNARE", "TOM 1", "TOM 2", "FLOOR", "RIDE"]
    for slot in 0..<7 {
      let cymbal = [0, 1, 6].contains(slot)
      let used = slot == 0 || slot == 2
      let color = used ? (slot == 0 ? PracticePalette.hat : PracticePalette.snare) : PracticePalette.quiet
      let x = slotX(slot, 1), cy = strike + (cymbal ? 29 : 43)
      let radius = min(29, nearWidth / 7 * 0.29), ry: CGFloat = cymbal ? 4.5 : 10
      line(NSPoint(x: x, y: strike + 9), NSPoint(x: x, y: cy - ry - 3),
           color: PracticePalette.line.withAlphaComponent(used ? 0.75 : 0.36), width: 0.8)
      let oval = NSBezierPath(ovalIn: NSRect(x: x - radius, y: cy - ry, width: radius * 2, height: ry * 2))
      PracticePalette.background.setFill()
      oval.fill()
      color.withAlphaComponent(used ? 0.78 : 0.62).setStroke()
      oval.lineWidth = 1.1
      oval.stroke()
      if cymbal {
        color.withAlphaComponent(0.6).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3.5, y: cy - 1.4, width: 7, height: 2.8)).fill()
      } else {
        color.withAlphaComponent(0.22).setStroke()
        NSBezierPath(ovalIn: NSRect(x: x - radius + 4, y: cy - ry + 3,
                                   width: radius * 2 - 8, height: ry * 2 - 6)).stroke()
      }
      text(names[slot], x: x, y: cy + ry + 8,
           color: used ? PracticePalette.ink : PracticePalette.muted.withAlphaComponent(0.78), alignment: .center)
    }
    PracticePalette.kick.withAlphaComponent(0.36).setFill()
    NSBezierPath(roundedRect: NSRect(x: center - nearWidth * 0.20, y: strike + 76,
                                   width: nearWidth * 0.40, height: 2), xRadius: 1, yRadius: 1).fill()
    let extraKick = reveal && hits.contains { $0.pulse.pad == 2 && $0.pulse.kind == .extra }
    text(extraKick ? "KICK · EXTRA" : "KICK · FOOT", x: center, y: strike + 82,
         color: extraKick ? PracticePalette.extra : PracticePalette.kick, alignment: .center)
    drawExtraLabels(projection: projection, hits: hits, reveal: reveal)

    if countIn {
      let count = min(4, max(1, Int((now - c.clickStart) * bpm / 60) + 1))
      text(String(count), x: center, y: top + (strike - top) * 0.32 - 20,
           size: 68, color: PracticePalette.ink, alignment: .center, weight: .regular)
    }
    if demo {
      text("LISTEN · DEMONSTRATION IS NOT SCORED", x: center, y: strike + 139, alignment: .center)
    } else if c.showLive || !active {
      drawTiming(controller: c, center: center, top: strike + 112)
    } else {
      text("Timing feedback after the phrase", x: center, y: strike + 139, alignment: .center)
    }
  }

  private func drawTiming(controller c: LabController, center: CGFloat, top: CGFloat) {
    let left = center - 132, right = center + 132
    text("EARLY", x: left, y: top)
    text("ON TIME", x: center, y: top, alignment: .center)
    text("LATE", x: right, y: top, alignment: .right)
    let biases = [c.snapshot.bias.0, c.snapshot.bias.1, c.snapshot.bias.2]
    let names = ["Hi-hat", "Snare", "Kick"]
    for pad in 0..<3 {
      let bias = biases[pad], row = top + 25 + CGFloat(pad) * 20
      text(names[pad], x: left - 20, y: row - 7, color: PracticePalette.pads[pad], alignment: .right)
      line(NSPoint(x: left, y: row), NSPoint(x: right, y: row), color: PracticePalette.line.withAlphaComponent(0.65), width: 0.7)
      line(NSPoint(x: center, y: row - 4), NSPoint(x: center, y: row + 4), color: PracticePalette.muted.withAlphaComponent(0.5), width: 0.8)
      if bias.sample_count >= 4 && bias.state != 5 {
        let x = center + CGFloat(min(80, max(-80, bias.offset_ms))) / 80 * 132
        PracticePalette.pads[pad].setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3, y: row - 3, width: 6, height: 6)).fill()
      }
      let label: String
      switch bias.state {
      case 0: label = "\(bias.sample_count)/4 hits"
      case 4: label = "Uneven timing"
      case 5: label = "Waiting for hits"
      default: label = String(format: "%+.0f ms", bias.offset_ms)
      }
      text(label, x: right + 18, y: row - 7)
    }
  }
}
