/// One authored attack in a 4/4 bar. Beat zero is count 1; 0.5 is its "and".
/// Pad indices are the current lab surfaces: 0 hi-hat, 1 snare, 2 kick.
/// Hand is an instruction, never a claim that MIDI identified the striking hand.
struct DrumxLessonNote: Equatable {
  let beat: Double
  let pad: Int
  let hand: String?
  let velocity: Int
}

struct DrumxLessonDefinition {
  let id: String
  let version: String
  /// Zero-based index into DrumxCourse.chapterTitles.
  let chapter: Int
  let title: String
  let subtitle: String
  let objective: String
  let explanation: String
  let counts: String
  let suggestedBPM: Double
  /// Suggested time across repetitions, not the duration of one take.
  let practiceMinutes: String
  let techniqueTip: String
  let events: [DrumxLessonNote]
  let readingQuestion: String
  let readingChoices: [String]
  /// Zero-based index into readingChoices.
  let readingAnswer: Int
}

/// A small foundation unit. Access rules are owned by the progression model.
/// Suggested practice adds up to 96 minutes across repeated short sessions.
/// Playback, scoring, and notation should consume these same one-bar events.
/// Guidance, tempo changes, attempt evidence, and readiness belong to the caller.
enum DrumxCourse {
  static let chapterTitles = [
    "Pulse and counts",
    "Build your backbeat",
    "Read, vary, and remember",
  ]

  private static let quarterBeats: [Double] = [0, 1, 2, 3]
  private static let eighthBeats: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
  private static let eighthCounts = "1 & 2 & 3 & 4 &"

  private static func snare(_ beats: [Double], hand: String = "L") -> [DrumxLessonNote] {
    beats.map { DrumxLessonNote(beat: $0, pad: 1, hand: hand, velocity: 108) }
  }

  private static func kick(_ beats: [Double]) -> [DrumxLessonNote] {
    beats.map { DrumxLessonNote(beat: $0, pad: 2, hand: nil, velocity: 112) }
  }

  private static func hat(_ beats: [Double]) -> [DrumxLessonNote] {
    beats.map { beat in
      DrumxLessonNote(beat: beat, pad: 0, hand: "R",
        velocity: beat.rounded(.down) == beat ? 90 : 78)
    }
  }

  private static func alternatingSnare(_ beats: [Double]) -> [DrumxLessonNote] {
    beats.enumerated().map { index, beat in
      DrumxLessonNote(beat: beat, pad: 1, hand: index.isMultiple(of: 2) ? "R" : "L",
        velocity: 100)
    }
  }

  private static func phrase(_ parts: [DrumxLessonNote]...) -> [DrumxLessonNote] {
    parts.flatMap { $0 }.sorted {
      $0.beat == $1.beat ? $0.pad < $1.pad : $0.beat < $1.beat
    }
  }

  static let lessons: [DrumxLessonDefinition] = [
    DrumxLessonDefinition(
      id: "find-the-pulse", version: "find-the-pulse-v1", chapter: 0,
      title: "Find the pulse", subtitle: "One click, one stroke.",
      objective: "Play four evenly spaced snare strokes and keep counting through the barline.",
      explanation: "A bar groups four quarter-note beats here. Strike the snare on each click while saying 1, 2, 3, 4. After 4, return to 1 without a pause.",
      counts: "1 2 3 4", suggestedBPM: 60, practiceMinutes: "Suggested 6 min",
      techniqueTip: "Let the stick rebound with a light grip. R and L suggest alternating hands; use the sound and a self-check to compare them, because MIDI cannot verify your hands.",
      events: alternatingSnare(quarterBeats),
      readingQuestion: "How many quarter-note beats are in this bar of 4/4?",
      readingChoices: ["Two", "Four", "Eight"], readingAnswer: 1),

    DrumxLessonDefinition(
      id: "eighth-note-hat", version: "eighth-note-hat-v1", chapter: 0,
      title: "Find the and", subtitle: "Two hi-hat notes per beat.",
      objective: "Divide each click into two equal parts on the closed hi-hat.",
      explanation: "The click still marks quarter notes. Add one hi-hat stroke halfway between each pair of clicks. Count every number and every &, saying & as and. Eight evenly spaced notes fill the bar.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Keep the hi-hat closed and use small, relaxed strokes. The right-hand hint is a suggested setup; mirror it if that suits your kit.",
      events: hat(eighthBeats),
      readingQuestion: "Where does the & of 1 fall?",
      readingChoices: ["Halfway between beats 1 and 2", "Together with beat 2", "After beat 4"],
      readingAnswer: 0),

    DrumxLessonDefinition(
      id: "backbeat-rests", version: "backbeat-rests-v1", chapter: 0,
      title: "Give silence its beat", subtitle: "Snare on 2 and 4.",
      objective: "Keep counting four beats while playing only the two backbeats.",
      explanation: "Play the snare on 2 and 4. Beats 1 and 3 are silent in this exercise, but they still take a full beat. Count all four numbers so the spaces have the same length as the played beats.",
      counts: "1 2 3 4", suggestedBPM: 60, practiceMinutes: "Suggested 6 min",
      techniqueTip: "Prepare the next stroke during the rest without squeezing the stick. A rest is a measured part of the rhythm, not permission to lose the count.",
      events: snare([1, 3]),
      readingQuestion: "Which beats carry the snare backbeat in this exercise?",
      readingChoices: ["1 and 3", "Every &", "2 and 4"], readingAnswer: 2),

    DrumxLessonDefinition(
      id: "kick-pulse", version: "kick-pulse-v1", chapter: 0,
      title: "Bring in the bass drum", subtitle: "Kick on 1 and 3.",
      objective: "Place two bass-drum notes inside a steady four-beat count.",
      explanation: "Kick is another name for the bass drum. Play it on 1 and 3, leaving 2 and 4 silent. Continue counting through those rests and into the next bar.",
      counts: "1 2 3 4", suggestedBPM: 60, practiceMinutes: "Suggested 6 min",
      techniqueTip: "Use a comfortable pedal motion and stay balanced on the seat. MIDI records the kick event; it does not assess your foot technique.",
      events: kick([0, 2]),
      readingQuestion: "Which counts are silent in this bass-drum exercise?",
      readingChoices: ["2 and 4", "1 and 3", "None of them"], readingAnswer: 0),

    DrumxLessonDefinition(
      id: "hat-and-kick", version: "hat-and-kick-v1", chapter: 1,
      title: "Hand meets foot", subtitle: "Keep the hat moving over the kick.",
      objective: "Play steady hi-hat eighth notes with kick on 1 and 3.",
      explanation: "Bring the previous two patterns together. The hi-hat plays every number and &, while the kick joins it on 1 and 3. Notes lined up at the same time are played together, not one after another.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Listen for the hi-hat and kick to arrive together on 1 and 3. Keep the hi-hat motion consistent when your foot joins in.",
      events: phrase(hat(eighthBeats), kick([0, 2])),
      readingQuestion: "How do you play vertically aligned hi-hat and kick notes?",
      readingChoices: ["Hi-hat first, then kick", "Both at the same time", "Choose either note"],
      readingAnswer: 1),

    DrumxLessonDefinition(
      id: "hat-and-snare", version: "hat-and-snare-v1", chapter: 1,
      title: "Add the backbeat", subtitle: "Steady hat, snare on 2 and 4.",
      objective: "Keep hi-hat eighth notes even while the other hand adds the snare.",
      explanation: "For this step, leave the bass drum out. Play hi-hat on every number and &, with snare on 2 and 4. The hi-hat continues on the backbeats, so those two counts each contain a pair of simultaneous notes.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Use the hi-hat hand and snare hand comfortably, crossed or open-handed. Do not let the snare stroke interrupt the next hi-hat note.",
      events: phrase(hat(eighthBeats), snare([1, 3])),
      readingQuestion: "What happens on beat 2 in this pattern?",
      readingChoices: ["Only the snare plays", "Only the kick plays", "Hi-hat and snare play together"],
      readingAnswer: 2),

    DrumxLessonDefinition(
      id: "first-backbeat", version: "first-backbeat-v1", chapter: 1,
      title: "Your first backbeat", subtitle: "Three instruments, one groove.",
      objective: "Combine eighth-note hi-hat, kick on 1 and 3, and snare on 2 and 4.",
      explanation: "Put the two coordination steps together. The hi-hat keeps all eight notes. Kick joins on 1 and 3; snare joins on 2 and 4. Repeat the bar, then try hiding a phrase when you feel ready. This is a groove, not a named rudiment.",
      counts: eighthCounts, suggestedBPM: 72, practiceMinutes: "Suggested 12 min",
      techniqueTip: "Keep counting while your limbs share the beat. If the pattern falls apart, return to hand-and-foot or hat-and-snare practice, then recombine them at a comfortable tempo.",
      events: phrase(hat(eighthBeats), snare([1, 3]), kick([0, 2])),
      readingQuestion: "Which description matches this groove?",
      readingChoices: ["Kick on 1 and 3; snare on 2 and 4", "Kick on 2 and 4; snare on 1 and 3", "Snare on every &"],
      readingAnswer: 0),

    DrumxLessonDefinition(
      id: "quarter-note-groove", version: "quarter-note-groove-v1", chapter: 1,
      title: "Give the groove more space", subtitle: "Four hi-hat notes instead of eight.",
      objective: "Change the hi-hat to quarter notes while keeping the kick and snare pattern.",
      explanation: "Keep kick on 1 and 3 and snare on 2 and 4. This time, strike the hi-hat only on the four numbered beats. Count the & between them without adding a hit. The pulse stays the same even though the pattern has fewer notes.",
      counts: eighthCounts, suggestedBPM: 72, practiceMinutes: "Suggested 6 min",
      techniqueTip: "Let the spaces remain open. Mentally comparing this bar with the previous groove can help you hear the difference between quarter and eighth notes.",
      events: phrase(hat(quarterBeats), snare([1, 3]), kick([0, 2])),
      readingQuestion: "How many hi-hat strokes are in this version of the bar?",
      readingChoices: ["Eight", "Four", "Two"], readingAnswer: 1),

    DrumxLessonDefinition(
      id: "alternating-eighths", version: "alternating-eighths-v1", chapter: 2,
      title: "Let your hands take turns", subtitle: "Snare eighth notes, R then L.",
      objective: "Play eight evenly spaced snare strokes with suggested alternating sticking.",
      explanation: "Move the eighth-note rhythm to the snare. Play R L R L R L R L while counting 1 & 2 & 3 & 4 &. Each hand supplies every other note. This prepares a short fill; deeper rudiment technique comes in later units.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Match the sound and spacing of the two hands. R/L is a self-check: the same snare MIDI note cannot tell the app which hand struck it.",
      events: alternatingSnare(eighthBeats),
      readingQuestion: "Following R L sticking, which hand plays the & of 1?",
      readingChoices: ["Right", "Both", "Left"], readingAnswer: 2),

    DrumxLessonDefinition(
      id: "kick-on-the-and", version: "kick-on-the-and-v1", chapter: 2,
      title: "Kick on the and", subtitle: "One extra note changes the feel.",
      objective: "Add a kick on the & of 3 without changing the hand pattern.",
      explanation: "Return to the full eighth-note backbeat. Keep kick on 1 and 3, then add one on the & of 3. Snare stays on 2 and 4. Say 3 and 4 evenly so the extra kick fits between the two numbered beats.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 10 min",
      techniqueTip: "Keep your hands on their original rhythm when the extra kick arrives. Lower the tempo if you need more time between the two pedal strokes.",
      events: phrase(hat(eighthBeats), snare([1, 3]), kick([0, 2, 2.5])),
      readingQuestion: "Where is the extra kick compared with Your first backbeat?",
      readingChoices: ["On beat 2", "On the & of 3", "On the & of 4"], readingAnswer: 1),

    DrumxLessonDefinition(
      id: "leave-a-gap", version: "leave-a-gap-v1", chapter: 2,
      title: "Keep counting through a gap", subtitle: "A quiet ending, a clear return.",
      objective: "Leave space around the final snare, then return to the next bar's first beat.",
      explanation: "Play the basic groove through the & of 3. On beat 4, play only snare; on the & of 4, play nothing. Keep counting 4 and 1 through the gap. Read the space first, then try the phrase with less guidance.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Keep the count moving while the hi-hat is silent. A neutral flash from your own hit is not a note to follow; listen to the click and recall what comes next.",
      events: phrase(hat([0, 0.5, 1, 1.5, 2, 2.5]), snare([1, 3]), kick([0, 2])),
      readingQuestion: "What should you play on the & of 4 in this bar?",
      readingChoices: ["Nothing; keep counting", "A hi-hat note", "A kick note"], readingAnswer: 0),

    DrumxLessonDefinition(
      id: "groove-to-fill", version: "groove-to-fill-v1", chapter: 2,
      title: "Groove into a fill", subtitle: "Two beats of groove, two beats of fill.",
      objective: "Replace the last two beats with alternating snare eighth notes and return to one.",
      explanation: "For beats 1 and 2, play the basic groove: hi-hat eighths, kick on 1, snare on 2. For 3 & 4 &, play four snare notes, R L R L, leaving hi-hat and kick out. Repeat the bar and land the next hi-hat and kick together on 1.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 10 min",
      techniqueTip: "The fill uses the same spacing as the hi-hat notes it replaces. Count through the change, and try a click-only take to check recall when the phrase feels familiar.",
      events: phrase(hat([0, 0.5, 1, 1.5]), kick([0]), snare([1]),
        alternatingSnare([2, 2.5, 3, 3.5])),
      readingQuestion: "Where does the snare fill begin in this one-bar exercise?",
      readingChoices: ["On beat 1", "On the & of 2", "On beat 3"], readingAnswer: 2),
  ]

  static func lesson(id: String) -> DrumxLessonDefinition? {
    lessons.first { $0.id == id }
  }
}
