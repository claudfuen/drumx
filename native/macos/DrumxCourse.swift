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

/// Foundations, introductory rudiments, and three-instrument coordination.
/// Suggested practice totals 174 minutes across repetitions, not unique content.
/// Playback, scoring, and notation should consume these same one-bar events.
/// Guidance, tempo changes, attempt evidence, and readiness belong to the caller.
enum DrumxCourse {
  static let chapterTitles = [
    "Pulse and counts",
    "Build your backbeat",
    "Read, vary, and remember",
    "Hands and rudiments",
    "Make the groove your own",
  ]

  private static let quarterBeats: [Double] = [0, 1, 2, 3]
  private static let eighthBeats: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5]
  private static let eighthCounts = "1 & 2 & 3 & 4 &"
  private static let doubles = ["R", "R", "L", "L", "R", "R", "L", "L"]
  private static let paradiddle = ["R", "L", "R", "R", "L", "R", "L", "L"]

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

  /// An original slow study of a conventional sticking. Moving suggested R to
  /// hi-hat and L to snare makes the orchestration audible, not hand-verifiable.
  private static func stickingStudy(_ hands: [String], orchestrated: Bool = false) -> [DrumxLessonNote] {
    precondition(hands.count == eighthBeats.count)
    return zip(eighthBeats, hands).map { beat, hand in
      let pad = orchestrated && hand == "R" ? 0 : 1
      return DrumxLessonNote(beat: beat, pad: pad, hand: hand, velocity: pad == 0 ? 88 : 100)
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
      title: "Single Stroke Roll", subtitle: "Let your hands take turns.",
      objective: "Name the Single Stroke Roll and play eight even strokes with suggested alternating hands.",
      explanation: "The Single Stroke Roll alternates R L. Here, play R L R L R L R L as snare eighth notes while counting 1 & 2 & 3 & 4 &. The sticking names the rudiment; eighth notes describe this exercise's spacing. This slow introduction also prepares a short fill.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Listen for matching sound and spacing from both hands. R/L is a self-check, not a MIDI measurement. If the ands become uneven, revisit Find the and before adding speed.",
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

    DrumxLessonDefinition(
      id: "double-stroke-open-roll", version: "double-stroke-open-roll-v1", chapter: 3,
      title: "Double Stroke Open Roll", subtitle: "Two even strokes from each hand.",
      objective: "Keep each pair evenly spaced in a slow introduction to double strokes.",
      explanation: "The Double Stroke Open Roll repeats R R L L. Here, play R R L L R R L L as snare eighth notes, with two distinct strokes per hand. Each number and & gets one note. The timing stays like the Single Stroke Roll; the suggested hand sequence changes.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Listen to each pair's second stroke: keep it clear and even. If the pulse slips, revisit Single Stroke Roll. Self-check the hands or ask a teacher; MIDI cannot verify sticking or controlled rebound. This is not a buzz-roll exercise.",
      events: stickingStudy(doubles),
      readingQuestion: "With R R L L eighths, which counts use the first left-hand pair?",
      readingChoices: ["1 and the & of 1", "2 and the & of 2", "Only beat 4"], readingAnswer: 1),

    DrumxLessonDefinition(
      id: "move-the-doubles", version: "move-the-doubles-v1", chapter: 3,
      title: "Move the doubles", subtitle: "One sticking, two sounds.",
      objective: "Move the double-stroke pattern between hi-hat and snare without changing its spacing.",
      explanation: "Keep R R L L R R L L in eighth notes. Place the suggested R strokes on closed hi-hat and L strokes on snare. Hear two hat notes, then two snare notes, repeated. This is orchestration: placing a rhythm on different instruments. Leave the foot out for this study.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Listen for even spacing when the sound changes. If switching surfaces adds a gap, return to Double Stroke Open Roll on snare. Use a comfortable reach. The pad score checks instruments, not which hand played them.",
      events: stickingStudy(doubles, orchestrated: true),
      readingQuestion: "Which instrument plays both eighth notes on count 2 and its &?",
      readingChoices: ["Hi-hat", "Bass drum", "Snare"], readingAnswer: 2),

    DrumxLessonDefinition(
      id: "single-paradiddle", version: "single-paradiddle-v1", chapter: 3,
      title: "Single Paradiddle", subtitle: "Two singles, then a double.",
      objective: "Learn R L R R L R L L while keeping every snare eighth note evenly spaced.",
      explanation: "A Single Paradiddle combines singles and doubles: R L R R, then L R L L. In this slow study, one full sequence fills the bar in eighth notes. The first group starts on 1 and the second on 3. Keep the beat unchanged when one hand plays twice.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 10 min",
      techniqueTip: "Say the sticking, then listen for even notes through each double. Revisit Single Stroke Roll or Double Stroke Open Roll if needed. No accents are required here. Self-check your hands; a perfect MIDI timing score cannot verify the sticking.",
      events: stickingStudy(paradiddle),
      readingQuestion: "In this eighth-note paradiddle, where does the L R L L group begin?",
      readingChoices: ["On beat 3", "On the & of 1", "On beat 4"], readingAnswer: 0),

    DrumxLessonDefinition(
      id: "move-the-paradiddle", version: "move-the-paradiddle-v1", chapter: 3,
      title: "Move the paradiddle", subtitle: "Hear the sticking across the kit.",
      objective: "Play the paradiddle's rhythm across hi-hat and snare with no gaps at the changes.",
      explanation: "Use R L R R L R L L again, with suggested R on closed hi-hat and L on snare. The staff now shows which surface plays each eighth note. Listen for the different sounds revealing the two singles and the double. This coordination study is not the usual snare-on-2-and-4 backbeat.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 10 min",
      techniqueTip: "Keep each sound in its place without speeding up the doubles. If the surface changes distract you, revisit Single Paradiddle on snare. MIDI can check the surface sequence; hand choice and movement remain self or teacher checks.",
      events: stickingStudy(paradiddle, orchestrated: true),
      readingQuestion: "Which two counts contain the final pair of snare notes?",
      readingChoices: ["1 and the & of 1", "3 and the & of 3", "4 and the & of 4"], readingAnswer: 2),

    DrumxLessonDefinition(
      id: "foot-under-paradiddle", version: "foot-under-paradiddle-v1", chapter: 4,
      title: "Foot beneath the paradiddle", subtitle: "Same hands, add the downbeats.",
      objective: "Add kick on 1 and 3 without disturbing the orchestrated paradiddle.",
      explanation: "Keep the hi-hat and snare sequence from Move the paradiddle. Add bass drum on 1 and 3. On 1, kick meets hi-hat; on 3, it meets snare. The suggested leading hand changes while your foot keeps the same two counts. Read those aligned notes as simultaneous sounds.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 12 min",
      techniqueTip: "Listen for kick and snare arriving together on 3, then an even next hi-hat. If adding the foot disrupts your hands, revisit Move the paradiddle. MIDI checks the note arrivals, not hand choice, balance, or pedal technique.",
      events: phrase(stickingStudy(paradiddle, orchestrated: true), kick([0, 2])),
      readingQuestion: "Which two instruments are vertically aligned on beat 3?",
      readingChoices: ["Hi-hat and snare", "Snare and bass drum", "Hi-hat and bass drum"], readingAnswer: 1),

    DrumxLessonDefinition(
      id: "four-on-the-floor", version: "four-on-the-floor-v1", chapter: 4,
      title: "Four on the floor", subtitle: "A bass-drum note on every beat.",
      objective: "Keep hi-hat eighths and the snare backbeat over four steady quarter-note kicks.",
      explanation: "Return to the familiar eighth-note hi-hat and snare on 2 and 4. This time the kick plays all four numbered beats. Four on the floor names that steady bass-drum pattern. On 2 and 4, hi-hat, snare, and kick arrive together; the hat still plays each & between them.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 8 min",
      techniqueTip: "Listen for one aligned attack from all three instruments on the backbeats. Keep the intervening hats even. If the extra kicks interrupt your hands, revisit Your first backbeat. Stay balanced; pedal technique remains a self or teacher check.",
      events: phrase(hat(eighthBeats), snare([1, 3]), kick(quarterBeats)),
      readingQuestion: "How many different instruments play together on beat 2?",
      readingChoices: ["Three", "One", "Two"], readingAnswer: 0),

    DrumxLessonDefinition(
      id: "lead-into-one", version: "lead-into-one-v1", chapter: 4,
      title: "Lead into one", subtitle: "An extra kick before the barline.",
      objective: "Place a kick on the & of 4 and land the next downbeat without rushing.",
      explanation: "Play the basic groove with hi-hat eighths, snare on 2 and 4, and kick on 1 and 3. Add a kick on the & of 4. That extra note anticipates the next bar's 1. Count 4 and 1 evenly: the barline does not shorten the space between the two kick strokes.",
      counts: eighthCounts, suggestedBPM: 60, practiceMinutes: "Suggested 10 min",
      techniqueTip: "Listen to the gap from the last kick to the next first beat. Keep it one eighth note long. If the pedal pair feels crowded, revisit Kick on the and. Keep a comfortable motion; timing does not certify foot technique.",
      events: phrase(hat(eighthBeats), snare([1, 3]), kick([0, 2, 3.5])),
      readingQuestion: "Which count places the added kick immediately before the next bar?",
      readingChoices: ["Beat 3", "The & of 4", "Beat 4"], readingAnswer: 1),

    DrumxLessonDefinition(
      id: "between-the-beats", version: "between-the-beats-v1", chapter: 4,
      title: "Between the beats", subtitle: "Move the hi-hat to every and.",
      objective: "Keep the numbered beats steady while the hi-hat plays only halfway between them.",
      explanation: "Keep kick on 1 and 3 and snare on 2 and 4. Play closed hi-hat only on each &: these are the offbeats in this exercise. The first beat's upper voice starts with an eighth rest, followed by a hat note. Begin at 48 BPM to give this new coordination more room.",
      counts: eighthCounts, suggestedBPM: 48, practiceMinutes: "Suggested 12 min",
      techniqueTip: "Listen for even spacing from kick or snare to hi-hat and back again. Avoid pulling the hats onto the numbered beats. If the rests become confusing, revisit Give the groove more space, then count this pattern aloud before playing.",
      events: phrase(hat([0.5, 1.5, 2.5, 3.5]), snare([1, 3]), kick([0, 2])),
      readingQuestion: "In the first beat's upper voice, what comes before the hi-hat note?",
      readingChoices: ["A simultaneous snare note", "A quarter-note hat", "An eighth rest"], readingAnswer: 2),
  ]

  static func lesson(id: String) -> DrumxLessonDefinition? {
    lessons.first { $0.id == id }
  }
}
