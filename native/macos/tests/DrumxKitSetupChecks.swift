import Foundation

private var checks = 0
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private func sourceChecks() {
  let setup = DrumxKitSetup()
  check(!setup.isMIDISelected && !setup.isReady, "source presence does not manufacture readiness")
  check(!setup.beginLearning(pad: 0) && setup.pendingPad == nil, "keyboard mode cannot arm MIDI learning")
  for pad in 0..<3 { _ = setup.receiveKeyboard(pad: pad, velocity: 80, at: 1) }
  check(setup.isReady && setup.lastHit?.note == nil && setup.lastHit?.sourceID == nil,
        "keyboard checks are explicitly keyboard receipts")
  setup.selectSource(41)
  check(setup.confirmedPads.isEmpty && setup.lastHit == nil && !setup.isReady, "selecting MIDI clears keyboard evidence")
  check(setup.receiveKeyboard(pad: 0, velocity: 100, at: 2) == nil, "keyboard cannot confirm a selected MIDI kit")
  check(setup.receiveMIDI(note: 42, velocity: 100, sourceID: 42, at: 2) == nil, "wrong source cannot create a receipt")
  check(setup.confirmedPads.isEmpty && setup.lastHit == nil, "foreign input leaves checks and raw display unchanged")
  let raw = setup.receiveMIDI(note: 99, velocity: 64, sourceID: 41, at: 3)
  check(raw?.hit.note == 99 && raw?.hit.velocity == 64 && raw?.hit.sourceID == 41 && raw?.hit.pad == nil,
        "unmapped hit retains raw note, velocity and source without inventing a pad")
  check(setup.confirmedPads.isEmpty && setup.lastHit == raw?.hit, "unmapped receipt is visible but not a readiness check")
  for note in [42, 38, 36] { _ = setup.receiveMIDI(note: note, velocity: 100, sourceID: 41, at: 4) }
  check(setup.isReady, "three mapped hits from the selected source check the kit")
  setup.selectSource(41)
  check(setup.isReady, "refreshing the same source identity preserves valid checks")
  _ = setup.beginLearning(pad: 1)
  setup.selectSource(43)
  check(setup.pendingPad == nil && setup.confirmedPads.isEmpty && setup.lastHit == nil, "source change cancels learn and clears stale receipts")
  _ = setup.beginLearning(pad: 2)
  _ = setup.receiveMIDI(note: 36, velocity: 100, sourceID: 43, at: 5)
  _ = setup.beginLearning(pad: 0)
  setup.invalidateInput()
  check(setup.pendingPad == nil && !setup.isReady && setup.lastHit == nil, "same-ID disconnect/reconnect can explicitly invalidate checks and learning")
  setup.selectSource(nil)
  check(setup.receiveMIDI(note: 42, velocity: 100, sourceID: 43, at: 6) == nil,
        "disconnected source cannot contaminate keyboard setup")
}

private func mappingChecks() {
  let setup = DrumxKitSetup()
  setup.selectSource(1)
  _ = setup.receiveMIDI(note: 38, velocity: 100, sourceID: 1, at: 1)
  _ = setup.receiveMIDI(note: 36, velocity: 100, sourceID: 1, at: 1)
  check(setup.beginLearning(pad: 0), "selected kit can arm a pad")
  let added = setup.receiveMIDI(note: 22, velocity: 55, sourceID: 1, at: 2)
  check(setup.mappings[0] == [22, 42, 44, 46], "learning preserves all existing hi-hat articulation aliases")
  check(added?.mappingChange?.mappings == setup.mappings && added?.mappingChange?.removedFromPads == [],
        "learn receipt exposes the complete resulting mapping and conflicts")
  check(added?.mappingChange?.wasAlreadyMapped == false && setup.pendingPad == nil, "successful learn is one-shot")
  check(setup.isReady, "learning a pad preserves unaffected source checks")
  _ = setup.beginLearning(pad: 0)
  let repeated = setup.receiveMIDI(note: 42, velocity: 88, sourceID: 1, at: 3)
  check(repeated?.mappingChange?.wasAlreadyMapped == true && setup.mappings[0].count == 4,
        "learning an existing alias does not duplicate it")
  _ = setup.beginLearning(pad: 0)
  let moved = setup.receiveMIDI(note: 38, velocity: 120, sourceID: 1, at: 4)
  check(moved?.mappingChange?.removedFromPads == [1] && setup.mappings[1] == [40],
        "reassigned note is removed only from its prior owner and reports the conflict")
  check(setup.mappings[0] == [22, 38, 42, 44, 46] && setup.mappings[2] == [35, 36],
        "reassignment retains every unrelated alias")
  check(!setup.confirmedPads.contains(1) && setup.confirmedPads.contains(0) && setup.confirmedPads.contains(2),
        "conflicted pad must be checked again; untouched pad stays checked")
  _ = setup.beginLearning(pad: 2)
  setup.cancelLearning()
  let before = setup.mappings
  let cancelled = setup.receiveMIDI(note: 99, velocity: 100, sourceID: 1, at: 5)
  check(cancelled?.mappingChange == nil && setup.mappings == before, "cancelled learn cannot capture the next played note")
  _ = setup.beginLearning(pad: 1)
  check(setup.receiveMIDI(note: 50, velocity: 100, sourceID: 2, at: 6) == nil && setup.pendingPad == 1,
        "foreign-source packet cannot complete learning")
  check(setup.receiveMIDI(note: 50, velocity: 0, sourceID: 1, at: 7) == nil && setup.pendingPad == 1,
        "note-off velocity cannot learn a mapping")
  check(setup.replaceMappings([[42], [38], [36]]), "valid explicit mapping replacement accepted")
  check(setup.pendingPad == nil && setup.confirmedPads.isEmpty, "mapping replacement resets checks and pending learn")
  _ = setup.beginLearning(pad: 0)
  _ = setup.receiveMIDI(note: 38, velocity: 90, sourceID: 1, at: 8)
  check(setup.mappings[1].isEmpty && !setup.confirmedPads.contains(1), "moving a sole alias leaves its former pad unchecked")
  let beforeQueuedHit = setup.mappings
  _ = setup.beginLearning(pad: 2, at: 10)
  let queued = setup.receiveMIDI(note: 55, velocity: 90, sourceID: 1, at: 9.9)
  check(queued?.hit.note == 55 && queued?.mappingChange == nil && setup.pendingPad == 2,
        "pre-arm packet stays visible but cannot complete new learning")
  check(setup.mappings == beforeQueuedHit, "queued old strike cannot change the intended mapping")
  check(setup.receiveMIDI(note: 56, velocity: 90, sourceID: 1, at: 10.1)?.mappingChange?.pad == 2,
        "a strike captured after arming can complete learning")
}

private func validationChecks() {
  let setup = DrumxKitSetup()
  setup.selectSource(1)
  let original = setup.mappings
  let invalid = [[], [[42], [38]], [[42], [38], [36], []],
                 [[42, 42], [38], [36]], [[42], [42], [36]],
                 [[-1], [38], [36]], [[128], [38], [36]],
                 [Array(0...16), [38], [36]]]
  for mapping in invalid {
    check(!setup.replaceMappings(mapping), "invalid or overlapping mappings rejected")
    check(setup.mappings == original, "invalid replacement cannot mutate a valid mapping")
  }
  let invalidLoad = DrumxKitSetup(mappings: [[42], [42], [36]])
  check(invalidLoad.mappings == DrumxKitSetup.defaultMappings && invalidLoad.lastError != nil,
        "invalid loaded mapping falls back explicitly to standard notes")
  for (note, velocity, time) in [(-1, 90, 1.0), (128, 90, 1), (42, -1, 1),
                                 (42, 128, 1), (42, 0, 1), (42, 90, -1), (42, 90, Double.nan)] {
    check(setup.receiveMIDI(note: note, velocity: velocity, sourceID: 1, at: time) == nil,
          "invalid raw packet cannot mutate setup")
  }
  check(setup.lastHit == nil && setup.confirmedPads.isEmpty, "rejected packets do not fabricate raw display or readiness")
  check(!setup.beginLearning(pad: -1) && !setup.beginLearning(pad: 3), "invalid learn target rejected")
  check(!setup.beginLearning(pad: 0, at: .nan) && !setup.beginLearning(pad: 0, at: -1),
        "invalid learn timestamp cannot arm a mapping")
  let full = DrumxKitSetup(mappings: [Array(0..<16), [38], [36]])
  full.selectSource(1)
  _ = full.beginLearning(pad: 0)
  let before = full.mappings
  let overflow = full.receiveMIDI(note: 38, velocity: 100, sourceID: 1, at: 1)
  check(full.mappings == before && full.pendingPad == 0 && full.lastError != nil,
        "alias limit fails atomically without stealing another pad's note")
  check(overflow?.hit.note == 38 && overflow?.mappingChange == nil && full.confirmedPads.isEmpty,
        "failed learn still exposes raw input but does not validate the wrong physical pad")
  let existing = full.receiveMIDI(note: 0, velocity: 1, sourceID: 1, at: 2)
  check(existing?.mappingChange?.wasAlreadyMapped == true && full.pendingPad == nil,
        "full mapping can still relearn an existing alias at minimum strike velocity")
  full.selectSource(nil)
  check(full.receiveKeyboard(pad: 4, velocity: 100, at: 3) == nil
          && full.receiveKeyboard(pad: 0, velocity: 0, at: 3) == nil,
        "keyboard validation rejects invalid pads and non-strikes")
}

@main enum DrumxKitSetupChecks {
  static func main() {
    sourceChecks(); mappingChecks(); validationChecks()
    print("Drumx MIDI kit setup: \(checks) checks passed.")
  }
}
