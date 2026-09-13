import Foundation

@main
struct DrumxSongScoreChecks {
  static var checks = 0

  static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("Song score check failed: \(message)") }
  }
  static func rejected(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError("Expected rejection: \(message)") }
    catch { checks += 1 }
  }
  static func score(_ count: Int = 40, misses: Set<Int> = [], extras: [Double] = [],
                    resolved: Int? = nil, completed: Bool = true) -> DrumxSongScore {
    DrumxSongScore(expectedNotes: count,
      resolvedNotes: (0..<(resolved ?? count)).map { DrumxSongScoredNote(id: $0, time: Double($0), hit: !misses.contains($0)) },
      extraTimes: extras, completed: completed)
  }

  static func main() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drumx-score-checks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DrumxSongScoreStore(root: directory.appendingPathComponent("SongScores"))
    let profile = UUID(), otherProfile = UUID(), completedAt = Date(timeIntervalSince1970: 1_700_000_000)
    func attempt(_ value: DrumxSongScore, id: UUID = UUID(), player: UUID? = nil,
                 song: String = "chart-one", difficulty: String = "expert", revision: Int = 0) -> DrumxSongAttempt {
      DrumxSongAttempt(id: id, profileID: player ?? profile, songID: song,
        difficulty: difficulty, completedAt: completedAt, revision: revision, score: value)
    }

    check(score(10).points == 1000, "first ten hits use 1x")
    check(score(11).points == 1200, "eleventh hit earns 2x")
    check(score(20).points == 3000, "second ten use 2x")
    check(score(21).points == 3300, "twenty-first hit earns 3x")
    check(score(30).points == 6000, "third ten use 3x")
    check(score(31).points == 6400, "thirty-first hit earns 4x")
    check(score(40).points == 10_000, "perfect chart denominator matches earned maximum")
    check(score(40).stars == 5 && score(40).fullCombo, "perfect take earns five stars and full combo")
    check(score(40, misses: Set(0..<40)).points == 0, "all misses earn zero")
    check(score(40, misses: Set(0..<40)).isValid, "completed all-miss take remains valid evidence")
    check(score(40, misses: [10]).points == 6700, "a miss resets the multiplier")
    check(score(40, extras: [10]).points == 7000, "an extra at a note time breaks combo first")
    check(score(40, extras: [41]).combo == 0, "extra after final note resets current combo")
    check(score(40, extras: [41]).bestCombo == 40, "later extra preserves best streak")
    check(!score(40, extras: [41]).fullCombo, "extras disqualify full combo")
    check(score(40, extras: [41]).hitRate < 1, "extras affect hit rate")
    check(score(40, resolved: 10, completed: false).maxPoints == 10_000, "live denominator includes the whole chart")
    check(score(40, resolved: 10, completed: false).stars == 0, "ten early notes do not imply a completed-song rating")
    check(score(5, resolved: 1, completed: false).stars == 1, "one star at exactly20percent")
    check(score(5, resolved: 2, completed: false).stars == 2, "two stars at40percent")
    check(score(5, resolved: 3, completed: false).stars == 3, "three stars at60percent")
    check(score(5, resolved: 4, completed: false).stars == 4, "four stars at80percent")
    check(score(40).nextStarPoints == nil, "completed star ladder has no next target")
    check(score(40, resolved: 0, completed: false).nextStarPoints == 2000, "next star exposes exact score target")
    check(DrumxSongScore.perfectPoints(noteCount: 200_000) == 79_994_000, "maximum supported chart does not overflow")
    check(!score(0).isValid, "empty charts cannot score")
    check(!score(40, resolved: 5, completed: true).isValid, "partial charts cannot claim completion")
    check(!score(40, extras: [.nan]).isValid, "invalid input times fail closed")
    let duplicate = DrumxSongScore(expectedNotes: 2,
      resolvedNotes: [.init(id: 0, time: 0, hit: true), .init(id: 0, time: 1, hit: true)], extraTimes: [], completed: true)
    check(!duplicate.isValid, "duplicate notes cannot inflate score")
    let chord = DrumxSongScore(expectedNotes: 2,
      resolvedNotes: [.init(id: 1, time: 0, hit: true), .init(id: 0, time: 0, hit: true)], extraTimes: [], completed: true)
    check(chord.points == 200, "simultaneous drum notes are scored individually")
    var ledger = DrumxSongInputLedger()
    ledger.receive(id: 1, eventID: 2, time: 2.05, isExtra: false)
    ledger.receive(id: 2, eventID: 2, time: 1.98, isExtra: false)
    check(ledger.extraTimes == [2.05], "earlier captured replacement demotes the original matched input to an extra")
    ledger.receive(id: 2, eventID: 2, time: 1.98, isExtra: false)
    ledger.receive(id: 3, eventID: -1, time: 5, isExtra: true)
    ledger.receive(id: 3, eventID: -1, time: 5, isExtra: true)
    ledger.receive(id: 0, eventID: -1, time: 0, isExtra: false)
    check(ledger.extraTimes == [2.05, 5], "duplicate receipts and ignored inputs cannot inflate extra strikes")

    let empty = try store.best(profileID: profile, songID: "chart-one", difficulty: "expert")
    check(empty == nil, "new library has no invented best")
    check(!FileManager.default.fileExists(atPath: directory.path), "reading absent scores does not create an archive")
    rejected("partial take persistence") { try store.record(attempt(score(40, resolved: 10, completed: false))) }
    check(!FileManager.default.fileExists(atPath: directory.path), "invalid takes write nothing")

    let good = attempt(score(40, misses: [10]))
    let first = try store.record(good)
    check(first.inserted && first.personalBest && first.playCount == 1, "first complete take creates a best")
    let archive = store.archiveURL(profileID: profile, songID: "chart-one", difficulty: "expert")
    let beforeDuplicate = try Data(contentsOf: archive)
    let duplicateResult = try store.record(good)
    check(!duplicateResult.inserted && !duplicateResult.updated && duplicateResult.playCount == 1,
      "duplicate attempt is idempotent")
    check((try? Data(contentsOf: archive)) == beforeDuplicate, "duplicate attempt leaves exact archive bytes alone")

    let worse = attempt(score(40, misses: Set(0..<30)))
    let second = try store.record(worse)
    check(second.playCount == 2 && second.best.id == good.id && !second.personalBest, "worse take keeps the best and counts one new play")
    let tied = attempt(good.score)
    let third = try store.record(tied)
    check(third.best.id == good.id, "exact score tie retains first best deterministically")

    let improved = attempt(score(40), id: worse.id, revision: 1)
    let correction = try store.record(improved)
    check(correction.updated && !correction.inserted && correction.playCount == 3,
      "late correction updates same attempt without another play")
    check(correction.best.id == worse.id && correction.personalBest, "late correction can improve personal best")
    let stale = try store.record(worse)
    check(stale.best.score.points == 10_000 && stale.playCount == 3 && !stale.updated,
      "older worse revision cannot overwrite a corrected attempt")
    let reopened = DrumxSongScoreStore(root: store.root)
    let reopenedBest = try reopened.best(profileID: profile, songID: "chart-one", difficulty: "expert")
    check(reopenedBest?.score.points == 10_000, "best survives reopening the store")

    let lateExtra = DrumxSongAttempt(id: worse.id, profileID: profile, songID: "chart-one",
      difficulty: "expert", completedAt: completedAt.addingTimeInterval(100), revision: 2,
      score: score(40, extras: [5, 15, 25, 35]))
    let correctedDown = try store.record(lateExtra)
    check(correctedDown.updated && correctedDown.playCount == 3, "newer authoritative correction may lower the same take without duplicating it")
    check(correctedDown.best.id == good.id && correctedDown.best.score == good.score,
      "late extras remove a false personal best and restore the best different take")
    check(!correctedDown.personalBest, "downward correction cannot announce a new record")
    let staleBetter = try store.record(improved)
    check(!staleBetter.updated && staleBetter.best.id == good.id, "stale higher score cannot restore an invalidated record")
    let beforeConflict = try Data(contentsOf: archive)
    rejected("conflicting identical revision") { try store.record(attempt(score(40), id: worse.id, revision: 2)) }
    check((try? Data(contentsOf: archive)) == beforeConflict, "conflicting revision preserves exact archive bytes")
    let savedObject = try JSONSerialization.jsonObject(with: beforeConflict) as! [String: Any]
    let savedAttempts = savedObject["attempts"] as! [[String: Any]]
    let savedCorrection = savedAttempts.first { ($0["id"] as? String) == worse.id.uuidString }!
    check((savedCorrection["completedAt"] as? Double) == completedAt.timeIntervalSinceReferenceDate,
      "late correction retains the first completion timestamp")
    rejected("negative revision") { try store.record(attempt(score(40), revision: -1)) }

    try store.record(attempt(score(5), player: otherProfile))
    try store.record(attempt(score(6), difficulty: "easy"))
    try store.record(attempt(score(7), song: "chart-two"))
    let another = try store.best(profileID: otherProfile, songID: "chart-one", difficulty: "expert")
    let easy = try store.best(profileID: profile, songID: "chart-one", difficulty: "easy")
    let otherSong = try store.best(profileID: profile, songID: "chart-two", difficulty: "expert")
    check(another?.score.points == 500, "profiles isolate scores")
    check(easy?.score.points == 600, "difficulties isolate scores")
    check(otherSong?.score.points == 700, "songs isolate scores")
    check(store.archiveURL(profileID: profile, songID: "../elsewhere", difficulty: "expert").deletingLastPathComponent()
      == archive.deletingLastPathComponent(), "song identifiers cannot escape the private profile directory")
    check(store.archiveURL(profileID: profile, songID: "CHART-one", difficulty: "expert") != archive,
      "case-distinct identities cannot collide on macOS")
    let beforeChangedChart = try Data(contentsOf: archive)
    rejected("different note count cannot compare as same chart") { try store.record(attempt(score(41))) }
    check((try? Data(contentsOf: archive)) == beforeChangedChart, "changed chart preserves existing archive")

    let badPath = store.archiveURL(profileID: profile, songID: "corrupt", difficulty: "expert")
    let corrupt = Data("{\"schemaVersion\":1,garbled".utf8)
    try corrupt.write(to: badPath)
    rejected("corrupt archive read") { _ = try store.best(profileID: profile, songID: "corrupt", difficulty: "expert") }
    rejected("corrupt archive mutation") { try store.record(attempt(score(40), song: "corrupt")) }
    check((try? Data(contentsOf: badPath)) == corrupt, "corrupt bytes remain untouched")

    let badIdentity = store.archiveURL(profileID: profile, songID: "wrong-identity", difficulty: "expert")
    try Data(contentsOf: archive).write(to: badIdentity)
    rejected("archive key identity mismatch") { try store.record(attempt(score(40), song: "wrong-identity")) }
    let badVersion = store.archiveURL(profileID: profile, songID: "wrong-version", difficulty: "expert")
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: archive)) as! [String: Any]
    object["schemaVersion"] = 999
    let badVersionData = try JSONSerialization.data(withJSONObject: object)
    try badVersionData.write(to: badVersion)
    rejected("unknown schema must be preserved") { try store.record(attempt(score(40), song: "wrong-version")) }
    check((try? Data(contentsOf: badVersion)) == badVersionData, "unknown schema is not migrated by guessing")

    let protected = directory.appendingPathComponent("unrelated.json")
    try Data("keep-me".utf8).write(to: protected)
    let linked = store.archiveURL(profileID: profile, songID: "linked", difficulty: "expert")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: protected)
    rejected("symlink archive must not replace its target") { try store.record(attempt(score(40), song: "linked")) }
    check((try? Data(contentsOf: protected)) == Data("keep-me".utf8), "unrelated target survives unsafe-path rejection")

    let directoryCollision = store.archiveURL(profileID: profile, songID: "directory", difficulty: "expert")
    try FileManager.default.createDirectory(at: directoryCollision, withIntermediateDirectories: false)
    rejected("archive path occupied by a directory") { try store.record(attempt(score(40), song: "directory")) }
    check(FileManager.default.fileExists(atPath: directoryCollision.path), "failed atomic save leaves unrelated directory")
    print("\(checks) song score checks passed")
  }
}
