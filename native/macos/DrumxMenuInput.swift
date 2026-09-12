import Foundation

enum DrumxMenuCommand: Equatable {
  case previous
  case next
  case activate
}

/// The controller must opt in and call only on eligible menu pages, never while
/// playing, mapping, or using keyboard mode. Reset on every page/source change.
/// Host timestamps are input capture times so a queued musical hit stays stale.
final class DrumxMenuInput {
  static let entryGuard: Double = 0.75
  static let navigationDebounce: Double = 0.20
  static let confirmationWindow: Double = 0.60
  static let minimumKickSeparation: Double = 0.08
  static let activationCooldown: Double = 0.90

  private var acceptsAfter = Double.infinity
  private var lastObservedAt: Double?
  private var lastNavigationAt: Double?
  private var lastActivationAt: Double?
  private var kickArmedAt: Double?
  private let tolerance = 0.000000001

  func reset(at time: Double) {
    kickArmedAt = nil
    lastNavigationAt = nil
    guard time.isFinite, time >= 0 else {
      acceptsAfter = .infinity
      lastObservedAt = nil
      return
    }
    acceptsAfter = time + Self.entryGuard
    lastObservedAt = time
    // Keep activation cooldown across page transitions, while clearing the arm.
  }

  func isKickArmed(at time: Double) -> Bool {
    guard time.isFinite, let armed = kickArmedAt else { return false }
    return time >= armed && time - armed <= Self.confirmationWindow + tolerance
  }

  func receive(pad: Int, velocity: Int, at time: Double) -> DrumxMenuCommand? {
    guard (0..<3).contains(pad), (32...127).contains(velocity), time.isFinite, time >= 0,
      time + tolerance >= acceptsAfter,
      lastObservedAt.map({ time >= $0 }) ?? true else { return nil }
    lastObservedAt = time

    if pad != 2 {
      // Navigation clears any confirmation aimed at the previous selection.
      kickArmedAt = nil
      if let previous = lastNavigationAt,
        time - previous + tolerance < Self.navigationDebounce { return nil }
      lastNavigationAt = time
      return pad == 0 ? .previous : .next
    }

    if let activation = lastActivationAt,
      time - activation + tolerance < Self.activationCooldown { return nil }
    guard let armed = kickArmedAt else {
      kickArmedAt = time
      return nil
    }
    let interval = time - armed
    if interval > Self.confirmationWindow + tolerance {
      kickArmedAt = time
      return nil
    }
    guard interval + tolerance >= Self.minimumKickSeparation else { return nil }
    kickArmedAt = nil
    lastActivationAt = time
    return .activate
  }
}
