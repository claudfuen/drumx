import Foundation

struct PracticeResume: Codable, Equatable {
  var lessonID: String
  var tempo: Double
  var mode: Int
  var liveFeedback: Bool
  var bars: Int
  /// Nil preserves compatibility with resumes saved before lesson revisions were tracked.
  var lessonVersion: String?

  init(lessonID: String = "find-the-pulse", tempo: Double = 72, mode: Int = 0,
       liveFeedback: Bool = true, bars: Int = 4, lessonVersion: String? = nil) {
    self.lessonID = lessonID
    self.tempo = tempo
    self.mode = mode
    self.liveFeedback = liveFeedback
    self.bars = bars
    self.lessonVersion = lessonVersion
  }

  fileprivate var isValid: Bool {
    validProgressIdentifier(lessonID) && tempo.isFinite && (30...240).contains(tempo)
      && (0...2).contains(mode) && (1...64).contains(bars)
      && (lessonVersion.map(validProgressIdentifier) ?? true)
  }
}

enum DrumxCheckKind: String, Codable {
  case readingQuizPassed
  case techniqueSelfCheck
}

/// Versioned evidence of an explicit learner action. A self-check is not an
/// observed technique assessment, and neither kind claims MIDI-verified mastery.
struct DrumxCheckEvidence: Codable, Equatable {
  let lessonID: String
  let version: String
  let kind: DrumxCheckKind
  let recordedAt: Date

  fileprivate var isValid: Bool {
    validProgressIdentifier(lessonID) && validProgressIdentifier(version)
      && recordedAt.timeIntervalSinceReferenceDate.isFinite
  }
}

struct DrumxPlayerProfile: Codable, Equatable, Identifiable {
  let id: UUID
  fileprivate(set) var name: String
  let createdAt: Date
  fileprivate(set) var hasCompletedWelcome: Bool
  fileprivate(set) var resume: PracticeResume
  fileprivate(set) var checks: [DrumxCheckEvidence]
  fileprivate let usesLegacyHistory: Bool

  var lastLessonID: String { resume.lessonID }

  /// History stays in its existing store. This model never reads or rewrites takes.
  var historyKey: String {
    usesLegacyHistory ? "drumx.lessonHistory.v1"
      : "drumx.lessonHistory.player.\(id.uuidString.lowercased()).v1"
  }

  func evidence(lessonID: String, version: String, kind: DrumxCheckKind) -> DrumxCheckEvidence? {
    checks.first { $0.lessonID == lessonID && $0.version == version && $0.kind == kind }
  }

  fileprivate var isValid: Bool {
    guard validPlayerName(name), name == name.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt.timeIntervalSinceReferenceDate.isFinite, resume.isValid, checks.count <= 2048,
      checks.allSatisfy({ $0.isValid && $0.recordedAt >= createdAt })
    else { return false }
    // Each kind/version has one explicit check date, never duplicate pass records.
    let keys = checks.map { EvidenceKey(lessonID: $0.lessonID, version: $0.version, kind: $0.kind) }
    return Set(keys).count == keys.count
  }
}

private struct EvidenceKey: Hashable {
  let lessonID: String
  let version: String
  let kind: DrumxCheckKind
}

private struct StoredDrumxProgress: Codable {
  let schemaVersion: Int
  let profiles: [DrumxPlayerProfile]
  let selectedProfileID: UUID

  var isValid: Bool {
    guard schemaVersion == 1, (1...8).contains(profiles.count),
      profiles.allSatisfy({ $0.isValid }),
      Set(profiles.map(\.id)).count == profiles.count,
      Set(profiles.map { normalizedPlayerName($0.name) }).count == profiles.count,
      profiles.contains(where: { $0.id == selectedProfileID }),
      profiles.first?.usesLegacyHistory == true,
      profiles.dropFirst().allSatisfy({ !$0.usesLegacyHistory })
    else { return false }
    return true
  }
}

private func validProgressIdentifier(_ value: String) -> Bool {
  (1...128).contains(value.count)
    && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
}

private func validPlayerName(_ value: String) -> Bool {
  (1...32).contains(value.count)
    && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
}

private func normalizedPlayerName(_ value: String) -> String {
  value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

/// Serial/main-thread use. Score progress remains derived from each player's
/// LessonHistory. Only profile selection, resume settings and explicit checks live here.
final class DrumxProgress {
  private let defaults: UserDefaults
  private let storageKey: String
  private(set) var profiles: [DrumxPlayerProfile]
  private(set) var selectedProfileID: UUID
  private(set) var lastError: String?

  var selectedProfile: DrumxPlayerProfile {
    // Both decoding and every mutation validate the selected ID before publication.
    profiles.first(where: { $0.id == selectedProfileID })!
  }

  var selectedHistoryKey: String { selectedProfile.historyKey }

  init(defaults: UserDefaults = .standard, storageKey: String = "drumx.progress.v1") {
    self.defaults = defaults
    self.storageKey = storageKey
    let player = DrumxPlayerProfile(id: UUID(), name: "Player 1", createdAt: Date(),
      hasCompletedWelcome: false, resume: PracticeResume(), checks: [], usesLegacyHistory: true)
    profiles = [player]
    selectedProfileID = player.id

    guard let original = defaults.object(forKey: storageKey) else {
      // A new store must retain the default player's UUID across app launches.
      _ = persist(profiles: profiles, selectedID: selectedProfileID)
      return
    }
    guard let data = original as? Data,
      let stored = try? JSONDecoder().decode(StoredDrumxProgress.self, from: data), stored.isValid
    else {
      // Keep the original bytes/type untouched. Only a later explicit mutation can replace it.
      lastError = "Saved player progress could not be read. The original record has been kept."
      return
    }
    profiles = stored.profiles
    selectedProfileID = stored.selectedProfileID
  }

  /// Adding a profile selects it. It starts with no welcome, check, or score evidence.
  @discardableResult
  func addProfile(name: String, at date: Date = Date()) -> DrumxPlayerProfile? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard validPlayerName(name) else {
      lastError = "Use a player name with 1 to 32 characters and no line breaks."
      return nil
    }
    guard profiles.count < 8 else {
      lastError = "This device can store up to 8 players."
      return nil
    }
    guard !profiles.contains(where: { normalizedPlayerName($0.name) == normalizedPlayerName(name) }) else {
      lastError = "That player name is already in use."
      return nil
    }
    guard date.timeIntervalSinceReferenceDate.isFinite else {
      lastError = "The player creation date is invalid."
      return nil
    }
    let player = DrumxPlayerProfile(id: UUID(), name: name, createdAt: date,
      hasCompletedWelcome: false, resume: PracticeResume(), checks: [], usesLegacyHistory: false)
    guard persist(profiles: profiles + [player], selectedID: player.id) else { return nil }
    return player
  }

  @discardableResult
  func selectProfile(id: UUID) -> Bool {
    guard profiles.contains(where: { $0.id == id }) else {
      lastError = "That player could not be found."
      return false
    }
    guard id != selectedProfileID else { return true }
    return persist(profiles: profiles, selectedID: id)
  }

  /// Renaming preserves the player's UUID, legacy history ownership and all evidence.
  @discardableResult
  func renameSelectedProfile(name: String) -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard validPlayerName(name) else {
      lastError = "Use a player name with 1 to 32 characters and no line breaks."
      return false
    }
    guard !profiles.contains(where: {
      $0.id != selectedProfileID && normalizedPlayerName($0.name) == normalizedPlayerName(name)
    }) else {
      lastError = "That player name is already in use."
      return false
    }
    guard name != selectedProfile.name else { return true }
    return updateSelected { $0.name = name }
  }

  @discardableResult
  func updateResume(_ resume: PracticeResume) -> Bool {
    guard resume.isValid else {
      lastError = "The saved lesson settings are invalid."
      return false
    }
    guard resume != selectedProfile.resume else { return true }
    return updateSelected { $0.resume = resume }
  }

  @discardableResult
  func completeWelcome() -> Bool {
    guard !selectedProfile.hasCompletedWelcome else { return true }
    return updateSelected { $0.hasCompletedWelcome = true }
  }

  func readingEvidence(lessonID: String, version: String) -> DrumxCheckEvidence? {
    selectedProfile.evidence(lessonID: lessonID, version: version, kind: .readingQuizPassed)
  }

  func techniqueEvidence(lessonID: String, version: String) -> DrumxCheckEvidence? {
    selectedProfile.evidence(lessonID: lessonID, version: version, kind: .techniqueSelfCheck)
  }

  /// Invoke only after the learner explicitly passes this lesson version's reading quiz.
  @discardableResult
  func markReadingChecked(lessonID: String, version: String, at date: Date = Date()) -> Bool {
    markChecked(lessonID: lessonID, version: version, kind: .readingQuizPassed, at: date)
  }

  /// Explicit learner self-report only. It is separate from the reading quiz and MIDI results.
  @discardableResult
  func markTechniqueChecked(lessonID: String, version: String, at date: Date = Date()) -> Bool {
    markChecked(lessonID: lessonID, version: version, kind: .techniqueSelfCheck, at: date)
  }

  private func markChecked(lessonID: String, version: String, kind: DrumxCheckKind, at date: Date) -> Bool {
    let evidence = DrumxCheckEvidence(lessonID: lessonID, version: version, kind: kind, recordedAt: date)
    guard evidence.isValid, date >= selectedProfile.createdAt else {
      lastError = "The lesson check details are invalid."
      return false
    }
    guard selectedProfile.evidence(lessonID: lessonID, version: version, kind: kind) == nil else {
      return true // Preserve the first explicit check date rather than inventing a new pass.
    }
    guard selectedProfile.checks.count < 2048 else {
      lastError = "This player's saved check record is full."
      return false
    }
    return updateSelected { $0.checks.append(evidence) }
  }

  private func updateSelected(_ mutation: (inout DrumxPlayerProfile) -> Void) -> Bool {
    guard let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return false }
    var updated = profiles
    mutation(&updated[index])
    return persist(profiles: updated, selectedID: selectedProfileID)
  }

  private func persist(profiles: [DrumxPlayerProfile], selectedID: UUID) -> Bool {
    let stored = StoredDrumxProgress(schemaVersion: 1, profiles: profiles, selectedProfileID: selectedID)
    guard stored.isValid else {
      lastError = "Player progress could not be saved because its values are invalid."
      return false
    }
    do {
      let data = try JSONEncoder().encode(stored)
      defaults.set(data, forKey: storageKey)
      self.profiles = profiles
      selectedProfileID = selectedID
      lastError = nil
      return true
    } catch {
      lastError = "Player progress could not be saved."
      return false
    }
  }
}
