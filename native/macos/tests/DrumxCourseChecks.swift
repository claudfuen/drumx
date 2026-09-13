import Foundation

private var checks = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError("FAIL: \(message)") }
}

private func notes(_ id: String, pad: Int) -> [DrumxLessonNote] {
  guard let lesson = DrumxCourse.lesson(id: id) else { fatalError("Missing lesson \(id)") }
  return lesson.events.filter { $0.pad == pad }
}

private func beats(_ id: String, pad: Int) -> [Double] {
  notes(id, pad: pad).map(\.beat)
}

private func catalogChecks() {
  let lessons = DrumxCourse.lessons
  check(lessons.count == 20, "foundation and vocabulary course has twenty authored lessons")
  check(DrumxCourse.chapterTitles.count == 5, "five coherent chapters")
  check(Set(lessons.map(\.id)).count == lessons.count, "lesson IDs are unique")
  check(Set(lessons.map(\.version)).count == lessons.count, "lesson versions are unique")
  check(DrumxCourse.lesson(id: "not-a-lesson") == nil, "unknown IDs do not silently select a lesson")
  check(DrumxCourse.lesson(id: "") == nil, "empty ID has no lesson")

  for chapter in DrumxCourse.chapterTitles.indices {
    check(lessons.filter { $0.chapter == chapter }.count == 4,
      "chapter \(chapter) has a complete four-lesson sequence")
  }
  check(lessons.map(\.chapter) == lessons.map(\.chapter).sorted(), "chapters stay in sequence")

  for lesson in lessons {
    check(DrumxCourse.lesson(id: lesson.id)?.version == lesson.version, "lookup preserves identity")
    check(lesson.version == "\(lesson.id)-v1", "stable first-version naming for \(lesson.id)")
    check(DrumxCourse.chapterTitles.indices.contains(lesson.chapter), "valid chapter")
    check(lesson.suggestedBPM.isFinite && (48...144).contains(lesson.suggestedBPM),
      "suggested tempo is supported by the current player")
    check(lesson.practiceMinutes.hasPrefix("Suggested "), "practice estimate is explicitly a suggestion")
    let copy = [lesson.id, lesson.title, lesson.subtitle, lesson.objective, lesson.explanation,
      lesson.counts, lesson.techniqueTip, lesson.readingQuestion]
    check(copy.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
      "complete teaching copy for \(lesson.id)")
    check(lesson.readingChoices.count >= 2, "reading question has alternatives")
    check(Set(lesson.readingChoices).count == lesson.readingChoices.count, "distinct reading choices")
    check(lesson.readingChoices.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
      "reading choices are not empty")
    check(lesson.readingChoices.indices.contains(lesson.readingAnswer), "reading answer is in range")
    check(!lesson.events.isEmpty, "exercise contains authored events")

    var previousBeat = -1.0
    var previousPad = -1
    var occupied = Set<String>()
    for note in lesson.events {
      check(note.beat.isFinite && note.beat >= 0 && note.beat < 4, "event stays in one four-beat bar")
      check((note.beat * 2).rounded() == note.beat * 2, "authored course uses the supported quarter/eighth grid")
      check((0...2).contains(note.pad), "event uses an available instrument")
      check((1...127).contains(note.velocity), "audible MIDI velocity")
      check(note.hand == nil || note.hand == "R" || note.hand == "L", "valid optional sticking hint")
      check(note.pad != 2 || note.hand == nil, "bass-drum note does not assign a hand")
      check(note.beat > previousBeat || (note.beat == previousBeat && note.pad > previousPad),
        "events have deterministic beat/pad order")
      check(occupied.insert("\(note.beat):\(note.pad)").inserted,
        "no duplicate target for a pad at the same beat")
      previousBeat = note.beat
      previousPad = note.pad
    }
  }
}

private func musicalChecks() {
  let eighths: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
  let expectedPads: [String: Set<Int>] = [
    "find-the-pulse": [1], "eighth-note-hat": [0], "backbeat-rests": [1],
    "kick-pulse": [2], "hat-and-kick": [0, 2], "hat-and-snare": [0, 1],
    "first-backbeat": [0, 1, 2], "quarter-note-groove": [0, 1, 2],
    "alternating-eighths": [1], "kick-on-the-and": [0, 1, 2],
    "leave-a-gap": [0, 1, 2], "groove-to-fill": [0, 1, 2],
    "double-stroke-open-roll": [1], "move-the-doubles": [0, 1],
    "single-paradiddle": [1], "move-the-paradiddle": [0, 1],
    "foot-under-paradiddle": [0, 1, 2], "four-on-the-floor": [0, 1, 2],
    "lead-into-one": [0, 1, 2], "between-the-beats": [0, 1, 2],
  ]
  check(Set(expectedPads.keys) == Set(DrumxCourse.lessons.map(\.id)), "instrument contract covers the course")
  for lesson in DrumxCourse.lessons {
    check(Set(lesson.events.map(\.pad)) == expectedPads[lesson.id], "intended instruments for \(lesson.id)")
  }
  check(beats("find-the-pulse", pad: 1) == [0, 1, 2, 3], "pulse has four quarter notes")
  check(beats("eighth-note-hat", pad: 0) == eighths, "eight hi-hat eighths")
  check(beats("backbeat-rests", pad: 1) == [1, 3], "snare on counts 2 and 4, with rests")
  check(beats("kick-pulse", pad: 2) == [0, 2], "kick on counts 1 and 3")
  check(beats("hat-and-kick", pad: 0) == eighths && beats("hat-and-kick", pad: 2) == [0, 2],
    "first coordination layer preserves hat and kick")
  check(beats("hat-and-snare", pad: 0) == eighths && beats("hat-and-snare", pad: 1) == [1, 3],
    "second coordination layer preserves hat and snare")
  check(beats("quarter-note-groove", pad: 0) == [0, 1, 2, 3], "quarter-hat variant leaves the ands empty")
  check(beats("alternating-eighths", pad: 1) == eighths, "fill preparation uses eighths")
  check(notes("alternating-eighths", pad: 1).map(\.hand) == ["R", "L", "R", "L", "R", "L", "R", "L"],
    "alternating snare sticking matches the explanation")
  check(beats("kick-on-the-and", pad: 2) == [0, 2, 2.5], "extra kick is on and of 3")
  check(beats("kick-on-the-and", pad: 1) == [1, 3], "extra kick preserves the backbeat")
  check(beats("leave-a-gap", pad: 0) == [0, 0.5, 1, 1.5, 2, 2.5], "hi-hat leaves beat 4 open")
  check(DrumxCourse.lesson(id: "leave-a-gap")!.events.allSatisfy { $0.beat != 3.5 },
    "and of 4 is silent on every instrument")
  check(beats("groove-to-fill", pad: 0) == [0, 0.5, 1, 1.5], "hi-hat stops before the fill")
  check(beats("groove-to-fill", pad: 2) == [0], "fill replaces the second kick")
  check(beats("groove-to-fill", pad: 1) == [1, 2, 2.5, 3, 3.5], "backbeat leads to four fill strokes")
  check(notes("groove-to-fill", pad: 1).filter { $0.beat >= 2 }.map(\.hand) == ["R", "L", "R", "L"],
    "fill begins right-led on beat 3")
}

private func originalCourseCompatibilityChecks() {
  let originalIDs = [
    "find-the-pulse", "eighth-note-hat", "backbeat-rests", "kick-pulse",
    "hat-and-kick", "hat-and-snare", "first-backbeat", "quarter-note-groove",
    "alternating-eighths", "kick-on-the-and", "leave-a-gap", "groove-to-fill",
  ]
  check(Array(DrumxCourse.lessons.prefix(12)).map(\.id) == originalIDs,
    "all original IDs retain their positions before the added lessons")
  // Frozen from the original course. Each item is eighth tick:pad:hand:velocity,
  // so new content cannot silently alter saved musical conditions or demo sound.
  let originalEvents = [
    "find-the-pulse": "0:1:R:100 2:1:L:100 4:1:R:100 6:1:L:100",
    "eighth-note-hat": "0:0:R:90 1:0:R:78 2:0:R:90 3:0:R:78 4:0:R:90 5:0:R:78 6:0:R:90 7:0:R:78",
    "backbeat-rests": "2:1:L:108 6:1:L:108",
    "kick-pulse": "0:2:-:112 4:2:-:112",
    "hat-and-kick": "0:0:R:90 0:2:-:112 1:0:R:78 2:0:R:90 3:0:R:78 4:0:R:90 4:2:-:112 5:0:R:78 6:0:R:90 7:0:R:78",
    "hat-and-snare": "0:0:R:90 1:0:R:78 2:0:R:90 2:1:L:108 3:0:R:78 4:0:R:90 5:0:R:78 6:0:R:90 6:1:L:108 7:0:R:78",
    "first-backbeat": "0:0:R:90 0:2:-:112 1:0:R:78 2:0:R:90 2:1:L:108 3:0:R:78 4:0:R:90 4:2:-:112 5:0:R:78 6:0:R:90 6:1:L:108 7:0:R:78",
    "quarter-note-groove": "0:0:R:90 0:2:-:112 2:0:R:90 2:1:L:108 4:0:R:90 4:2:-:112 6:0:R:90 6:1:L:108",
    "alternating-eighths": "0:1:R:100 1:1:L:100 2:1:R:100 3:1:L:100 4:1:R:100 5:1:L:100 6:1:R:100 7:1:L:100",
    "kick-on-the-and": "0:0:R:90 0:2:-:112 1:0:R:78 2:0:R:90 2:1:L:108 3:0:R:78 4:0:R:90 4:2:-:112 5:0:R:78 5:2:-:112 6:0:R:90 6:1:L:108 7:0:R:78",
    "leave-a-gap": "0:0:R:90 0:2:-:112 1:0:R:78 2:0:R:90 2:1:L:108 3:0:R:78 4:0:R:90 4:2:-:112 5:0:R:78 6:1:L:108",
    "groove-to-fill": "0:0:R:90 0:2:-:112 1:0:R:78 2:0:R:90 2:1:L:108 3:0:R:78 4:1:R:100 5:1:L:100 6:1:R:100 7:1:L:100",
  ]
  for (index, id) in originalIDs.enumerated() {
    let lesson = DrumxCourse.lessons[index]
    let fingerprint = lesson.events.map {
      "\(Int($0.beat * 2)):\($0.pad):\($0.hand ?? "-"):\($0.velocity)"
    }.joined(separator: " ")
    check(lesson.version == "\(id)-v1", "original version remains stable for \(id)")
    check(lesson.chapter == index / 4, "original chapter remains stable for \(id)")
    check(fingerprint == originalEvents[id], "all original event fields remain unchanged for \(id)")
  }
  check(DrumxCourse.lesson(id: "alternating-eighths")!.title == "Single Stroke Roll",
    "existing singles lesson teaches the conventional name without duplicating its timeline")
}

private func vocabularyChecks() {
  let additions = Array(DrumxCourse.lessons.dropFirst(12))
  check(additions.map(\.id) == ["double-stroke-open-roll", "move-the-doubles",
    "single-paradiddle", "move-the-paradiddle", "foot-under-paradiddle",
    "four-on-the-floor", "lead-into-one", "between-the-beats"],
    "new lessons follow the authored preparation and application sequence")
  check(Array(DrumxCourse.chapterTitles.suffix(2)) == ["Hands and rudiments", "Make the groove your own"],
    "new chapters separate sticking vocabulary from further coordination")
  check(additions.map(\.suggestedBPM) == [60, 60, 60, 60, 60, 60, 60, 48],
    "offbeat coordination has its own slower starting condition")
  check(additions.map { $0.events.count } == [8, 8, 8, 8, 10, 14, 13, 8],
    "every new bar has its exact independent target count")

  let eighths: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
  let doubles = DrumxCourse.lesson(id: "double-stroke-open-roll")!
  let paradiddle = DrumxCourse.lesson(id: "single-paradiddle")!
  check(doubles.events.map(\.beat) == eighths && paradiddle.events.map(\.beat) == eighths,
    "rudiment introductions retain even eighth-note timing")
  check(doubles.events.map(\.hand) == ["R", "R", "L", "L", "R", "R", "L", "L"],
    "double-stroke introduction contains two strokes per suggested hand")
  check(paradiddle.events.map(\.hand) == ["R", "L", "R", "R", "L", "R", "L", "L"],
    "single paradiddle contains the full right-led and left-led groups")
  check(doubles.events.allSatisfy { $0.velocity == 100 } && paradiddle.events.allSatisfy { $0.velocity == 100 },
    "ungraded introductory doubles and paradiddle do not secretly require accents")

  check(beats("move-the-doubles", pad: 0) == [0, 0.5, 2, 2.5]
    && beats("move-the-doubles", pad: 1) == [1, 1.5, 3, 3.5],
    "doubles application alternates pairs of hats and snares")
  check(beats("move-the-paradiddle", pad: 0) == [0, 1, 1.5, 2.5]
    && beats("move-the-paradiddle", pad: 1) == [0.5, 2, 3, 3.5],
    "paradiddle application has a distinct instrument timeline")
  for id in ["move-the-doubles", "move-the-paradiddle", "foot-under-paradiddle"] {
    check(notes(id, pad: 0).allSatisfy { $0.hand == "R" }
      && notes(id, pad: 1).allSatisfy { $0.hand == "L" },
      "orchestrated sticking suggestions match the authored surface for \(id)")
  }
  let orchestrated = DrumxCourse.lesson(id: "move-the-paradiddle")!
  let coordinated = DrumxCourse.lesson(id: "foot-under-paradiddle")!
  check(coordinated.events.filter { $0.pad != 2 } == orchestrated.events,
    "adding the foot preserves every hand-study event")
  check(beats("foot-under-paradiddle", pad: 2) == [0, 2], "foot joins counts 1 and 3")
  check(coordinated.events.filter { $0.beat == 0 }.map(\.pad) == [0, 2]
    && coordinated.events.filter { $0.beat == 2 }.map(\.pad) == [1, 2],
    "foot meets hat on 1 and snare on 3")
  check(beats("four-on-the-floor", pad: 2) == [0, 1, 2, 3]
    && beats("four-on-the-floor", pad: 0) == eighths
    && beats("four-on-the-floor", pad: 1) == [1, 3],
    "four on the floor keeps the familiar hands with a quarter-note foot")
  check(beats("lead-into-one", pad: 2) == [0, 2, 3.5], "anticipating kick is the and of 4")
  let firstBackbeat = DrumxCourse.lesson(id: "first-backbeat")!
  check(DrumxCourse.lesson(id: "lead-into-one")!.events.filter { $0.pad != 2 }
    == firstBackbeat.events.filter { $0.pad != 2 }, "anticipation preserves the original hand pattern")
  check(beats("between-the-beats", pad: 0) == [0.5, 1.5, 2.5, 3.5]
    && beats("between-the-beats", pad: 1) == [1, 3]
    && beats("between-the-beats", pad: 2) == [0, 2],
    "offbeat hats alternate with the unchanged numbered-beat snare and kick")
  check(DrumxCourse.lesson(id: "between-the-beats")!.events.filter { $0.beat == 0 }.map(\.pad) == [2],
    "offbeat study begins with an upper-voice rest over the kick")

  let minutes = DrumxCourse.lessons.compactMap { Int($0.practiceMinutes.split(separator: " ")[1]) }
  check(minutes.count == 20 && minutes.reduce(0, +) == 174,
    "published suggested practice total agrees with the course, not unique-content duration")
}

private func backbeatCompatibilityChecks() {
  guard let backbeat = DrumxCourse.lesson(id: "first-backbeat") else { fatalError("Missing legacy backbeat") }
  check(backbeat.version == "first-backbeat-v1", "legacy attempts keep the original lesson version")
  check(backbeat.events.count == 12, "legacy bar has twelve independent targets")
  let expected: [(Double, Int)] = [
    (0, 0), (0, 2), (0.5, 0), (1, 0), (1, 1), (1.5, 0),
    (2, 0), (2, 2), (2.5, 0), (3, 0), (3, 1), (3.5, 0),
  ]
  for (note, old) in zip(backbeat.events, expected) {
    check(note.beat == old.0 && note.pad == old.1, "authored backbeat matches the original scoring grid")
    let expectedVelocity = note.pad == 1 ? 108 : note.pad == 2 ? 112
      : note.beat.rounded(.down) == note.beat ? 90 : 78
    check(note.velocity == expectedVelocity, "legacy demonstration velocities stay intact")
  }
}

@main
private struct DrumxCourseChecks {
  static func main() {
    catalogChecks()
    musicalChecks()
    originalCourseCompatibilityChecks()
    vocabularyChecks()
    backbeatCompatibilityChecks()
    print("Drumx course checks passed: \(checks)")
  }
}
