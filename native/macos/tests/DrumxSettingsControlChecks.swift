import AppKit

// This isolated page-layout fixture needs only NSButton's frame and visibility
// contract. Production LessonButton drawing belongs to the app's visual gate.
typealias LessonButton = NSButton
// Course UI only compares this stable identity; tempo evaluation has its own suite.
enum DrumxTempoCoach { static let lessonVersion = "find-the-pulse-v1" }
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
    let course = DrumxCourseMenuView(frame: NSRect(x: 0, y: 0, width: 980, height: 540))
    window.contentView = course
    var launches = 0
    course.onSelect = { _ in launches += 1 }
    func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func updateCourse(_ index: Int) {
      let lesson = DrumxCourse.lessons[index]
      course.update(lesson: lesson, player: "Fixture", statuses: [:], practised: 0,
        availability: Set(DrumxCourse.lessons.map(\.id)), recommendedID: lesson.id)
      course.layoutSubtreeIfNeeded()
    }
    func visibleNodes() -> [NSButton] {
      descendants(course).compactMap { $0 as? NSButton }.filter {
        Int($0.title) != nil && !$0.isHiddenOrHasHiddenAncestor
      }
    }
    updateCourse(0)
    check(visibleNodes().count == 12, "first course page exposes three readable four-step chapters")
    let courseButtons = descendants(course).compactMap { $0 as? NSButton }
    let next = courseButtons.first { $0.title == "Next" }!
    let previous = courseButtons.first { $0.title == "Previous" }!
    check(!previous.isEnabled && next.isEnabled, "chapter paging has explicit beginning boundary")
    next.performClick(nil); course.layoutSubtreeIfNeeded()
    check(visibleNodes().map(\.title) == (13...20).map { String(format: "%02d", $0) },
      "next page shows later chapters without shrinking all twenty steps")
    check(previous.isEnabled && !next.isEnabled && launches == 0, "chapter inspection never starts a lesson and respects final page")
    previous.performClick(nil); course.layoutSubtreeIfNeeded()
    check(visibleNodes().first?.title == "01", "previous chapters return to the first page")
    updateCourse(DrumxCourse.lessons.count - 1)
    check(visibleNodes().last?.title == "20", "resuming a later lesson reveals its chapter automatically")
    let left = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!
    let thirteenth = courseButtons.first { $0.title == "13" }!
    thirteenth.keyDown(with: left); course.layoutSubtreeIfNeeded()
    check(visibleNodes().last?.title == "12" && launches == 0, "left arrow crosses the chapter page boundary without launching")
    for size in [NSSize(width: 980, height: 540), NSSize(width: 1440, height: 780), NSSize(width: 1840, height: 1180)] {
      course.setFrameSize(size); course.layoutSubtreeIfNeeded()
      for node in visibleNodes() {
        check(node.frame.width >= 44 && node.frame.height >= 44, "course steps keep useful target sizes across supported viewports")
        check(course.bounds.contains(course.convert(node.bounds, from: node)), "visible course steps remain inside their viewport")
      }
    }
    print("Drumx native settings/control contracts: \(checks) checks passed without a visible window.")
  }
}
