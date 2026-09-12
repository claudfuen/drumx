import Foundation

enum DrumxHitKind: Equatable {
  case strike
  case matched
  case extra
}

struct DrumxHitPulse: Equatable {
  let id: UInt64
  let pad: Int
  let kind: DrumxHitKind
  let startedAt: Double
  let velocity: Double
  /// Only matched pulses expose a signed offset; neutral and extra pulses use zero.
  let offsetMS: Double

  /// Normalized animation age. Future, expired, and invalid times are not drawable.
  func progress(at time: Double) -> Double? {
    guard time.isFinite, time >= startedAt,
      time < startedAt + DrumxHitFeedback.duration
    else { return nil }
    return min((time - startedAt) / DrumxHitFeedback.duration, 1.0.nextDown)
  }
}

/// Serial use by the controller. Each physical input produces its own short pulse,
/// including simultaneous notes and repeated strikes on the same pad.
struct DrumxHitFeedback {
  static let duration: Double = 0.42
  static let maxPulses = 48
  private(set) var pulses: [DrumxHitPulse] = []
  private var nextID: UInt64 = 1

  init() {
    pulses.reserveCapacity(Self.maxPulses)
  }

  /// `at` is visual receipt time, not the original timestamp used for grading.
  /// The caller records physical strikes only; this buffer never generates misses.
  mutating func record(
    pad: Int, judgment: Int?, velocity: Double, offsetMS: Double, at time: Double,
    revealJudgment: Bool
  ) {
    guard (0..<3).contains(pad), time.isFinite, velocity.isFinite, offsetMS.isFinite else {
      return
    }
    prune(at: time)
    // Evict before appending so a burst never grows the array beyond its capacity.
    if pulses.count == Self.maxPulses { pulses.removeFirst() }

    let kind: DrumxHitKind
    if revealJudgment {
      switch judgment {
      case 1?, 2?, 3?: kind = .matched
      case 4?: kind = .extra
      default: kind = .strike
      }
    } else {
      kind = .strike
    }
    pulses.append(DrumxHitPulse(
      id: nextID, pad: pad, kind: kind, startedAt: time,
      velocity: min(1, max(0, velocity)), offsetMS: kind == .matched ? offsetMS : 0))
    nextID &+= 1
    if nextID == 0 { nextID = 1 }
  }

  mutating func prune(at time: Double) {
    guard time.isFinite else { return }
    pulses.removeAll { time >= $0.startedAt + Self.duration }
  }

  /// Keep the ID sequence and reserved storage while removing every old animation.
  mutating func reset() {
    pulses.removeAll(keepingCapacity: true)
  }
}
