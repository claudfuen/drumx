import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private func navigationChecks() {
  let menu = DrumxMenuInput()
  check(menu.receive(pad: 0, velocity: 100, at: 100) == nil, "helper is inactive until page/source reset")
  menu.reset(at: 1)
  check(menu.receive(pad: 0, velocity: 100, at: 1.749) == nil, "last musical hits are ignored during page-entry guard")
  check(menu.receive(pad: 0, velocity: 100, at: 1.75) == .previous, "hi-hat navigates previous after entry guard")
  check(menu.receive(pad: 1, velocity: 100, at: 1.949) == nil, "navigation debounce covers alternating pads")
  check(menu.receive(pad: 1, velocity: 100, at: 1.95) == .next, "snare navigates next at debounce boundary")
  check(menu.receive(pad: 0, velocity: 31, at: 2.15) == nil, "soft ghost note cannot navigate")
  check(menu.receive(pad: 0, velocity: 32, at: 2.15) == .previous, "minimum intentional velocity accepted")
  check(menu.receive(pad: 1, velocity: 100, at: 2.0) == nil, "out-of-order queued hit cannot navigate")
  menu.reset(at: 3)
  check(menu.receive(pad: 2, velocity: 100, at: 2.9) == nil && !menu.isKickArmed(at: 3),
        "old capture time cannot arm a newly entered page")
  check(menu.receive(pad: 1, velocity: 100, at: 3.75) == .next, "page reset gives a new navigation state")
}

private func confirmationChecks() {
  let menu = DrumxMenuInput()
  menu.reset(at: 0)
  check(menu.receive(pad: 2, velocity: 100, at: 1) == nil && menu.isKickArmed(at: 1),
        "one kick arms confirmation without activating")
  check(menu.receive(pad: 2, velocity: 100, at: 1) == nil, "duplicate same-time kick cannot activate")
  check(menu.receive(pad: 2, velocity: 100, at: 1.079) == nil, "near-duplicate kick stays below minimum separation")
  check(menu.receive(pad: 2, velocity: 100, at: 1.08) == .activate, "second distinct kick confirms")
  check(!menu.isKickArmed(at: 1.08), "activation clears its confirmation state")
  check(menu.receive(pad: 2, velocity: 100, at: 1.20) == nil && !menu.isKickArmed(at: 1.20),
        "kick during cooldown cannot arm an accidental repeat")
  check(menu.receive(pad: 0, velocity: 100, at: 1.30) == .previous,
        "activation cooldown does not unnecessarily block ordinary navigation")
  check(menu.receive(pad: 2, velocity: 100, at: 1.98) == nil && menu.isKickArmed(at: 1.98),
        "a new confirmation can arm after activation cooldown")
  check(menu.receive(pad: 2, velocity: 100, at: 2.58) == .activate, "600ms confirmation boundary is accepted")
  menu.reset(at: 2.58)
  check(menu.receive(pad: 2, velocity: 100, at: 3.33) == nil && !menu.isKickArmed(at: 3.33),
        "new page guard does not shorten the 900ms activation cooldown")
  check(menu.receive(pad: 2, velocity: 100, at: 3.48) == nil && menu.isKickArmed(at: 3.48),
        "fresh page can arm after both timing protections")

  let expiring = DrumxMenuInput()
  expiring.reset(at: 0)
  _ = expiring.receive(pad: 2, velocity: 100, at: 1)
  check(!expiring.isKickArmed(at: 1.601), "armed indication expires after confirmation window")
  check(expiring.receive(pad: 2, velocity: 100, at: 1.601) == nil && expiring.isKickArmed(at: 1.601),
        "late second kick starts a new pair rather than activating")
  check(expiring.receive(pad: 2, velocity: 100, at: 1.8) == .activate, "new pair can confirm normally")
}

private func cancellationAndValidationChecks() {
  let menu = DrumxMenuInput()
  menu.reset(at: 0)
  _ = menu.receive(pad: 2, velocity: 100, at: 1)
  check(menu.receive(pad: 1, velocity: 100, at: 1.1) == .next && !menu.isKickArmed(at: 1.1),
        "changing selection cancels the previous kick confirmation")
  check(menu.receive(pad: 2, velocity: 100, at: 1.2) == nil, "kick after navigation is only a first kick")
  menu.reset(at: 1.3)
  check(!menu.isKickArmed(at: 1.3), "page/source reset cancels pending confirmation")
  check(menu.receive(pad: 2, velocity: 100, at: 2.05) == nil, "source reset requires a new pair")
  for (pad, velocity, time) in [(-1, 100, 2.2), (3, 100, 2.2), (2, 0, 2.2),
                                 (2, 31, 2.2), (2, 128, 2.2), (2, 100, -1),
                                 (2, 100, Double.nan), (2, 100, Double.infinity)] {
    check(menu.receive(pad: pad, velocity: velocity, at: time) == nil, "invalid or soft event cannot emit menu command")
  }
  check(menu.isKickArmed(at: 2.2), "rejected non-strikes do not count as a second kick")
  menu.reset(at: .nan)
  check(menu.receive(pad: 0, velocity: 100, at: 5) == nil && !menu.isKickArmed(at: 5),
        "invalid reset disables commands safely")
  menu.reset(at: 6)
  check(menu.receive(pad: 1, velocity: 100, at: 6.75) == .next, "valid reset recovers from invalid time")
}

@main enum DrumxMenuInputChecks {
  static func main() {
    navigationChecks(); confirmationChecks(); cancellationAndValidationChecks()
    print("Drumx opt-in MIDI menu input: \(checks) checks passed.")
  }
}
