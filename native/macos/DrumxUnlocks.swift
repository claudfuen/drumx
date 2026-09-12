import Foundation

struct DrumxUnlockState {
  let availableIDs: Set<String>
  /// A beginner pattern goal, not a claim of mastery or technique assessment.
  let clearedIDs: Set<String>
  let reasonByID: [String: String]
  let recommendedID: String
  let nextRequiredAction: String
  let practisedIDs: Set<String>
  let readingIDs: Set<String>
  let recallIDs: Set<String>
}

/// Read-only progression. Supply only the selected player's LessonHistory.attempts.
/// LessonAttempt has no transport flags: archive admission is the authority for
/// natural completion and exclusion of demonstrations, not guessed device names.
enum DrumxUnlocks {
  static let minimumBars = 4
  static let minimumMatchPercent = 80

  static func evaluate(course: [DrumxLessonDefinition], history: [LessonAttempt],
                       progress: DrumxProgress) -> DrumxUnlockState {
    guard !course.isEmpty, validCourse(course) else {
      return DrumxUnlockState(availableIDs: [], clearedIDs: [], reasonByID: [:],
        recommendedID: "", nextRequiredAction: "Choose a valid lesson course.",
        practisedIDs: [], readingIDs: [], recallIDs: [])
    }

    // The score model reuses LessonAttempt's archive-value validation. A wrong
    // chart size is checked separately against the authored course below.
    let validHistory = history.filter {
      DrumxRunScore(attempt: $0).isComplete && $0.expected % $0.settings.bars == 0
        && (1...24).contains($0.expected / $0.settings.bars)
    }
    var cleared = Set<String>(), practised = Set<String>(), reading = Set<String>(), recall = Set<String>()
    var preservedThrough = 0
    for (index, lesson) in course.enumerated() {
      let current = validHistory.filter {
        $0.settings.lessonVersion == lesson.version
          && $0.expected == lesson.events.count * $0.settings.bars
      }
      if current.contains(where: {
        $0.settings.bars >= minimumBars && $0.matched * 5 >= $0.expected * 4
      }) { cleared.insert(lesson.id) }

      if progress.practiceEvidence(lessonID: lesson.id, version: lesson.version) != nil
        || current.contains(where: { $0.matched > 0 }) { practised.insert(lesson.id) }
      if progress.readingEvidence(lessonID: lesson.id, version: lesson.version) != nil {
        reading.insert(lesson.id)
      }
      if progress.recallEvidence(lessonID: lesson.id, version: lesson.version) != nil
        || current.contains(where: { $0.matched > 0 && $0.settings.mode == 2 && !$0.settings.liveFeedback }) {
        recall.insert(lesson.id)
      }

      // Retain access, including earlier lessons, when a learner had already reached
      // this point. Older revisions preserve access only; they cannot clear new work.
      let durablePractice = progress.selectedProfile.checks.contains {
        $0.lessonID == lesson.id && $0.kind == .completedPractice
      }
      let archivedPractice = validHistory.contains {
        $0.matched > 0 && archivedVersion($0.settings.lessonVersion, belongsTo: lesson)
          && ($0.settings.lessonVersion != lesson.version
            || $0.expected == lesson.events.count * $0.settings.bars)
      }
      if durablePractice || archivedPractice || progress.selectedProfile.lastLessonID == lesson.id {
        preservedThrough = max(preservedThrough, index)
      }
    }

    var available = Set(course.prefix(preservedThrough + 1).map(\.id))
    var reasons: [String: String] = [:]
    for index in 1..<course.count {
      let previous = course[index - 1], lesson = course[index]
      let chapterTransition = lesson.chapter != previous.chapter
      if available.contains(previous.id), cleared.contains(previous.id),
        !chapterTransition || reading.contains(previous.id) {
        available.insert(lesson.id)
      }
      if !available.contains(lesson.id) {
        reasons[lesson.id] = cleared.contains(previous.id) && chapterTransition && !reading.contains(previous.id)
          ? readingAction(previous) : practiceAction(previous)
      }
    }

    // Continue at the available frontier, respecting preserved access rather than
    // forcing an existing learner back through historical gaps in the archive.
    let frontier = course.lastIndex(where: { available.contains($0.id) })!
    let recommended = course[frontier]
    let action: String
    if !cleared.contains(recommended.id) {
      action = practiceAction(recommended)
    } else if frontier + 1 < course.count,
      course[frontier + 1].chapter != recommended.chapter, !reading.contains(recommended.id) {
      action = readingAction(recommended)
    } else {
      action = "Revisit an available lesson or try it from memory."
    }
    return DrumxUnlockState(availableIDs: available, clearedIDs: cleared, reasonByID: reasons,
      recommendedID: recommended.id, nextRequiredAction: action,
      practisedIDs: practised, readingIDs: reading, recallIDs: recall)
  }

  private static func practiceAction(_ lesson: DrumxLessonDefinition) -> String {
    "Finish \(lesson.title): 4+ bars with at least 80% of notes matched."
  }

  private static func readingAction(_ lesson: DrumxLessonDefinition) -> String {
    "Pass the reading check in \(lesson.title)."
  }

  /// The authored course uses stable `<lesson id>-v<number>` archive versions.
  /// Accept that exact namespace for access preservation, never a fuzzy prefix.
  private static func archivedVersion(_ version: String, belongsTo lesson: DrumxLessonDefinition) -> Bool {
    if version == lesson.version { return true }
    let prefix = lesson.id + "-v"
    guard version.hasPrefix(prefix), lesson.version.hasPrefix(prefix) else { return false }
    let suffix = version.dropFirst(prefix.count)
    let currentSuffix = lesson.version.dropFirst(prefix.count)
    return !suffix.isEmpty && suffix.count <= 6 && !currentSuffix.isEmpty
      && suffix.allSatisfy({ $0 >= "0" && $0 <= "9" })
      && currentSuffix.allSatisfy({ $0 >= "0" && $0 <= "9" })
  }

  private static func validCourse(_ course: [DrumxLessonDefinition]) -> Bool {
    guard Set(course.map(\.id)).count == course.count,
      Set(course.map(\.version)).count == course.count else { return false }
    return course.allSatisfy { lesson in
      guard !lesson.id.isEmpty, !lesson.version.isEmpty, lesson.chapter >= 0,
        !lesson.events.isEmpty, lesson.events.count <= 24,
        lesson.events.allSatisfy({
          $0.beat.isFinite && (0..<4).contains($0.beat) && (0..<3).contains($0.pad)
            && abs($0.beat * 2 - ($0.beat * 2).rounded()) < 0.000001
        }) else { return false }
      return Set(lesson.events.map { Int(($0.beat * 2).rounded()) * 3 + $0.pad }).count == lesson.events.count
    }
  }
}
