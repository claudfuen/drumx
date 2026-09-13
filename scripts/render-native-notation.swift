// Bitmap-only views; no application, window, device, or player history.
import AppKit

@main struct RenderNativeNotation {
  static func main() throws {
    let width = 960, height = 710
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2,
      pixelsHigh: height * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: CGFloat(height)); flip.scaleX(by: 1, yBy: -1); flip.concat()
    NSColor(calibratedRed: 0.055, green: 0.076, blue: 0.082, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let ids = ["double-stroke-open-roll", "single-paradiddle", "foot-under-paradiddle"]
    for (index, id) in ids.enumerated() {
      let lesson = DrumxCourse.lessons.first { $0.id == id }!
      let y = CGFloat(index * 230)
      (lesson.title as NSString).draw(at: NSPoint(x: 40, y: y + 12), withAttributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white])
      let view = DrumxNotationView(frame: NSRect(x: 0, y: 0, width: 880, height: 172))
      view.lesson = lesson
      NSGraphicsContext.saveGraphicsState()
      let placement = NSAffineTransform(); placement.translateX(by: 40, yBy: y + 44); placement.concat()
      view.draw(view.bounds)
      NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/native-curriculum-notation.png"))
  }
}
