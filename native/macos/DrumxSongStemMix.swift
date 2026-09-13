import Foundation

enum DrumxSongAudioMode: String, CaseIterable {
  case practice
  case reference

  var title: String {
    switch self {
    case .practice: return "Play your drums"
    case .reference: return "Hear recorded drums"
    }
  }
}

/// Changes the imported recording's mix, independently of scoring and live-pad
/// monitoring. Stem names come from the manifest, never the decoded cache name.
struct DrumxSongStemMix {
  let mode: DrumxSongAudioMode
  let gains: [Float]
  let hasSeparateDrums: Bool
  let hasBacking: Bool
  private let hasAudio: Bool

  init(stems: [String], mode: DrumxSongAudioMode = .practice) {
    self.mode = mode
    hasAudio = !stems.isEmpty
    hasSeparateDrums = stems.contains(where: Self.isDrumStem)
    hasBacking = stems.contains { !Self.isDrumStem($0) }
    gains = stems.map { Self.gain(for: $0, mode: mode) }
  }

  static func isDrumStem(_ name: String) -> Bool {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "drums", "drums_1", "drums_2", "drums_3", "drums_4": return true
    default: return false
    }
  }

  static func gain(for stem: String, mode: DrumxSongAudioMode) -> Float {
    mode == .practice && isDrumStem(stem) ? 0 : 1
  }

  var status: String {
    guard hasAudio else { return "This chart has no song audio." }
    guard hasSeparateDrums else {
      return "No separate drum stems. Drums embedded in the song remain audible."
    }
    switch mode {
    case .practice:
      return hasBacking ? "Recorded drum stems are off. Play with the backing track."
        : "Recorded drums are off. This song has no separate backing track."
    case .reference:
      return "Recorded drums play with the song, independently of your hits."
    }
  }

  var limitation: String? {
    guard hasAudio else { return nil }
    return hasSeparateDrums ? "Drums mixed into other recordings can still be audible."
      : "Muting drums requires a separate drum recording or a drumless backing track."
  }
}
