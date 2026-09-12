import AppKit

// This isolated page-layout fixture needs only NSButton's frame and visibility
// contract. Production LessonButton drawing belongs to the app's visual gate.
typealias LessonButton = NSButton
private var checks = 0
private func check(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !value() { fatalError("FAIL: \(message)") }
}
private final class ActionProbe: NSObject {
  var count = 0
  @objc func changed(_ sender: Any?) { count += 1 }
}

@main enum DrumxSettingsControlChecks {
  static func main() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let probe = ActionProbe()
    let slider = DrumxSlider(value: 0.7, minValue: 0, maxValue: 1, target: probe, action: #selector(ActionProbe.changed(_:)))
    let value = NSTextField(labelWithString: "")
    slider.attachValueLabel(value) { "\(Int(($0 * 100).rounded()))%" }
    check(value.stringValue == "70%" && slider.accessibilityValueDescription() == "70%", "volume units are visible and accessible")
    slider.doubleValue = 0.25
    check(value.stringValue == "25%" && probe.count == 0, "restoring a value updates its label without producing a user action")
    slider.cell?.doubleValue = 0.5
    _ = slider.sendAction(slider.action, to: slider.target)
    check(value.stringValue == "50%" && probe.count == 1, "native cell tracking refreshes units and sends exactly one action")
    let toggle = DrumxToggle(checkboxWithTitle: "Drumx sounds", target: probe, action: #selector(ActionProbe.changed(_:)))
    toggle.state = .off; toggle.performClick(nil)
    check(toggle.state == .on && probe.count == 2, "branded toggle retains native switch state and action")
    toggle.performClick(nil)
    check(toggle.state == .off && probe.count == 3, "second activation turns the toggle off")
    toggle.isEnabled = false; toggle.performClick(nil)
    check(toggle.state == .off && probe.count == 3, "disabled toggle cannot change state or send actions")
    let source = DrumxPopUpButton()
    source.addItems(withTitles: ["Keyboard", "A long named MIDI input"])
    source.item(at: 1)?.representedObject = 42
    source.selectItem(at: 1)
    check(source.indexOfSelectedItem == 1 && source.selectedItem?.representedObject as? Int == 42, "branded popup retains native selection and source identity")
    let field = NSTextField(string: "-25")
    field.cell = DrumxTextFieldCell(textCell: field.stringValue)
    field.target = probe; field.action = #selector(ActionProbe.changed(_:))
    check(field.stringValue == "-25" && field.isEditable && field.isSelectable, "offset cell preserves its signed value and native editability")
    field.stringValue = "+14"
    _ = field.sendAction(field.action, to: field.target)
    check(field.stringValue == "+14" && probe.count == 4, "offset cell preserves the commit target and action")

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620), styleMask: [.borderless], backing: .buffered, defer: false)
    // Never order or activate this window. It exists only for AppKit layout.
    let page = DrumxSettingsPage()
    window.contentView = page
    let panels = (0..<4).map { index -> NSView in
      let panel = NSView()
      panel.heightAnchor.constraint(greaterThanOrEqualToConstant: index == 3 ? 720 : 430).isActive = true
      panel.isHidden = index != 0
      return panel
    }
    let tabs = ["Your kit", "Sound", "Playing", "Players"].map { NSButton(title: $0, target: nil, action: nil) }
    page.install(tabs: tabs, panels: panels)
    page.layoutSubtreeIfNeeded()
    guard let scroll = page.subviews.compactMap({ $0 as? NSScrollView }).first else { fatalError("missing settings viewport") }
    check(page.bounds.contains(scroll.frame), "minimum-size content viewport remains inside the settings page")
    check(zip(tabs, tabs.dropFirst()).allSatisfy { $0.frame.maxX < $1.frame.minX }, "four broad tabs do not overlap")
    check(tabs.allSatisfy { page.bounds.contains($0.frame) }, "all section actions fit at minimum app width")
    panels[0].isHidden = true; panels[3].isHidden = false
    page.revealSelectedSection(); page.layoutSubtreeIfNeeded()
    check((scroll.documentView?.frame.height ?? 0) >= 720, "tall content retains its full height instead of clipping controls")
    check(scroll.contentSize.height < (scroll.documentView?.frame.height ?? 0), "overflow remains scrollable below fixed settings navigation")
    panels[3].isHidden = true; panels[0].isHidden = false
    page.revealSelectedSection(); page.layoutSubtreeIfNeeded()
    check(panels[3].isHiddenOrHasHiddenAncestor && !panels[0].isHiddenOrHasHiddenAncestor, "inactive sections remain hidden from pointer and keyboard interaction")

    let kit = DrumxKitCheckView(frame: NSRect(x: 0, y: 0, width: 430, height: 460))
    kit.layoutSubtreeIfNeeded()
    let pads = kit.subviews.compactMap { $0 as? NSButton }
    check(pads.count == 3 && pads.allSatisfy { kit.bounds.contains($0.frame) }, "all supported kit controls retain bounded hit targets")
    kit.selectedPad = 2
    check((pads[2].accessibilityValue() as? String)?.contains("Selected") == true, "pad selection is exposed independently of colour")
    kit.showHit(pad: nil, velocity: 90, description: "MIDI 49 · unmapped")
    let signal = kit.subviews.compactMap { $0 as? NSTextField }.first!
    check(signal.accessibilityLabel()?.contains("Velocity 90") == true
      && signal.accessibilityValue()?.contains("MIDI 49") == true, "raw unmapped signal and velocity are accessible")
    kit.showHit(pad: 12, velocity: 999, description: "Unexpected input")
    check(kit.lastPad == nil && kit.lastVelocity == 127, "invalid input cannot index beyond the diagram or overrun its meter")
    kit.clearSignal()
    check(kit.lastPad == nil && kit.lastVelocity == 0 && signal.stringValue.contains("Strike a pad"), "disconnect reset clears both visible and accessible signal state")
    print("Drumx native settings/control contracts: \(checks) checks passed without a visible window.")
  }
}
