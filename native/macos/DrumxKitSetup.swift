import Foundation

struct DrumxKitHit: Equatable {
  /// Nil for a keyboard check; MIDI receipts retain even an unmapped raw note.
  let note: Int?
  let velocity: Int
  let sourceID: Int32?
  let pad: Int?
  let receivedAt: Double
}

struct DrumxKitMappingChange: Equatable {
  let pad: Int
  let note: Int
  let wasAlreadyMapped: Bool
  let removedFromPads: [Int]
  let mappings: [[Int]]
}

struct DrumxKitReceipt: Equatable {
  let hit: DrumxKitHit
  let mappingChange: DrumxKitMappingChange?
}

/// Serial setup state. The controller owns native source connection, persistence,
/// sampler mapping and MIDI-learn muting. This model never infers a physical pad
/// from its appearance, a keyboard hit, or the presence of a MIDI endpoint alone.
final class DrumxKitSetup {
  static let defaultMappings = [[42, 44, 46], [38, 40], [35, 36]]
  static let maximumAliasesPerPad = 16

  private(set) var mappings: [[Int]]
  private(set) var selectedSourceID: Int32?
  private(set) var pendingPad: Int?
  private(set) var confirmedPads: Set<Int> = []
  private(set) var lastHit: DrumxKitHit?
  private(set) var lastError: String?
  private var learningStartedAt: Double?

  var isMIDISelected: Bool { selectedSourceID != nil }
  var isReady: Bool { confirmedPads == Set(0..<3) }

  init(mappings: [[Int]] = DrumxKitSetup.defaultMappings) {
    if Self.validMappings(mappings) {
      self.mappings = mappings.map { $0.sorted() }
    } else {
      self.mappings = Self.defaultMappings
      lastError = "Saved MIDI mapping was invalid. Standard drum notes are in use."
    }
  }

  /// Pass the source that actually connected, not the popup's requested ID.
  func selectSource(_ sourceID: Int32?) {
    guard sourceID != selectedSourceID else { return }
    selectedSourceID = sourceID
    invalidateInput()
  }

  /// Also call for failed reconnects or port loss when the visible source ID is unchanged.
  func invalidateInput() {
    pendingPad = nil
    learningStartedAt = nil
    confirmedPads.removeAll()
    lastHit = nil
    lastError = nil
  }

  @discardableResult
  func replaceMappings(_ mappings: [[Int]]) -> Bool {
    guard Self.validMappings(mappings) else {
      lastError = "Use three distinct pad mappings with at most 16 MIDI notes per pad, from 0 to 127."
      return false
    }
    let normalized = mappings.map { $0.sorted() }
    guard normalized != self.mappings else { return true }
    self.mappings = normalized
    invalidateInput()
    return true
  }

  @discardableResult
  func beginLearning(pad: Int, at time: Double = 0) -> Bool {
    guard (0..<3).contains(pad) else {
      lastError = "Choose hi-hat, snare, or kick to learn a MIDI note."
      return false
    }
    guard selectedSourceID != nil else {
      lastError = "Connect and select a MIDI input before learning a pad."
      return false
    }
    guard time.isFinite, time >= 0 else {
      lastError = "The MIDI learn start time is invalid."
      return false
    }
    pendingPad = pad
    learningStartedAt = time
    lastError = nil
    return true
  }

  func cancelLearning() {
    pendingPad = nil
    learningStartedAt = nil
    lastError = nil
  }

  @discardableResult
  func receiveMIDI(note: Int, velocity: Int, sourceID: Int32, at time: Double) -> DrumxKitReceipt? {
    guard selectedSourceID == sourceID, (0...127).contains(note), validStrike(velocity, time) else { return nil }
    var change: DrumxKitMappingChange?
    if let pad = pendingPad {
      if let armed = learningStartedAt, time < armed {
        let hit = DrumxKitHit(note: note, velocity: velocity, sourceID: sourceID,
          pad: mappings.firstIndex(where: { $0.contains(note) }), receivedAt: time)
        lastHit = hit
        return DrumxKitReceipt(hit: hit, mappingChange: nil)
      }
      let existing = mappings[pad].contains(note)
      if !existing && mappings[pad].count >= Self.maximumAliasesPerPad {
        lastError = "That pad already has 16 note aliases. Cancel learning or revise its mapping before adding another."
        let hit = DrumxKitHit(note: note, velocity: velocity, sourceID: sourceID,
          pad: mappings.firstIndex(where: { $0.contains(note) }), receivedAt: time)
        lastHit = hit
        return DrumxKitReceipt(hit: hit, mappingChange: nil)
      }
      var updated = mappings
      let conflicts = (0..<3).filter { $0 != pad && updated[$0].contains(note) }
      for other in conflicts { updated[other].removeAll { $0 == note } }
      if !existing { updated[pad].append(note); updated[pad].sort() }
      // Reassignment can invalidate an earlier check of a different pad.
      for other in conflicts { confirmedPads.remove(other) }
      confirmedPads.remove(pad)
      mappings = updated
      pendingPad = nil
      learningStartedAt = nil
      lastError = nil
      change = DrumxKitMappingChange(pad: pad, note: note, wasAlreadyMapped: existing,
        removedFromPads: conflicts, mappings: updated)
    }
    let pad = mappings.firstIndex(where: { $0.contains(note) })
    if let pad { confirmedPads.insert(pad) }
    let hit = DrumxKitHit(note: note, velocity: velocity, sourceID: sourceID, pad: pad, receivedAt: time)
    lastHit = hit
    return DrumxKitReceipt(hit: hit, mappingChange: change)
  }

  @discardableResult
  func receiveKeyboard(pad: Int, velocity: Int, at time: Double) -> DrumxKitReceipt? {
    guard selectedSourceID == nil, (0..<3).contains(pad), validStrike(velocity, time) else { return nil }
    confirmedPads.insert(pad)
    let hit = DrumxKitHit(note: nil, velocity: velocity, sourceID: nil, pad: pad, receivedAt: time)
    lastHit = hit
    return DrumxKitReceipt(hit: hit, mappingChange: nil)
  }

  private func validStrike(_ velocity: Int, _ time: Double) -> Bool {
    (1...127).contains(velocity) && time.isFinite && time >= 0
  }

  private static func validMappings(_ mappings: [[Int]]) -> Bool {
    guard mappings.count == 3, mappings.allSatisfy({ $0.count <= maximumAliasesPerPad }),
      mappings.flatMap({ $0 }).allSatisfy({ (0...127).contains($0) }) else { return false }
    let notes = mappings.flatMap { $0 }
    // Empty pads are allowed after an explicit reassignment, but cannot check ready.
    return Set(notes).count == notes.count
  }
}
