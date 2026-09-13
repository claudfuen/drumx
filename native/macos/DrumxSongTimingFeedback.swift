import Foundation

enum DrumxSongTimingStatus: Equatable {
  case gathering
  case centered
  case rushing
  case dragging
  case uneven
  case stale

  var label: String {
    switch self {
    case .gathering: return "Play a few notes"
    case .centered: return "Centered"
    case .rushing: return "Rushing"
    case .dragging: return "Dragging"
    case .uneven: return "Uneven"
    case .stale: return "Waiting for hits"
    }
  }
}

struct DrumxSongTimingState: Equatable {
  let status: DrumxSongTimingStatus
  /// Negative means early, positive means late. Absent until enough fresh matches exist.
  let offsetMS: Double?
  let sampleCount: Int
  /// Median absolute deviation, so a single stray hit does not dominate consistency.
  let spreadMS: Double?

  var label: String { status.label }
}

/// Recent tendency across the entire kit, independent of rendering and wall time.
/// The controller records matched judgments only, never extra or ignored strikes.
/// Use the same song clock for captures and `state(at:)`, freezing it during pause.
struct DrumxSongTimingFeedback {
  static let sampleLimit = 12
  static let horizonSeconds = 4.0
  static let staleSeconds = 3.0
  static let minimumSamples = 3
  static let centeredDeadbandMS = 12.0

  private struct Sample {
    let id: UInt64
    let eventID: Int?
    let time: Double
    let offsetMS: Double
  }

  private var samples: [Sample] = []
  private var greatestID: UInt64 = 0
  private var lastMatchedTime: Double?

  /// Core hit IDs increase within a run even when capture timestamps arrive late.
  /// Reset this helper with the core; rejecting old IDs also prevents snapshot replays.
  mutating func record(id: UInt64, time: Double, offsetMS: Double, eventID: Int? = nil) {
    guard id > greatestID, time.isFinite, offsetMS.isFinite else { return }
    greatestID = id
    if let eventID { samples.removeAll { $0.eventID == eventID } }
    let latest = max(samples.map(\.time).max() ?? time, time)
    lastMatchedTime = latest
    samples.append(Sample(id: id, eventID: eventID, time: time, offsetMS: offsetMS))
    samples.removeAll { latest - $0.time > Self.horizonSeconds }
    samples.sort { left, right in
      left.time == right.time ? left.id > right.id : left.time > right.time
    }
    if samples.count > Self.sampleLimit {
      samples.removeLast(samples.count - Self.sampleLimit)
    }
  }

  func state(at time: Double) -> DrumxSongTimingState {
    guard time.isFinite else { return idle(.gathering, count: 0) }
    let visible = samples.filter { $0.time <= time }
    let recent = visible.filter { time - $0.time <= Self.horizonSeconds }
    let lastVisibleTime = lastMatchedTime.flatMap { $0 <= time ? $0 : visible.first?.time }
    if let lastVisibleTime, time - lastVisibleTime >= Self.staleSeconds - 1e-9 {
      return idle(.stale, count: recent.count)
    }
    guard recent.count >= Self.minimumSamples else {
      return idle(.gathering, count: recent.count)
    }
    var offsets = recent.map(\.offsetMS)
    let rawMedian = median(offsets)
    let rawDeviation = median(offsets.map { abs($0 - rawMedian) })
    // Match the core's robust bias estimator; only the sample window and deadband differ.
    let fence = max(30, 3 * 1.4826 * rawDeviation)
    offsets.removeAll { abs($0 - rawMedian) > fence }
    guard offsets.count >= Self.minimumSamples else {
      return idle(.gathering, count: offsets.count)
    }
    let offset = median(offsets)
    let spread = median(offsets.map { abs($0 - offset) })
    let status: DrumxSongTimingStatus
    if spread > 25 { status = .uneven }
    else if offset < -Self.centeredDeadbandMS { status = .rushing }
    else if offset > Self.centeredDeadbandMS { status = .dragging }
    else { status = .centered }
    return DrumxSongTimingState(status: status, offsetMS: offset,
      sampleCount: offsets.count, spreadMS: spread)
  }

  mutating func reset() {
    samples.removeAll(keepingCapacity: true)
    greatestID = 0
    lastMatchedTime = nil
  }

  private func idle(_ status: DrumxSongTimingStatus, count: Int) -> DrumxSongTimingState {
    DrumxSongTimingState(status: status, offsetMS: nil, sampleCount: count, spreadMS: nil)
  }

  private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    // Halving first avoids overflow for finite values near Double's limit.
    return sorted.count % 2 == 1 ? sorted[middle] : sorted[middle - 1] / 2 + sorted[middle] / 2
  }
}
