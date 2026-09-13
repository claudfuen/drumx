// Reproducible image fixtures from the shipping PracticeView and scoring core.
// This small controller supplies scripted input only. It never opens a window,
// starts audio/MIDI, or reads/writes a player's progress.
import AppKit

enum DrumxIO { static func hostNowSeconds() -> Double { 1000 } }

final class LabController {
  let core = dx_core_create()!
  let lesson = DrumxCourse.lesson(id: "first-backbeat")!
  let tempo = 72.0
  let lessonBars = 16
  let modeNames = ["Guided notes", "Hide a phrase", "From memory"]
  let demonstrating = false, completed = false, transportActive = true, showHands = true
  var showLive = true
  var mode = 0
  var snapshot = DXSnapshot()
  var hitFeedback = DrumxHitFeedback()
  var practiceStart = 0.0
  var clickStart: Double { practiceStart - 240 / tempo }

  init(mode: Int) {
    self.mode = mode
    // Capture just after a simultaneous hi-hat/snare attack in bar six.
    let songTime = 25 * 60 / tempo + 0.09
    practiceStart = DrumxIO.hostNowSeconds() - songTime
    let notes = (0..<lessonBars).flatMap { bar in
      lesson.events.map { DXChartEvent(pad: Int32($0.pad), beat: $0.beat + Double(bar * 4)) }
    }
    precondition(notes.withUnsafeBufferPointer {
      dx_core_load_chart(core, tempo, Double(lessonBars * 4), $0.baseAddress, Int32($0.count))
    } == 1)
    dx_core_set_guidance(core, Int32(mode))
    for note in notes {
      let at = note.beat * 60 / tempo + [0.008, 0.016, -0.005][Int(note.pad)]
      if at > songTime { continue }
      let result = dx_core_input(core, note.pad, at, 0.82)
      hitFeedback.record(pad: Int(note.pad), judgment: Int(result.judgment), velocity: 0.82,
        offsetMS: result.offset_ms, at: practiceStart + at, revealJudgment: true)
    }
    dx_core_advance(core, songTime)
    dx_core_snapshot(core, &snapshot)
  }
  deinit { dx_core_destroy(core) }
  func dismissOrStop() {}
  func keyboardHit(pad: Int, velocity: Int, hostTime: Double) {}
  func handHint(pad: Int, seconds: Double) -> String? {
    let beat = (seconds * tempo / 60).truncatingRemainder(dividingBy: 4)
    return lesson.events.first { $0.pad == pad && abs($0.beat - beat) < 0.00001 }?.hand
  }
}

@main struct RenderNativeGameplay {
  static func main() throws {
    for mode in [0, 1] {
      let controller = LabController(mode: mode)
      let view = PracticeView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
      view.controller = controller
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 900,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      let context = NSGraphicsContext(bitmapImageRep: bitmap)!
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
      let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: 900); flip.scaleX(by: 1, yBy: -1); flip.concat()
      view.draw(view.bounds)
      NSGraphicsContext.restoreGraphicsState()
      let name = mode == 0 ? "gameplay-highway" : "gameplay-memory"
      try bitmap.representation(using: .png, properties: [:])!.write(to:
        URL(fileURLWithPath: "docs/images/\(name).png"))
    }
  }
}
