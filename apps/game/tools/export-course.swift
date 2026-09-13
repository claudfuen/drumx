// Rebuild the shared course with:
// swiftc native/macos/DrumxCourse.swift apps/game/tools/export-course.swift -o .build/export-game-course
// .build/export-game-course > apps/game/data/course.json
import Foundation
@main enum ExportCourse {
  static func main() throws {
    let lessons: [[String: Any]] = DrumxCourse.lessons.map { lesson in
      ["id":lesson.id,"version":lesson.version,"chapter":lesson.chapter,"title":lesson.title,
       "subtitle":lesson.subtitle,"objective":lesson.objective,"explanation":lesson.explanation,
       "counts":lesson.counts,"bpm":lesson.suggestedBPM,"practice_minutes":lesson.practiceMinutes,"technique_tip":lesson.techniqueTip,
       "reading_question":lesson.readingQuestion,"reading_choices":lesson.readingChoices,"reading_answer":lesson.readingAnswer,
       "events":lesson.events.map { ["beat":$0.beat,"pad":$0.pad,"velocity":$0.velocity,"hand":$0.hand ?? ""] as [String:Any] }]
    }
    let value: [String:Any] = ["version":1,"chapters":DrumxCourse.chapterTitles,"lessons":lessons]
    let bytes = try JSONSerialization.data(withJSONObject:value, options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
    print(String(decoding:bytes,as:UTF8.self))
  }
}
