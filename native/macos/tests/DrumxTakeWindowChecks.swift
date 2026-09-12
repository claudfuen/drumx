import Foundation

@main enum DrumxTakeWindowChecks {
  static func main() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
      checks += 1
      guard condition() else { fatalError("Take window check failed: \(label)") }
    }
    func near(_ value: Double?, _ expected: Double) -> Bool {
      guard let value else { return false }
      return abs(value - expected) < 0.000000001
    }

    var positive = DrumxTakeWindow(
      practiceStart: 100, calibrationMS: 200, inputIdentity: "midi:42")
    check(near(positive.songTime(capturedAt: 101.1, inputIdentity: "midi:42"), 0.9),
          "A running take applies its positive calibration")
    positive.stop(atHostTime: 101)
    check(positive.songTime(capturedAt: 101.1, inputIdentity: "midi:42") == nil,
          "Positive calibration cannot turn a fresh post-stop hit into a correction")
    check(near(positive.songTime(capturedAt: 100.95, inputIdentity: "midi:42"), 0.75),
          "A preserved pre-stop MIDI timestamp remains valid after delayed delivery")
    check(near(positive.songTime(capturedAt: 101, inputIdentity: "midi:42"), 0.8),
          "Capture exactly at the raw stop cutoff is accepted")
    check(positive.songTime(capturedAt: 101.nextUp, inputIdentity: "midi:42") == nil,
          "The next representable capture time after the cutoff is rejected")

    var negative = DrumxTakeWindow(
      practiceStart: 100, calibrationMS: -200, inputIdentity: "keyboard")
    negative.stop(atHostTime: 101)
    check(near(negative.songTime(capturedAt: 100.95, inputIdentity: "keyboard"), 1.15),
          "Negative calibration does not reject a raw pre-stop hit")
    check(near(negative.songTime(capturedAt: 101, inputIdentity: "keyboard"), 1.2),
          "Negative calibration keeps the inclusive raw cutoff")
    check(negative.songTime(capturedAt: 101.01, inputIdentity: "keyboard") == nil,
          "Negative calibration also rejects fresh post-stop hits")
    check(near(negative.songTime(capturedAt: 99.9, inputIdentity: "keyboard"), 0.1),
          "Count-in eligibility is left to the scoring core")

    check(positive.songTime(capturedAt: 100.8, inputIdentity: "keyboard") == nil,
          "Keyboard input cannot earn a MIDI take's score")
    check(positive.songTime(capturedAt: 100.8, inputIdentity: "midi:43") == nil,
          "Another MIDI input cannot alter this take")
    check(positive.songTime(capturedAt: 100.8, inputIdentity: "MIDI:42") == nil,
          "Input identities match exactly")
    check(negative.songTime(capturedAt: 100.8, inputIdentity: "midi:42") == nil,
          "MIDI input cannot earn a keyboard take's score")

    positive.stop(atHostTime: 102)
    check(positive.songTime(capturedAt: 101.1, inputIdentity: "midi:42") == nil,
          "A repeated later stop cannot extend the take")
    positive.stop(atHostTime: 100.9)
    check(positive.songTime(capturedAt: 100.95, inputIdentity: "midi:42") == nil,
          "An earlier stop narrows the capture boundary")

    for invalid in [Double.nan, Double.infinity, -Double.infinity] {
      let valid = DrumxTakeWindow(
        practiceStart: 100, calibrationMS: 0, inputIdentity: "keyboard")
      check(valid.songTime(capturedAt: invalid, inputIdentity: "keyboard") == nil,
            "Nonfinite capture timestamps are rejected")
      let badStart = DrumxTakeWindow(
        practiceStart: invalid, calibrationMS: 0, inputIdentity: "keyboard")
      check(badStart.songTime(capturedAt: 101, inputIdentity: "keyboard") == nil,
            "Nonfinite clock anchors cannot yield a score timestamp")
      let badOffset = DrumxTakeWindow(
        practiceStart: 100, calibrationMS: invalid, inputIdentity: "keyboard")
      check(badOffset.songTime(capturedAt: 101, inputIdentity: "keyboard") == nil,
            "Nonfinite calibration is rejected")
      var badStop = valid
      badStop.stop(atHostTime: invalid)
      badStop.stop(atHostTime: 102)
      check(badStop.songTime(capturedAt: 101, inputIdentity: "keyboard") == nil,
            "An invalid stop closes input and a later stop cannot reopen it")
      check(!valid.phraseHasEnded(atHostTime: invalid, duration: 4),
            "Nonfinite completion host time cannot complete a phrase")
      check(!valid.phraseHasEnded(atHostTime: 104, duration: invalid),
            "Nonfinite duration cannot complete a phrase")
      check(!badStart.phraseHasEnded(atHostTime: 104, duration: 4),
            "Nonfinite clock anchor cannot complete a phrase")
    }

    let blank = DrumxTakeWindow(practiceStart: 100, calibrationMS: 0, inputIdentity: "")
    check(blank.songTime(capturedAt: 101, inputIdentity: "") == nil,
          "An unspecified input identity cannot score")
    let overflow = DrumxTakeWindow(
      practiceStart: -Double.greatestFiniteMagnitude, calibrationMS: 0,
      inputIdentity: "keyboard")
    check(overflow.songTime(capturedAt: Double.greatestFiniteMagnitude,
                            inputIdentity: "keyboard") == nil,
          "Finite inputs that overflow elapsed time are rejected")
    check(!overflow.phraseHasEnded(atHostTime: Double.greatestFiniteMagnitude, duration: 4),
          "Overflow does not prove completion")

    for offset in [-200.0, 0, 200] {
      let window = DrumxTakeWindow(
        practiceStart: 100, calibrationMS: offset, inputIdentity: "keyboard")
      check(!window.phraseHasEnded(atHostTime: 103.99, duration: 4),
            "A phrase is unfinished just before its musical end")
      check(window.phraseHasEnded(atHostTime: 104, duration: 4),
            "The exact musical end completes the phrase regardless of calibration")
      check(window.phraseHasEnded(atHostTime: 104.05, duration: 4),
            "Stopping during the UI grace period preserves completion")
      check(!window.phraseHasEnded(atHostTime: 99, duration: 4),
            "Stopping in the count-in is incomplete")
      check(!window.phraseHasEnded(atHostTime: 104, duration: 0),
            "A zero-length phrase cannot complete")
      check(!window.phraseHasEnded(atHostTime: 104, duration: -1),
            "A negative-length phrase cannot complete")
    }
    print("Take window checks passed: \(checks)")
  }
}
