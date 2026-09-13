import Foundation

struct PracticeResume: Codable, Equatable {
  static let currentSessionFormatVersion = 1
  var lessonID: String
  var tempo: Double
  var mode: Int
  var liveFeedback: Bool
  var bars: Int
  /// Nil preserves compatibility with resumes saved before lesson revisions were tracked.
  var lessonVersion: String?
  /// Missing in old saves. The first format migration replaces the old four-bar default.
  var sessionFormatVersion: Int?

  init(lessonID: String = "find-the-pulse", tempo: Double = 60, mode: Int = 0,
       liveFeedback: Bool = true, bars: Int = 16, lessonVersion: String? = nil,
       sessionFormatVersion: Int? = nil) {
    self.lessonID = lessonID
    self.tempo = tempo
    self.mode = mode
    self.liveFeedback = liveFeedback
    self.bars = bars
    self.lessonVersion = lessonVersion
    self.sessionFormatVersion = sessionFormatVersion
  }

  fileprivate var isValid: Bool {
    validProgressIdentifier(lessonID) && tempo.isFinite && (30...240).contains(tempo)
      && (0...2).contains(mode) && (1...64).contains(bars)
      && (lessonVersion.map(validProgressIdentifier) ?? true)
      && (sessionFormatVersion.map { $0 == Self.currentSessionFormatVersion } ?? true)
  }
}

enum DrumxCheckKind: String, Codable {
  case readingQuizPassed
  case techniqueSelfCheck
  case completedPractice
  case clickOnlyAttempt
}

/// The guided plan remembers the last explicitly started condition. Free practice
/// has its own controls; switching routes never overwrites the other route.
struct DrumxPulsePractice: Codable, Equatable {
  var policyVersion: Int = 1
  var isFreePractice: Bool
  var guided: PracticeResume
  var free: PracticeResume

  static func initial(resume: PracticeResume, existingPlayer: Bool) -> DrumxPulsePractice {
    let initial = PracticeResume(lessonVersion: "find-the-pulse-v1", sessionFormatVersion: 1)
    return DrumxPulsePractice(isFreePractice: existingPlayer,
      guided: initial, free: resume.lessonID == "find-the-pulse" ? resume : initial)
  }

  fileprivate var isValid: Bool {
    policyVersion == 1 && guided.isValid && free.isValid
      && guided.lessonID == "find-the-pulse" && free.lessonID == "find-the-pulse"
      && guided.lessonVersion == "find-the-pulse-v1" && guided.bars == 16
      && [60.0, 66, 72, 84, 96].contains(guided.tempo)
      && ((guided.mode == 0 || guided.mode == 1) ? guided.liveFeedback : !guided.liveFeedback)
  }
}

/// Versioned evidence of an explicit learner action. A self-check is not an
/// observed technique assessment. Practice flags mean tried, never mastery.
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
  fileprivate(set) var pulsePractice: DrumxPulsePractice? = nil

  /// Frozen before the first new-policy take. Nil means this profile still needs migration.
  fileprivate(set) var legacyAccessThrough: String? = nil

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
    guard pulsePractice?.isValid ?? true,
      legacyAccessThrough.map(validProgressIdentifier) ?? true,
      validPlayerName(name), name == name.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt.timeIntervalSinceReferenceDate.isFinite, resume.isValid, checks.count <= 2048,
      checks.allSatisfy({ $0.isValid && $0.recordedAt >= createdAt })
    else { return false }
    // Each kind/version has one evidence date, never duplicate pass or take records.
    let keys = checks.map { EvidenceKey(lessonID: $0.lessonID, version: $0.version, kind: $0.kind) }
    let keySet = Set(keys)
    return keySet.count == keys.count && checks.filter { $0.kind == .clickOnlyAttempt }.allSatisfy {
      keySet.contains(EvidenceKey(lessonID: $0.lessonID, version: $0.version, kind: .completedPractice))
    }
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

/// Serial/main-thread use. Scores remain in each player's LessonHistory. Profile
/// selection, resume settings and durable dated evidence live here without score duplication.
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
      hasCompletedWelcome: false, resume: PracticeResume(), checks: [], usesLegacyHistory: false, legacyAccessThrough: "find-the-pulse")
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

  /// Snapshot the old course frontier once. Current practice/resume flags never
  /// increase this value, so free practice cannot masquerade as legacy access.
  @discardableResult
  func freezeLegacyAccess(through lessonID: String) -> Bool {
    guard validProgressIdentifier(lessonID) else { return false }
    guard selectedProfile.legacyAccessThrough == nil else { return true }
    return updateSelected { $0.legacyAccessThrough = lessonID }
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
  func updatePulsePractice(_ practice: DrumxPulsePractice) -> Bool {
    guard practice.isValid else {
      lastError = "The pulse practice plan could not be saved."
      return false
    }
    guard practice != selectedProfile.pulsePractice else { return true }
    return updateSelected { $0.pulsePractice = practice }
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

  func practiceEvidence(lessonID: String, version: String) -> DrumxCheckEvidence? {
    selectedProfile.evidence(lessonID: lessonID, version: version, kind: .completedPractice)
  }

  func recallEvidence(lessonID: String, version: String) -> DrumxCheckEvidence? {
    selectedProfile.evidence(lessonID: lessonID, version: version, kind: .clickOnlyAttempt)
  }

  /// Caller must first obtain a valid LessonHistory.record from a naturally completed
  /// take with at least one matched hit. Set recall only for mode 2 with live feedback off.
  /// These durable flags describe attempted practice, not score quality or mastery.
  /// Both conditions persist together; the bounded recent-take store remains untouched.
  @discardableResult
  func markPracticeCompleted(lessonID: String, version: String, recall: Bool,
                             at date: Date = Date()) -> Bool {
    let kinds: [DrumxCheckKind] = recall ? [.completedPractice, .clickOnlyAttempt] : [.completedPractice]
    let evidence = kinds.map {
      DrumxCheckEvidence(lessonID: lessonID, version: version, kind: $0, recordedAt: date)
    }
    guard evidence.allSatisfy({ $0.isValid }), date >= selectedProfile.createdAt else {
      lastError = "The completed practice details are invalid."
      return false
    }
    let newEvidence = evidence.filter {
      selectedProfile.evidence(lessonID: lessonID, version: version, kind: $0.kind) == nil
    }
    guard !newEvidence.isEmpty else { return true }
    guard selectedProfile.checks.count + newEvidence.count <= 2048 else {
      lastError = "This player's saved check record is full."
      return false
    }
    return updateSelected { $0.checks.append(contentsOf: newEvidence) }
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
