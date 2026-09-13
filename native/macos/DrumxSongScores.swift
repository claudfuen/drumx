import Foundation
import CryptoKit
import Darwin

/// A resolved chart note, supplied from the native timing core. IDs follow the
/// imported chart, and `time` is the target time, not a rendering timestamp.
struct DrumxSongScoredNote {
  let id: Int
  let time: Double
  let hit: Bool
}

/// The core credits the earliest captured input, even when callbacks arrive out
/// of order. A replacement match turns the previously credited input into an
/// extra. Retain that captured time rather than inventing a render-time strike.
struct DrumxSongInputLedger {
  private var received = Set<UInt64>()
  private var credited: [Int: (id: UInt64, time: Double)] = [:]
  private(set) var extraTimes: [Double] = []

  mutating func receive(id: UInt64, eventID: Int, time: Double, isExtra: Bool) {
    guard id > 0, time.isFinite, received.insert(id).inserted else { return }
    if isExtra { extraTimes.append(time) }
    else if eventID >= 0 {
      if let previous = credited[eventID] { extraTimes.append(previous.time) }
      credited[eventID] = (id, time)
    }
  }
}

/// Drumx song scoring, version 1. A match earns 100 points at the current
/// multiplier. Hits 1...10 earn 1x, 11...20 earn 2x, 21...30 earn 3x, then 4x.
/// Misses and extra strikes reset the combo. Timing precision remains separate.
struct DrumxSongScore: Codable, Equatable {
  static let scoringVersion = 1
  static let starPercentages = [20, 40, 60, 80, 95]
  static let maximumNotes = 200_000
  static let maximumExtras = 1_000_000

  let expectedNotes: Int
  let points: Int
  let matched: Int
  let missed: Int
  let extra: Int
  let combo: Int
  let bestCombo: Int
  let completed: Bool
  private let inputsValid: Bool

  var maxPoints: Int { Self.perfectPoints(noteCount: expectedNotes) }
  var stars: Int {
    guard isValid else { return 0 }
    return Self.starPercentages.filter { points * 100 >= maxPoints * $0 }.count
  }
  var multiplier: Int { min(4, 1 + combo / 10) }
  var hitRate: Double {
    let attempts = matched + missed + extra
    return attempts > 0 ? Double(matched) / Double(attempts) : 0
  }
  var hitRatePercent: Double { hitRate * 100 }
  var fullCombo: Bool { isValid && completed && matched == expectedNotes && extra == 0 }
  var scoreFraction: Double { isValid ? Double(points) / Double(maxPoints) : 0 }
  var nextStarPoints: Int? {
    guard isValid, stars < Self.starPercentages.count else { return nil }
    return (maxPoints * Self.starPercentages[stars] + 99) / 100
  }
  var progressToNextStar: Double {
    guard isValid else { return 0 }
    guard let next = nextStarPoints else { return 1 }
    let previous = stars == 0 ? 0 : (maxPoints * Self.starPercentages[stars - 1] + 99) / 100
    return min(1, max(0, Double(points - previous) / Double(next - previous)))
  }

  init(expectedNotes: Int, resolvedNotes: [DrumxSongScoredNote], extraTimes: [Double], completed: Bool) {
    self.expectedNotes = expectedNotes
    self.completed = completed
    let valid = (1...Self.maximumNotes).contains(expectedNotes)
      && resolvedNotes.count <= expectedNotes && extraTimes.count <= Self.maximumExtras
      && resolvedNotes.allSatisfy { (0..<expectedNotes).contains($0.id) && $0.time.isFinite && abs($0.time) <= 7200 }
      && Set(resolvedNotes.map(\.id)).count == resolvedNotes.count
      && extraTimes.allSatisfy { $0.isFinite && abs($0) <= 7200 }
      && (!completed || resolvedNotes.count == expectedNotes)
    inputsValid = valid
    guard valid else {
      points = 0; matched = 0; missed = 0; extra = 0; combo = 0; bestCombo = 0
      return
    }
    // Recompute from authoritative resolved events so a delayed MIDI packet that
    // corrects an expired miss repairs the same take rather than appending points.
    let notes = resolvedNotes.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    let extras = extraTimes.sorted()
    var points = 0, combo = 0, best = 0, matched = 0, missed = 0, extraIndex = 0
    for note in notes {
      // At exactly the same target time, an extra strike breaks combo first.
      while extraIndex < extras.count && extras[extraIndex] <= note.time {
        combo = 0; extraIndex += 1
      }
      if note.hit {
        points += 100 * min(4, 1 + combo / 10)
        combo += 1; matched += 1; best = max(best, combo)
      } else {
        missed += 1; combo = 0
      }
    }
    if extraIndex < extras.count { combo = 0 }
    self.points = points; self.combo = combo; bestCombo = best
    self.matched = matched; self.missed = missed; extra = extras.count
  }

  static func perfectPoints(noteCount: Int) -> Int {
    guard (1...maximumNotes).contains(noteCount) else { return 0 }
    return min(noteCount, 10) * 100
      + min(max(noteCount - 10, 0), 10) * 200
      + min(max(noteCount - 20, 0), 10) * 300
      + max(noteCount - 30, 0) * 400
  }

  var isValid: Bool {
    guard inputsValid, (1...Self.maximumNotes).contains(expectedNotes),
      (0...expectedNotes).contains(matched), (0...expectedNotes - matched).contains(missed),
      (0...Self.maximumExtras).contains(extra), (0...matched).contains(combo),
      (combo...matched).contains(bestCombo), points >= matched * 100,
      points <= Self.perfectPoints(noteCount: matched), points % 100 == 0,
      !completed || matched + missed == expectedNotes else { return false }
    if completed && missed == 0 && extra == 0 {
      return points == maxPoints && combo == matched && bestCombo == matched
    }
    return true
  }

  /// Compare only equivalent charts and scoring rules. Exact ties retain the
  /// existing attempt so a later equal take does not churn a personal best.
  func isBetter(than other: DrumxSongScore) -> Bool {
    if points != other.points { return points > other.points }
    let leftDenominator = max(1, matched + missed + extra)
    let rightDenominator = max(1, other.matched + other.missed + other.extra)
    let left = Int64(matched) * Int64(rightDenominator)
    let right = Int64(other.matched) * Int64(leftDenominator)
    if left != right { return left > right }
    return bestCombo > other.bestCombo
  }
}

struct DrumxSongAttempt: Codable, Equatable, Identifiable {
  let id: UUID
  let profileID: UUID
  let songID: String
  let difficulty: String
  let completedAt: Date
  let scoringVersion: Int
  let revision: Int
  let score: DrumxSongScore

  init(id: UUID = UUID(), profileID: UUID, songID: String, difficulty: String,
       completedAt: Date = Date(), revision: Int = 0, score: DrumxSongScore) {
    self.id = id; self.profileID = profileID; self.songID = songID
    self.difficulty = difficulty; self.completedAt = completedAt
    scoringVersion = DrumxSongScore.scoringVersion; self.revision = revision; self.score = score
  }

  fileprivate var isValid: Bool {
    DrumxSongScoreStore.validSongID(songID) && DrumxSongScoreStore.difficulties.contains(difficulty)
      && completedAt.timeIntervalSince1970.isFinite
      && completedAt.timeIntervalSince1970 >= 0 && completedAt.timeIntervalSince1970 <= 32_503_680_000
      && scoringVersion == DrumxSongScore.scoringVersion && revision >= 0 && score.completed && score.isValid
  }
}

struct DrumxSongScoreSummary {
  let best: DrumxSongAttempt
  let playCount: Int
}

struct DrumxSongScoreRecordResult {
  let best: DrumxSongAttempt
  let playCount: Int
  let inserted: Bool
  let updated: Bool
  let personalBest: Bool
}

enum DrumxSongScoreError: LocalizedError {
  case invalidAttempt
  case unreadableArchive
  case unsafePath
  case incompatibleChart
  case archiveFull
  case lockingFailed
  case conflictingRevision

  var errorDescription: String? {
    switch self {
    case .invalidAttempt: return "Only a complete, valid song take can be saved."
    case .unreadableArchive: return "Saved song scores could not be read. The original file has been preserved."
    case .unsafePath: return "The song score path is not a regular private archive. Existing data has been preserved."
    case .incompatibleChart: return "This difficulty has a different note count from its saved scores. Previous scores have been preserved."
    case .archiveFull: return "This song has reached its local take archive limit. Existing scores have been preserved."
    case .lockingFailed: return "The song score archive is busy or unavailable. Try saving again."
    case .conflictingRevision: return "This take has conflicting score revisions. The saved result has been preserved."
    }
  }
}

private struct StoredDrumxSongScores: Codable {
  let schemaVersion: Int
  let profileID: UUID
  let songID: String
  let difficulty: String
  var attempts: [DrumxSongAttempt]

  var isValid: Bool {
    guard schemaVersion == 1, (1...DrumxSongScoreStore.maximumAttempts).contains(attempts.count),
      Set(attempts.map(\.id)).count == attempts.count,
      attempts.allSatisfy({ $0.isValid && $0.profileID == profileID && $0.songID == songID && $0.difficulty == difficulty }),
      Set(attempts.map { $0.score.expectedNotes }).count == 1 else { return false }
    return true
  }

  var best: DrumxSongAttempt {
    attempts.dropFirst().reduce(attempts[0]) { best, attempt in
      attempt.score.isBetter(than: best.score) ? attempt : best
    }
  }
}

/// A dedicated atomic archive per player, song, and difficulty. This store never
/// reads or writes curriculum progress. Invalid existing bytes block replacement.
final class DrumxSongScoreStore {
  static let maximumAttempts = 10_000
  static let maximumArchiveBytes = 16 * 1024 * 1024
  static let difficulties = Set(["easy", "medium", "hard", "expert"])
  private static let processLock = NSRecursiveLock()
  let root: URL

  static var defaultRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Drumx/SongScores", isDirectory: true)
  }

  init(root: URL = DrumxSongScoreStore.defaultRoot) {
    self.root = root.standardizedFileURL
  }

  fileprivate static func validSongID(_ value: String) -> Bool {
    (1...128).contains(value.utf8.count) && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }

  func archiveURL(profileID: UUID, songID: String, difficulty: String) -> URL {
    // Hash framing avoids path traversal and filesystem case-folding collisions.
    let identity = "\(songID.utf8.count):\(songID):\(difficulty):v\(DrumxSongScore.scoringVersion)"
    let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    return root.appendingPathComponent(profileID.uuidString.lowercased(), isDirectory: true)
      .appendingPathComponent(digest + ".json")
  }

  func best(profileID: UUID, songID: String, difficulty: String) throws -> DrumxSongAttempt? {
    try summary(profileID: profileID, songID: songID, difficulty: difficulty)?.best
  }

  func summary(profileID: UUID, songID: String, difficulty: String) throws -> DrumxSongScoreSummary? {
    Self.processLock.lock(); defer { Self.processLock.unlock() }
    guard Self.validSongID(songID), Self.difficulties.contains(difficulty) else { throw DrumxSongScoreError.invalidAttempt }
    let path = archiveURL(profileID: profileID, songID: songID, difficulty: difficulty)
    guard let stored = try read(path, profileID: profileID, songID: songID, difficulty: difficulty) else { return nil }
    return DrumxSongScoreSummary(best: stored.best, playCount: stored.attempts.count)
  }

  @discardableResult func record(_ attempt: DrumxSongAttempt) throws -> DrumxSongScoreRecordResult {
    guard attempt.isValid else { throw DrumxSongScoreError.invalidAttempt }
    Self.processLock.lock(); defer { Self.processLock.unlock() }
    let path = archiveURL(profileID: attempt.profileID, songID: attempt.songID, difficulty: attempt.difficulty)
    let folder = path.deletingLastPathComponent()
    try ensurePrivateDirectory(root)
    try ensurePrivateDirectory(folder)
    let lockURL = folder.appendingPathComponent(".score-write.lock")
    try requireRegularPath(lockURL)
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
    guard descriptor >= 0 else { throw DrumxSongScoreError.lockingFailed }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw DrumxSongScoreError.lockingFailed }
    defer { flock(descriptor, LOCK_UN) }

    var stored = try read(path, profileID: attempt.profileID, songID: attempt.songID, difficulty: attempt.difficulty)
      ?? StoredDrumxSongScores(schemaVersion: 1, profileID: attempt.profileID,
        songID: attempt.songID, difficulty: attempt.difficulty, attempts: [])
    let previousBest = stored.attempts.isEmpty ? nil : stored.best
    if let previousBest, previousBest.score.expectedNotes != attempt.score.expectedNotes {
      throw DrumxSongScoreError.incompatibleChart
    }
    var inserted = false, updated = false
    if let index = stored.attempts.firstIndex(where: { $0.id == attempt.id }) {
      let previous = stored.attempts[index]
      if attempt.revision == previous.revision && attempt.score != previous.score {
        throw DrumxSongScoreError.conflictingRevision
      }
      if attempt.revision > previous.revision {
        // Late input corrects one completed take. Its original completion date
        // remains stable even if the caller rebuilt the attempt to retry a save.
        stored.attempts[index] = DrumxSongAttempt(id: previous.id, profileID: previous.profileID,
          songID: previous.songID, difficulty: previous.difficulty,
          completedAt: previous.completedAt, revision: attempt.revision, score: attempt.score)
        updated = true
      }
    } else {
      guard stored.attempts.count < Self.maximumAttempts else { throw DrumxSongScoreError.archiveFull }
      stored.attempts.append(attempt); inserted = true
    }
    guard stored.isValid else { throw DrumxSongScoreError.invalidAttempt }
    if inserted || updated {
      let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(stored)
      guard data.count <= Self.maximumArchiveBytes else { throw DrumxSongScoreError.archiveFull }
      try requireRegularPath(path)
      try data.write(to: path, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
      guard let verified = try read(path, profileID: attempt.profileID,
        songID: attempt.songID, difficulty: attempt.difficulty), verified.attempts == stored.attempts else {
        throw DrumxSongScoreError.unreadableArchive
      }
      stored = verified
    }
    let best = stored.best
    let personalBest = previousBest.map { best.score.isBetter(than: $0.score) } ?? true
    return DrumxSongScoreRecordResult(best: best, playCount: stored.attempts.count,
      inserted: inserted, updated: updated, personalBest: personalBest)
  }

  private func read(_ path: URL, profileID: UUID, songID: String, difficulty: String) throws -> StoredDrumxSongScores? {
    try requireRegularPath(root, allowDirectory: true)
    try requireRegularPath(path.deletingLastPathComponent(), allowDirectory: true)
    try requireRegularPath(path)
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
      guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumArchiveBytes else {
        throw DrumxSongScoreError.unreadableArchive
      }
      let stored = try JSONDecoder().decode(StoredDrumxSongScores.self, from: Data(contentsOf: path))
      guard stored.isValid, stored.profileID == profileID, stored.songID == songID, stored.difficulty == difficulty else {
        throw DrumxSongScoreError.unreadableArchive
      }
      return stored
    } catch { throw DrumxSongScoreError.unreadableArchive }
  }

  private func ensurePrivateDirectory(_ url: URL) throws {
    try requireRegularPath(url, allowDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try requireRegularPath(url, allowDirectory: true)
  }

  private func requireRegularPath(_ url: URL, allowDirectory: Bool = false) throws {
    var info = stat()
    if lstat(url.path, &info) != 0 {
      if errno == ENOENT { return }
      throw DrumxSongScoreError.unsafePath
    }
    let kind = info.st_mode & S_IFMT
    guard kind == (allowDirectory ? S_IFDIR : S_IFREG) else { throw DrumxSongScoreError.unsafePath }
  }
}
