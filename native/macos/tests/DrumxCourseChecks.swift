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
  check(lessons.count == 12, "foundation unit has twelve authored lessons")
  check(DrumxCourse.chapterTitles.count == 3, "three coherent chapters")
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
      check((note.beat * 2).rounded() == note.beat * 2, "first unit uses quarter/eighth grids")
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
    backbeatCompatibilityChecks()
    print("Drumx course checks passed: \(checks)")
  }
}
