/// A finite practice phrase and its assistance. This value never schedules audio,
/// mutates progress, awards evidence, or starts the next phrase automatically.
struct DrumxPracticePlan: Equatable {
  static let currentSessionFormatVersion = PracticeResume.currentSessionFormatVersion
  static let barChoices = [1, 4, 8, 16]
  static let standardBars = 16
  static let tempoRange = 48.0...144.0

  let tempo: Double
  let bars: Int
  /// 0 Guided, 1 Hidden bars, 2 From memory. Live evaluation is independent.
  let mode: Int
  let liveFeedback: Bool

  /// Playing time only. Count-in and the transport's startup lead are additional.
  var durationSeconds: Double { Double(bars * 4) * 60 / tempo }
  var countInSeconds: Double { 4 * 60 / tempo }
  /// Does not include the controller's short startup lead.
  var totalDurationSeconds: Double { durationSeconds + countInSeconds }

  private init(tempo: Double, bars: Int, mode: Int, liveFeedback: Bool) {
    self.tempo = tempo
    self.bars = bars
    self.mode = mode
    self.liveFeedback = liveFeedback
  }

  static func standard(lesson: DrumxLessonDefinition) -> DrumxPracticePlan {
    DrumxPracticePlan(tempo: boundedTempo(lesson.suggestedBPM, fallback: 60),
      bars: standardBars, mode: 0, liveFeedback: true)
  }

  static func restore(resume: PracticeResume, lesson: DrumxLessonDefinition) -> DrumxPracticePlan {
    let recommended = standard(lesson: lesson)
    guard resume.lessonID == lesson.id,
      resume.sessionFormatVersion == nil || resume.sessionFormatVersion == currentSessionFormatVersion
    else { return recommended }
    if let revision = resume.lessonVersion, revision != lesson.version { return recommended }

    var bars = barChoices.contains(resume.bars) ? resume.bars : standardBars
    // Legacy saves did not distinguish the four-bar default from a deliberate
    // four-bar choice. Migrate that value once; version 1 preserves future choices.
    if resume.sessionFormatVersion == nil && bars == 4 { bars = standardBars }
    let mode = (0...2).contains(resume.mode) ? resume.mode : 0
    // Hidden bars alternates shown/hidden bars, so a one-bar phrase is not useful.
    // Preserve the established four-bar repair when restoring this combination.
    if mode == 1 && bars == 1 { bars = 4 }
    return DrumxPracticePlan(tempo: boundedTempo(resume.tempo, fallback: recommended.tempo),
      bars: bars, mode: mode, liveFeedback: resume.liveFeedback)
  }

  private static func boundedTempo(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? min(tempoRange.upperBound, max(tempoRange.lowerBound, value)) : fallback
  }
}
