import Foundation

/// A take's immutable clock/source settings and its final raw capture-time boundary.
/// This does not impose the scoring core's count-in or phrase matching windows.
struct DrumxTakeWindow {
  let practiceStart: Double
  let calibrationMS: Double
  let inputIdentity: String

  private var stopHostTime: Double?
  private var acceptsInput = true

  init(practiceStart: Double, calibrationMS: Double, inputIdentity: String) {
    self.practiceStart = practiceStart
    self.calibrationMS = calibrationMS
    self.inputIdentity = inputIdentity
  }

  /// Repeated stops cannot reopen or extend a take. An invalid stop closes input.
  mutating func stop(atHostTime hostTime: Double) {
    guard hostTime.isFinite else {
      acceptsInput = false
      return
    }
    stopHostTime = min(stopHostTime ?? hostTime, hostTime)
  }

  /// Compare the original capture timestamp before calibration. Late delivery of
  /// a pre-stop hit is valid; a newly played post-stop hit is never a correction.
  func songTime(capturedAt hostTime: Double, inputIdentity source: String) -> Double? {
    guard acceptsInput, practiceStart.isFinite, calibrationMS.isFinite,
      hostTime.isFinite, !inputIdentity.isEmpty, source == inputIdentity
    else { return nil }
    if let cutoff = stopHostTime, hostTime > cutoff { return nil }
    let result = hostTime - practiceStart - calibrationMS / 1000
    return result.isFinite ? result : nil
  }

  /// Completion follows elapsed musical time, without the input calibration.
  /// Stop during the UI's late-delivery grace period still completes the phrase.
  func phraseHasEnded(atHostTime hostTime: Double, duration: Double) -> Bool {
    guard practiceStart.isFinite, hostTime.isFinite, duration.isFinite, duration > 0
    else { return false }
    let elapsed = hostTime - practiceStart
    return elapsed.isFinite && elapsed >= duration
  }
}
