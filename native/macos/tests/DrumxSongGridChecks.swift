import Foundation

@main enum DrumxSongGridChecks {
  static var count = 0

  static func check(_ value: @autoclosure () -> Bool, _ message: String) {
    count += 1
    precondition(value(), message)
  }

  static func near(_ value: Double, _ expected: Double, _ message: String) {
    check(abs(value - expected) < 0.00000001, message)
  }

  static func main() throws {
    let straight = [DrumxSongTempo(tick: 0, timeSeconds: 0, bpm: 120)]
    let common = [DrumxSongTimeSignature(tick: 0, numerator: 4, denominator: 4)]
    let commonGrid = DrumxSongGrid.lines(resolution: 480, tempos: straight,
      signatures: common, lead: 0, duration: 5)
    check(commonGrid.count == 11, "4/4 emits quarter-note beats through the full duration")
    for (index, line) in commonGrid.enumerated() {
      near(line.time, Double(index) / 2, "4/4 quarter-note lines follow source tempo")
      check(line.kind == (index % 4 == 0 ? .bar : .beat), "4/4 downbeats recur every four quarters")
    }

    // Independent Harmonix The Kill oracle: MIDI PPQN480,655736us/quarter,
    //6/8. Tick4320 is the fourth downbeat and first authored note at5.901624s.
    let killQuarter = 0.655736
    let kill = DrumxSongGrid.lines(resolution: 480,
      tempos: [DrumxSongTempo(tick: 0, timeSeconds: 0, bpm: 60 / killQuarter)],
      signatures: [DrumxSongTimeSignature(tick: 0, numerator: 6, denominator: 8)],
      lead: 0, duration: 7)
    for (index, line) in kill.enumerated() {
      near(line.time, Double(index) * killQuarter / 2, "6/8 eighth-note spacing follows the real tempo")
      let expected: DrumxSongGridKind = index % 6 == 0 ? .bar : index % 3 == 0 ? .beat : .subdivision
      check(line.kind == expected, "6/8 groups two dotted-quarter pulses with eighth subdivisions")
    }
    near(kill[18].time, 5.901624, "The Kill first authored note meets its actual bar line")
    check(kill[18].kind == .bar, "The Kill first note is a downbeat, independent of a4/4 assumption")

    let changingTempo = DrumxSongGrid.lines(resolution: 480,
      tempos: straight + [DrumxSongTempo(tick: 720, timeSeconds: 0.75, bpm: 60)],
      signatures: common, lead: 0, duration: 4)
    for (line, expected) in zip(changingTempo, [0.0, 0.5, 1.25, 2.25, 3.25]) {
      near(line.time, expected, "A tempo change between beats integrates both tempo spans")
    }
    check(changingTempo.last?.kind == .bar, "Tempo changes retain the current bar position")

    let delayed = [DrumxSongTempo(tick: 0, timeSeconds: -0.75, bpm: 120)]
    let shifted = DrumxSongGrid.lines(resolution: 480, tempos: delayed, signatures: common, lead: 0.75, duration: 2)
    check(shifted == Array(commonGrid.prefix(5)), "Negative chart offset and shared note lead apply exactly once")
    let cropped = DrumxSongGrid.lines(resolution: 480, tempos: delayed, signatures: common, lead: 0, duration: 1.25)
    near(cropped[0].time, 0.25, "Invisible negative grid positions are skipped without resetting the meter")
    check(cropped[0].kind == .beat && cropped.last?.kind == .bar, "Clipping a negative offset preserves bar identity")

    let halfNotes = DrumxSongGrid.lines(resolution: 192, tempos: straight,
      signatures: [DrumxSongTimeSignature(tick: 0, numerator: 3, denominator: 2)], lead: 0, duration: 3)
    check(halfNotes.map(\.time) == [0, 1, 2, 3], "3/2 counts half notes at the chart's quarter-note BPM")
    check(halfNotes.map(\.kind) == [.bar, .beat, .beat, .bar], "3/2 bar spans three denominator units")
    let fiveEight = DrumxSongGrid.lines(resolution: 480, tempos: straight,
      signatures: [DrumxSongTimeSignature(tick: 0, numerator: 5, denominator: 8)], lead: 0, duration: 1.25)
    check(fiveEight.map(\.time) == [0, 0.25, 0.5, 0.75, 1, 1.25], "5/8 retains eighth-note timing")
    check(fiveEight.filter { $0.kind == .subdivision }.isEmpty, "5/8 does not invent a compound grouping")
    let changingMeter = DrumxSongGrid.lines(resolution: 480, tempos: straight,
      signatures: common + [DrumxSongTimeSignature(tick: 1200, numerator: 3, denominator: 4)],
      lead: 0, duration: 3)
    check(changingMeter.filter { $0.kind == .bar }.map(\.time) == [0, 1.25, 2.75],
      "A meter change between old beats resets the bar exactly at its tick")
    check(changingMeter.map(\.time) == [0, 0.5, 1, 1.25, 1.75, 2.25, 2.75],
      "A new meter starts its own beat sequence without old-meter duplicates")

    check(DrumxSongGrid.lines(resolution: 480, tempos: [], signatures: common, lead: 0, duration: 5).isEmpty,
      "Missing clock metadata cannot produce a misleading fixed-tempo grid")
    check(DrumxSongGrid.lines(resolution: 480, tempos: straight,
      signatures: [DrumxSongTimeSignature(tick: 0, numerator: 4, denominator: 3)], lead: 0, duration: 5).isEmpty,
      "Invalid meter denominator fails safely")
    check(DrumxSongGrid.lines(resolution: 480,
      tempos: straight + [DrumxSongTempo(tick: 480, timeSeconds: 0.25, bpm: 60)],
      signatures: common, lead: 0, duration: 5).isEmpty, "Inconsistent clock anchors cannot misalign notes and grid")
    let bounded = DrumxSongGrid.lines(resolution: 480,
      tempos: [DrumxSongTempo(tick: 0, timeSeconds: 0, bpm: 10000)],
      signatures: [DrumxSongTimeSignature(tick: 0, numerator: 128, denominator: 128)], lead: 0, duration: 7200)
    check(bounded.count == DrumxSongGrid.maximumLineCount, "Extreme valid metadata cannot allocate an unbounded grid")
    check(bounded.allSatisfy { $0.time.isFinite && $0.time >= 0 && $0.time <= 7200 }, "Bounded grid positions remain valid")

    struct Manifest: Decodable {
      let title: String
      let resolution: Int
      let tempos: [DrumxSongTempo]
      let timeSignatures: [DrumxSongTimeSignature]
      let durationSeconds: Double
    }
    for path in CommandLine.arguments.dropFirst() {
      let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
      let started = Date()
      let lines = DrumxSongGrid.lines(resolution: manifest.resolution, tempos: manifest.tempos,
        signatures: manifest.timeSignatures, lead: 0, duration: manifest.durationSeconds)
      check(!lines.isEmpty, "Real imported chart tempo map supplies musical grid lines")
      check(zip(lines, lines.dropFirst()).allSatisfy { $0.time < $1.time }, "Real grid is strictly ordered")
      print("Prepared \(lines.count) musical grid lines for \(manifest.title) in \(String(format: "%.4f", Date().timeIntervalSince(started))) seconds.")
    }
    print("Song grid checks passed: \(count)")
  }
}
