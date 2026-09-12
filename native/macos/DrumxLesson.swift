import Foundation

/// Capture once at take start. Changing an aid or input creates a different comparison group.
struct TakeSettings: Codable, Equatable {
  let tempo: Double
  let mode: Int
  let liveFeedback: Bool
  let bars: Int
  let calibrationMS: Double
  let inputIdentity: String
  let mapping: [[Int]]
  let lessonVersion: String
  let handHints: Bool

  init(
    tempo: Double, mode: Int, liveFeedback: Bool, bars: Int, calibrationMS: Double,
    inputIdentity: String, mapping: [[Int]], lessonVersion: String = "first-backbeat-v1",
    handHints: Bool = true
  ) {
    self.tempo = tempo
    self.mode = mode
    self.liveFeedback = liveFeedback
    self.bars = bars
    self.calibrationMS = calibrationMS
    self.inputIdentity = inputIdentity
    // The order of aliases within one pad does not affect its meaning.
    self.mapping = mapping.map { Array(Set($0)).sorted() }
    self.lessonVersion = lessonVersion
    self.handHints = handHints
  }

  fileprivate var isValid: Bool {
    tempo.isFinite && (30...240).contains(tempo) && (0...2).contains(mode)
      && (1...64).contains(bars) && calibrationMS.isFinite
      && !inputIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !lessonVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && mapping.count == 3 && mapping.flatMap { $0 }.allSatisfy { (0...127).contains($0) }
  }
}

private let reviewPadNames = ["hi-hat", "snare", "kick"]

/// A fixed-size musical goal: points are earned against the whole phrase, even
/// while playing. Combos report the core's on-time streak and add no multiplier.
struct DrumxRunScore {
  let points: Int
  let stars: Int
  let progressToNextStar: Double
  let nextStarPoints: Int?
  let combo: Int
  let bestCombo: Int
  let isPerfect: Bool
  let isComplete: Bool

  init(snapshot: DXSnapshot, completedNaturally: Bool) {
    let total = snapshot.total
    let validClock = snapshot.bpm.isFinite && snapshot.bpm > 0
      && snapshot.duration_seconds.isFinite && snapshot.duration_seconds > 0
      && snapshot.elapsed_seconds.isFinite && snapshot.elapsed_seconds >= 0
    self.init(
      expected: Int(total.expected), matched: Int(total.matched), missed: Int(total.missed),
      extra: Int(total.extra), onTime: Int(total.on_time), combo: Int(total.streak),
      bestCombo: Int(total.best_streak),
      complete: completedNaturally && isCompleteSnapshot(snapshot), valid: validClock)
  }

  init(attempt: LessonAttempt) {
    self.init(
      expected: attempt.expected, matched: attempt.matched, missed: attempt.missed,
      extra: attempt.extra, onTime: attempt.onTime, combo: 0,
      bestCombo: attempt.bestStreak ?? 0, complete: attempt.isValid, valid: attempt.isValid)
  }

  private init(
    expected: Int, matched: Int, missed: Int, extra: Int, onTime: Int,
    combo: Int, bestCombo: Int, complete: Bool, valid: Bool
  ) {
    guard valid, expected > 0, matched >= 0, matched <= expected,
      missed >= 0, missed <= expected - matched, extra >= 0,
      onTime >= 0, onTime <= matched, combo >= 0, bestCombo >= combo, bestCombo <= onTime
    else {
      points = 0; stars = 0; progressToNextStar = 0; nextStarPoints = 4000
      self.combo = 0; self.bestCombo = 0; isPerfect = false; isComplete = false
      return
    }
    isComplete = complete
    isPerfect = complete && matched == expected && onTime == expected && missed == 0 && extra == 0
    self.combo = combo
    self.bestCombo = bestCombo

    // Full-width integer division preserves floor semantics at every threshold,
    // including counts too large for exact Double arithmetic. The quotient is <=10000.
    let denominator = UInt64(expected) + UInt64(extra)
    let numerator = UInt64(onTime).multipliedFullWidth(by: 10_000)
    let earned = Int(denominator.dividingFullWidth(numerator).quotient)
    let earnedPoints = min(earned, isPerfect ? 10_000 : 9_999)
    points = earnedPoints
    let thresholds = [4000, 6000, 7500, 9000, 10_000]
    stars = thresholds.filter { earnedPoints >= $0 }.count
    if stars == thresholds.count {
      nextStarPoints = nil
      progressToNextStar = 1
    } else {
      let previous = stars == 0 ? 0 : thresholds[stars - 1]
      let next = thresholds[stars]
      nextStarPoints = next
      progressToNextStar = Double(points - previous) / Double(next - previous)
    }
  }
}

/// Counts and timing are evidence about this attempt, never verification of hand technique.
struct LessonReview {
  let headline: String
  let detail: String
  let suggestedPad: Int?

  init(snapshot: DXSnapshot, completedNaturally: Bool) {
    let total = snapshot.total
    guard completedNaturally && isCompleteSnapshot(snapshot) else {
      if snapshot.elapsed_seconds <= 0 && total.matched == 0 && total.extra == 0 {
        headline = "Ready when you are"
        detail = "Follow the four-count lead-in, then join the groove."
      } else {
        headline = "Take stopped"
        detail = "Play the whole phrase to save a result."
      }
      suggestedPad = nil
      return
    }
    if total.matched == 0 {
      headline = "No matched hits yet"
      detail = "Check that your pads respond, then try again after the count-in."
      suggestedPad = nil
      return
    }
    let everyTargetOnTime = total.missed == 0 && total.extra == 0 && total.on_time == total.expected
    if total.matched < 8 {
      // A sparse exercise may contain only two or four targets. Few hits are
      // not missing work when the learner played every authored note on time.
      if everyTargetOnTime {
        headline = "The phrase stayed together"
        detail = "Every note landed inside the timing band. Repeat until it feels easy, then try less visual help."
        suggestedPad = nil
      } else {
        headline = "Build the pattern one part at a time"
        let parts = [snapshot.pads.0, snapshot.pads.1, snapshot.pads.2]
        let first = (0..<3).max { parts[$0].expected < parts[$1].expected } ?? 0
        detail = "\(total.matched) hits matched. Focus on the \(reviewPadNames[first]) and count each beat aloud at a comfortable tempo."
        suggestedPad = first
      }
      return
    }
    let pads = [snapshot.pads.0, snapshot.pads.1, snapshot.pads.2]
    // Compare omission rates, not raw counts: the hat has more targets than the other pads.
    let omissionPad = (0..<3).filter { pads[$0].expected > 0 && pads[$0].missed >= 2 }.max {
      Double(pads[$0].missed) / Double(pads[$0].expected)
        < Double(pads[$1].missed) / Double(pads[$1].expected)
    }
    if let pad = omissionPad,
      Double(pads[pad].missed) / Double(pads[pad].expected) >= 0.2
    {
      headline = "Bring in the \(reviewPadNames[pad])"
      detail = "\(pads[pad].missed) of \(pads[pad].expected) \(reviewPadNames[pad]) notes were missed. Count that part aloud, then add it back at a comfortable tempo."
      suggestedPad = pad
      return
    }
    if total.extra >= 3 && Double(total.extra) >= Double(total.matched) * 0.2 {
      let pad = (0..<3).max { pads[$0].extra < pads[$1].extra } ?? 0
      headline = "Leave space between the written notes"
      detail = "\(total.extra) extra hits. Try one strike per note. If a single hit registers twice, check your pad mapping."
      suggestedPad = pad
      return
    }
    let biases = [snapshot.bias.0, snapshot.bias.1, snapshot.bias.2]
    let timingPad = (0..<3).filter {
      let bias = biases[$0]
      return bias.sample_count >= 4 && bias.offset_ms.isFinite && bias.spread_ms.isFinite
        && bias.age_seconds.isFinite && bias.age_seconds >= 0
        && (2...4).contains(Int(bias.state))
    }.max {
      let a = biases[$0], b = biases[$1]
      return max(abs(a.offset_ms), a.spread_ms) < max(abs(b.offset_ms), b.spread_ms)
    }
    if let pad = timingPad {
      let bias = biases[pad]
      if bias.state == 4 {
        headline = "Steady the \(reviewPadNames[pad]) spacing"
        detail = "Recent \(reviewPadNames[pad]) hits had uneven spaces. Slow it down and listen for even strokes."
        suggestedPad = pad
        return
      }
      if bias.state == 2 || bias.state == 3 {
        let direction = bias.state == 2 ? "early" : "late"
        headline = "Listen to the \(reviewPadNames[pad]) against the click"
        detail = String(
          format: "Recent %@ hits tended %.0f ms %@. Listen for the click and keep the spaces even.",
          reviewPadNames[pad], abs(bias.offset_ms), direction)
        suggestedPad = pad
        return
      }
    }
    if everyTargetOnTime {
      headline = "The phrase stayed together"
      detail = "Every note landed inside the timing band. Repeat until it feels easy, then try less visual help."
      suggestedPad = nil
    } else {
      headline = "Keep building a repeatable phrase"
      detail = "\(total.matched) matched hits, \(total.missed) misses and \(total.extra) extras. Repeat at a comfortable tempo until the phrase feels steady."
      suggestedPad = nil
    }
  }
}

struct LessonAttempt: Codable, Equatable, Identifiable {
  let id: UUID
  let endedAt: Date
  let settings: TakeSettings
  let matched: Int
  let missed: Int
  let extra: Int
  let onTime: Int
  let expected: Int
  let timingAccuracyPercent: Double
  let hitRatePercent: Double
  let meanOffsetMS: Double?
  let meanAbsoluteOffsetMS: Double?
  /// nil identifies older saved attempts that did not record a best streak.
  let bestStreak: Int?

  fileprivate var isValid: Bool {
    guard settings.isValid, endedAt.timeIntervalSinceReferenceDate.isFinite,
      matched >= 0, missed >= 0, extra >= 0, onTime >= 0, expected > 0,
      matched <= expected, missed == expected - matched, onTime <= matched,
      timingAccuracyPercent.isFinite, hitRatePercent.isFinite,
      (0...100).contains(timingAccuracyPercent), (0...100).contains(hitRatePercent),
      bestStreak.map({ $0 >= 0 && $0 <= onTime }) ?? true
    else { return false }
    let denominator = Double(expected) + Double(extra)
    guard abs(timingAccuracyPercent - Double(onTime) / denominator * 100) < 0.000001,
      abs(hitRatePercent - Double(matched) / denominator * 100) < 0.000001
    else { return false }
    if matched == 0 { return meanOffsetMS == nil && meanAbsoluteOffsetMS == nil }
    guard let signed = meanOffsetMS, let absolute = meanAbsoluteOffsetMS else { return false }
    return signed.isFinite && absolute.isFinite && absolute >= 0
      && absolute <= 125.000001 && abs(signed) <= absolute + 0.000001
  }
}

/// Serial/main-thread use. Only complete natural takes are persisted.
final class LessonHistory {
  private let defaults: UserDefaults
  private let key: String
  private(set) var attempts: [LessonAttempt] = []
  private(set) var lastError: String?

  init(defaults: UserDefaults = .standard, key: String = "drumx.lessonHistory.v1") {
    self.defaults = defaults
    self.key = key
    guard let data = defaults.data(forKey: key) else { return }
    do {
      let decoded = try JSONDecoder().decode([LessonAttempt].self, from: data)
      var unique: [UUID: LessonAttempt] = [:]
      for attempt in decoded where attempt.isValid { unique[attempt.id] = attempt }
      attempts = Array(unique.values.sorted { $0.endedAt < $1.endedAt }.suffix(200))
    } catch {
      lastError = "Saved lesson history could not be read."
    }
  }

  /// Reuse the take UUID and end date when preserved MIDI timestamps correct its result.
  @discardableResult
  func record(
    id: UUID, settings: TakeSettings, snapshot: DXSnapshot, completedNaturally: Bool,
    endedAt: Date = Date()
  ) -> LessonAttempt? {
    guard completedNaturally, settings.isValid, isCompleteSnapshot(snapshot),
      endedAt.timeIntervalSinceReferenceDate.isFinite,
      abs(snapshot.bpm - settings.tempo) < 0.000001,
      Int(snapshot.guidance) == settings.mode,
      abs(snapshot.duration_seconds - Double(settings.bars) * 240 / settings.tempo) < 0.000001
    else { return nil }
    let total = snapshot.total
    let denominator = Double(total.expected) + Double(total.extra)
    let attempt = LessonAttempt(
      id: id, endedAt: endedAt, settings: settings,
      matched: Int(total.matched), missed: Int(total.missed), extra: Int(total.extra),
      onTime: Int(total.on_time), expected: Int(total.expected),
      timingAccuracyPercent: Double(total.on_time) / denominator * 100,
      hitRatePercent: Double(total.matched) / denominator * 100,
      meanOffsetMS: total.matched > 0 ? total.mean_offset_ms : nil,
      meanAbsoluteOffsetMS: total.matched > 0 ? total.mean_absolute_offset_ms : nil,
      bestStreak: Int(total.best_streak))
    guard attempt.isValid else { return nil }
    if let existing = attempts.first(where: { $0.id == id }), existing.settings != settings {
      return nil // A correction cannot silently move an attempt into another comparison group.
    }
    var updated = attempts.filter { $0.id != id }
    updated.append(attempt)
    updated.sort { $0.endedAt < $1.endedAt }
    updated = Array(updated.suffix(200))
    do {
      let data = try JSONEncoder().encode(updated)
      defaults.set(data, forKey: key)
      attempts = updated
      lastError = nil
      return attempt
    } catch {
      lastError = "This lesson result could not be saved."
      return nil
    }
  }

  /// Higher timing accuracy wins, then higher hit rate, then lower mean absolute
  /// timing error. The newest result breaks an exact tie. All aids/settings must match.
  /// A zero-score result is evidence of an attempt, not a claim of skill or mastery.
  func best(matching settings: TakeSettings, excluding id: UUID? = nil) -> LessonAttempt? {
    guard settings.isValid else { return nil }
    return attempts.filter { $0.settings == settings && $0.id != id }.max { a, b in
      if a.timingAccuracyPercent != b.timingAccuracyPercent {
        return a.timingAccuracyPercent < b.timingAccuracyPercent
      }
      if a.hitRatePercent != b.hitRatePercent { return a.hitRatePercent < b.hitRatePercent }
      let aError = a.meanAbsoluteOffsetMS ?? .infinity
      let bError = b.meanAbsoluteOffsetMS ?? .infinity
      if aError != bError { return aError > bError }
      return a.endedAt < b.endedAt
    }
  }

  /// Newest completed takes under the same conditions; partial takes never enter history.
  func recent(
    matching settings: TakeSettings, limit: Int = 6, excluding id: UUID? = nil
  ) -> [LessonAttempt] {
    guard settings.isValid, limit > 0 else { return [] }
    return Array(attempts.reversed().filter {
      $0.settings == settings && $0.id != id
    }.prefix(min(200, limit)))
  }
}

private func isCompleteSnapshot(_ snapshot: DXSnapshot) -> Bool {
  let total = snapshot.total
  guard snapshot.finished != 0, snapshot.bpm.isFinite, snapshot.bpm > 0,
    snapshot.duration_seconds.isFinite, snapshot.duration_seconds > 0,
    snapshot.elapsed_seconds.isFinite,
    snapshot.elapsed_seconds >= snapshot.duration_seconds - 0.000001,
    total.expected > 0, total.matched >= 0, total.missed >= 0, total.extra >= 0,
    total.matched <= total.expected, total.missed == total.expected - total.matched,
    total.on_time >= 0, total.on_time <= total.matched,
    total.timing_accuracy_percent.isFinite, total.hit_rate_percent.isFinite,
    total.mean_offset_ms.isFinite, total.mean_absolute_offset_ms.isFinite
  else { return false }
  return true
}
