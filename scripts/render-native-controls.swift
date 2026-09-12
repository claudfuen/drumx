// Bitmap-only component fixture. This never creates NSApplication or a window.
// From the repository root, compile with DrumxControls.swift and
// DrumxSettingsViews.swift, then run the binary. Output is
// .build/native-polish-controls.png; no player data is read.
import AppKit
// Only page geometry uses this placeholder; every rendered control is a real
// Drumx control, field cell or kit component. There is no app or window here.
typealias LessonButton = NSButton

@main struct RenderNativePolish {
  static func label(_ text: String, frame: NSRect, size: CGFloat = 14, color: NSColor = .white) -> NSTextField {
    let value = NSTextField(labelWithString: text)
    value.font = .systemFont(ofSize: size, weight: .medium)
    value.textColor = color; value.frame = frame
    return value
  }
  static func drawTree(_ view: NSView, in context: CGContext) {
    guard !view.isHidden else { return }
    context.saveGState()
    context.translateBy(x: view.frame.minX, y: view.frame.minY)
    if !view.isFlipped { context.translateBy(x: 0, y: view.frame.height); context.scaleBy(x: 1, y: -1) }
    let old = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: view.isFlipped)
    view.draw(view.bounds)
    // All component children use their parent's logical orientation.
    for child in view.subviews {
      context.saveGState()
      if !view.isFlipped { context.translateBy(x: 0, y: view.bounds.height); context.scaleBy(x: 1, y: -1) }
      drawTree(child, in: context)
      context.restoreGState()
    }
    NSGraphicsContext.current = old
    context.restoreGState()
  }
  static func main() throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1300,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1000, height: 650)
    let bitmap = NSGraphicsContext(bitmapImageRep: rep)!
    let context = bitmap.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: 650); transform.scaleX(by: 1, yBy: -1); transform.concat()
    NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1000, height: 650).fill()
    var views: [NSView] = [
      label("Native controls, refined.", frame: NSRect(x: 40, y: 32, width: 900, height: 48), size: 30),
      label("Bitmap-only component evidence. No app window or live interaction.", frame: NSRect(x: 40, y: 82, width: 900, height: 22), size: 13, color: .lightGray),
      label("DRUMS & DEMONSTRATIONS", frame: NSRect(x: 48, y: 145, width: 400, height: 20), size: 11, color: .lightGray),
    ]
    let slider = DrumxSlider(value: 0.7, minValue: 0, maxValue: 1, target: nil, action: nil)
    slider.frame = NSRect(x: 48, y: 178, width: 280, height: 36)
    let value = label("", frame: NSRect(x: 348, y: 184, width: 70, height: 25), size: 15)
    slider.attachValueLabel(value) { "\(Int(($0 * 100).rounded()))%" }
    views += [slider, value]
    for (index, state) in [NSControl.StateValue.on, .off, .off].enumerated() {
      let toggle = DrumxToggle(checkboxWithTitle: index == 2 ? "Disabled-state fixture" : index == 0 ? "Drumx drum sounds" : "Sticking hints", target: nil, action: nil)
      toggle.frame = NSRect(x: 48, y: 240 + CGFloat(index) * 47, width: 350, height: 32)
      toggle.state = state; toggle.isEnabled = index != 2
      toggle.font = .systemFont(ofSize: 13, weight: .medium); views.append(toggle)
    }
    views.append(label("INPUT SCORING OFFSET", frame: NSRect(x: 48, y: 402, width: 350, height: 20), size: 11, color: .lightGray))
    let offset = NSTextField(string: "-12"); offset.cell = DrumxTextFieldCell(textCell: offset.stringValue)
    offset.frame = NSRect(x: 48, y: 433, width: 86, height: 38)
    views += [offset, label("ms", frame: NSRect(x: 145, y: 443, width: 80, height: 22), color: .lightGray)]
    let source = DrumxPopUpButton()
    source.addItems(withTitles: ["Keyboard / no MIDI input", "Example MIDI drum module"])
    source.selectItem(at: 1); source.font = .systemFont(ofSize: 14, weight: .medium)
    source.frame = NSRect(x: 48, y: 516, width: 375, height: 38); views.append(source)
    let kit = DrumxKitCheckView(frame: NSRect(x: 490, y: 126, width: 470, height: 462))
    kit.selectedPad = 1; kit.confirmed = [0, 1]
    kit.showHit(pad: 1, velocity: 104, description: "MIDI 38 · Snare · velocity 104")
    kit.layoutSubtreeIfNeeded(); views.append(kit)
    let appearance = NSAppearance(named: .darkAqua)!
    appearance.performAsCurrentDrawingAppearance { for view in views { drawTree(view, in: context) } }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/native-polish-controls.png"))

    let page = DrumxSettingsPage(frame: NSRect(x: 0, y: 0, width: 980, height: 620))
    let panels = [NSView(), NSView()]
    panels[0].heightAnchor.constraint(greaterThanOrEqualToConstant: 430).isActive = true
    panels[1].heightAnchor.constraint(greaterThanOrEqualToConstant: 720).isActive = true
    panels[1].isHidden = true
    page.install(tabs: [NSButton(title: "Kit", target: nil, action: nil), NSButton(title: "Players", target: nil, action: nil)], panels: panels)
    page.layoutSubtreeIfNeeded()
    let scroll = page.subviews.compactMap { $0 as? NSScrollView }.first!
    print("Bitmap created; compact document \(scroll.documentView!.frame.height), viewport \(scroll.contentSize.height).")
    panels[0].isHidden = true; panels[1].isHidden = false; page.revealSelectedSection(); page.layoutSubtreeIfNeeded()
    print("Tall document \(scroll.documentView!.frame.height), viewport \(scroll.contentSize.height).")
    panels[1].isHidden = true; panels[0].isHidden = false; page.revealSelectedSection(); page.layoutSubtreeIfNeeded()
    print("Returned document \(scroll.documentView!.frame.height), viewport \(scroll.contentSize.height).")
  }
}
