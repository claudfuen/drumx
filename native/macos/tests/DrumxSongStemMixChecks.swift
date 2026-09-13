import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

@main
struct DrumxSongStemMixChecks {
  static func main() {
    // A one-file full song must never disappear merely because it has no stems.
    for name in ["song", "guitar"] {
      let mixed = DrumxSongStemMix(stems: [name])
      check(mixed.gains == [1], "a full mix remains audible in practice")
      check(!mixed.hasSeparateDrums && mixed.hasBacking, "a full mix cannot promise drum isolation")
      check(mixed.status.contains("remain audible"), "mixed songs explain the remaining drums")
    }

    // Cover actual common YARG packages: a single drum stem, and two to four
    // numbered recordings whose audio may contain several kit pieces each.
    let combinations = [["drums"], ["drums_1"], ["drums_1", "drums_2"],
      ["drums_1", "drums_2", "drums_3"], ["drums_1", "drums_2", "drums_3", "drums_4"]]
    for drums in combinations {
      let names = ["song", "guitar", "bass", "rhythm", "keys", "vocals", "vocals_1", "vocals_2", "crowd"] + drums
      let practice = DrumxSongStemMix(stems: names)
      let reference = DrumxSongStemMix(stems: names, mode: .reference)
      check(practice.mode == .practice && practice.hasSeparateDrums && practice.hasBacking,
        "isolated drum recordings default to practice with backing")
      check(practice.gains == Array(repeating: Float(1), count: 9) + Array(repeating: Float(0), count: drums.count),
        "practice silences every drum recording while retaining every backing instrument")
      check(reference.gains == Array(repeating: Float(1), count: names.count),
        "reference restores the entire recorded mix")
      check(reference.status.contains("independently of your hits"), "reference clearly explains unattended drum playback")
      check(practice.limitation?.contains("other recordings") == true,
        "separate stems do not promise to remove bleed from other recordings")
    }

    let reordered = DrumxSongStemMix(stems: ["DRUMS_4", "song", " drums_1\n", "vocals", "Drums_3", "drums_2"])
    check(reordered.gains == [0, 1, 0, 1, 0, 0], "gain follows manifest identity regardless of file order or capitalization")
    for unknown in ["drums_5", "drums_live", "drums_1.wav", "", "other"] {
      check(DrumxSongStemMix.gain(for: unknown, mode: .practice) == 1,
        "unknown audio is preserved without guessing its contents")
    }

    let drumsOnly = DrumxSongStemMix(stems: ["drums_1", "drums_2"])
    check(drumsOnly.gains == [0, 0] && !drumsOnly.hasBacking, "a drum-only song stays silent instead of re-enabling drums")
    check(drumsOnly.status.contains("no separate backing"), "a drum-only recording explains its silent backing")
    let empty = DrumxSongStemMix(stems: [])
    check(empty.gains.isEmpty && !empty.hasSeparateDrums && empty.limitation == nil, "missing audio is not presented as inseparable drums")
    check(empty.status == "This chart has no song audio.", "missing audio has its own status")

    print("\(checks) song stem mix checks passed.")
  }
}
