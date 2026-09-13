import AppKit

/// Songs own their transport and results. No song play writes lesson progress.
final class DrumxSongController: NSObject {
  let view = DrumxSongRootView()
  private let library = DrumxSongLibraryView()
  private let highway = DrumxSongHighwayView()
  private let backButton = LessonButton(title: "‹  Library", target: nil, action: nil)
  private let pauseButton = LessonButton(title: "Pause", target: nil, action: nil)
  private let restartButton = LessonButton(title: "Restart", target: nil, action: nil)
  private let recordedDrumsButton = DrumxPopUpButton()
  private let audioMixLabel = DrumxSongInk.label("", size: 11, color: DrumxSongInk.muted)
  private var audioMode = DrumxSongAudioMode(rawValue:
    UserDefaults.standard.string(forKey: "drumx.songs.recordedDrumsMode") ?? "") ?? .performance
  private var performanceMuted = false
  private var missDeadlines: [Int: Double] = [:]
  private let songTitle = DrumxSongInk.label("", size: 24, weight: .semibold)
  private let songSubtitle = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let scrollSpeedLabel = DrumxSongInk.label("Scroll speed · 1.25×", size: 11, color: DrumxSongInk.muted)
  private let scrollSpeedControl = DrumxSlider(value: 1.25, minValue: 0.7, maxValue: 1.8, target: nil, action: nil)
  private let io: DrumxIO
  private let onBack: () -> Void
  private let core: OpaquePointer
  private let transport = DrumxSongAudioTransport()
  private let previewTransport = DrumxSongAudioTransport()
  private var previewTimer: Timer?
  private var previewWork: DispatchWorkItem?
  private var previewCancellation: DrumxSongPreparationCancellation?
  private var playPreparationCancellation: DrumxSongPreparationCancellation?
  private var previewGeneration = 0
  private var currentPreview: DrumxSongPreparedPreview?
  private var clock = DrumxSongClock()
  private var timer: Timer?
  private var selectedSong: DrumxSong?
  private var loadedSong: DrumxSong?
  private var libraryGeneration = 0
  private var difficulty = "expert"
  private var prepared: DrumxSongPreparedAudio?
  private var preparedID: String?
  private var timing: DrumxSongChartTiming?
  private var inLibrary = true
  private var isActive = false
  private var playing = false
  private var completed = false
  private var pausedPosition: Double = 0
  private var generation = 0
  private var importBusy = false
  private var preparingID: String?
  private var snapshot = DXSnapshot()
  private var recentTiming = DrumxSongTimingFeedback()
  private let scoreStore = DrumxSongScoreStore()
  private let scoreQueue = DispatchQueue(label: "org.drumx.song-scores", qos: .utility)
  private var inputLedger = DrumxSongInputLedger()
  private var scoredMetrics: [Int]?
  private var scoreRevision = 0
  private var attemptID = UUID()
  private var attemptProfileID: UUID?
  private var attemptSongID: String?
  private var attemptDifficulty = "expert"
  private var attemptCompletedAt: Date?
  private var pendingScores: [UUID: DrumxSongAttempt] = [:]
  private var savingScores = Set<UUID>()
  private var scoreSaveErrors: [UUID: String] = [:]
  private var scoreCloseWaiters: [(Bool) -> Void] = []
  private var bestReadGeneration = 0
  private struct BestSelection: Equatable {
    let profileID: UUID
    let songID: String
    let difficulty: String
  }
  private var bestSelection: BestSelection?
  private static let defaultMapping = [[42, 44, 46], [38, 40], [35, 36], [48, 50], [45, 47], [41, 43], [49, 52, 55, 57], [51, 53, 59]]
  private var mapping = DrumxSongController.defaultMapping
  var inputOffsetMilliseconds: Double = 0
  var profileID: UUID? {
    didSet {
      if profileID != oldValue { bestSelection = nil; bestReadGeneration += 1 }
    }
  }
  var hasUnsavedScores: Bool { !pendingScores.isEmpty || !savingScores.isEmpty }

  /// Finish existing atomic writes, retry any failed takes once, and return on
  /// main after every latest revision has settled. Failure retains the session.
  func retryScoresBeforeClosing(completion: @escaping (Bool) -> Void) {
    scoreCloseWaiters.append(completion)
    retryPendingScores()
    finishScoreCloseWaitersIfReady()
  }

  init(io: DrumxIO, onBack: @escaping () -> Void) {
    self.io = io; self.onBack = onBack
    guard let core = dx_core_create() else { fatalError("Could not create song scoring core") }
    self.core = core
    super.init()
    for item in [library, highway, backButton, pauseButton, restartButton, songTitle, songSubtitle,
                 scrollSpeedLabel, scrollSpeedControl, recordedDrumsButton, audioMixLabel] { view.addSubview(item) }
    for (button, selector) in [(backButton, #selector(backToLibrary)),
      (pauseButton, #selector(togglePause)), (restartButton, #selector(restart))] {
      button.target = self; button.action = selector; button.isBordered = false
    }
    backButton.quiet = true; pauseButton.primary = true
    recordedDrumsButton.addItems(withTitles: DrumxSongAudioMode.allCases.map(\.title))
    recordedDrumsButton.target = self; recordedDrumsButton.action = #selector(changeRecordedDrums)
    recordedDrumsButton.setAccessibilityLabel("Recorded drums")
    recordedDrumsButton.toolTip = "Follow my playing restores recorded drums on hits and mutes them on misses. Always on plays the full recording. Off uses your kit and any enabled Drumx hit sounds."
    let savedSpeed = UserDefaults.standard.object(forKey: "drumx.songs.scrollSpeed") as? Double ?? 1.25
    highway.scrollSpeed = savedSpeed.isFinite ? min(1.8, max(0.7, savedSpeed)) : 1.25
    scrollSpeedControl.doubleValue = highway.scrollSpeed
    scrollSpeedControl.isContinuous = true
    scrollSpeedControl.target = self; scrollSpeedControl.action = #selector(scrollSpeedChanged)
    scrollSpeedControl.setAccessibilityLabel("Scroll speed")
    scrollSpeedControl.toolTip = "Spread notes farther apart visually. Audio speed and scoring stay the same."
    scrollSpeedControl.attachValueLabel(scrollSpeedLabel) { String(format: "Scroll speed · %.2f×", $0) }
    view.onResize = { [weak self] in self?.layout() }
    view.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    library.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    view.onDrop = { [weak self] url in self?.importSource(url, scan: false) }
    library.onBack = { [weak self] in self?.stop(); self?.onBack() }
    library.onImport = { [weak self] in self?.chooseImport(scan: false) }
    library.onDirectory = { [weak self] in self?.chooseImport(scan: true) }
    library.onRefresh = { [weak self] in self?.refreshLibrary() }
    library.onRetryScoreSave = { [weak self] in self?.retryPendingScores() }
    library.onEncore = { NSWorkspace.shared.open(URL(string: "https://www.enchor.us/")!) }
    library.onSelection = { [weak self] song in self?.selectSong(song) }
    library.onNoSelection = { [weak self] in
      guard let self else { return }
      self.selectedSong = nil; self.generation += 1; self.preparingID = nil
      self.playPreparationCancellation?.cancel(); self.playPreparationCancellation = nil
      self.loadedSong = nil; self.prepared = nil; self.preparedID = nil
      self.bestSelection = nil; self.bestReadGeneration += 1; self.library.setBest(nil)
      self.stopPreview()
      self.library.setStatus("Import a song or adjust your search to choose what to play.", busy: self.importBusy)
    }
    library.onDifficulty = { [weak self] value in
      self?.difficulty = value; self?.refreshSelection()
    }
    library.onPlay = { [weak self] in self?.prepareAndPlay() }
    library.onPreviewToggle = { [weak self] in
      guard let self, let song = self.selectedSong else { return }
      if self.previewCancellation != nil || self.previewTransport.isRunning { self.stopPreview() }
      else { self.schedulePreview(song, delay: 0) }
    }
    highway.eventAt = { [weak self] index in
      guard let self else { return nil }
      var event = DXEvent()
      return dx_core_event(self.core, Int32(index), &event) != 0 ? event : nil
    }
    transport.onInterrupted = { [weak self] reason in
      self?.pause(reason: reason)
    }
    previewTransport.onInterrupted = { [weak self] _ in self?.stopPreview() }
    setLibraryVisible(true)
  }

  deinit {
    timer?.invalidate(); previewTimer?.invalidate(); previewWork?.cancel(); previewCancellation?.cancel()
    playPreparationCancellation?.cancel()
    transport.stop(); previewTransport.stop(); dx_core_destroy(core)
  }

  func setMIDIMapping(_ notesByPad: [[Int]]) {
    mapping = Self.defaultMapping
    let supplied = min(mapping.count, notesByPad.count)
    for index in 0..<supplied { mapping[index] = notesByPad[index] }
    // User-assigned notes win over remaining GM defaults, with one pad per hit.
    for index in supplied..<mapping.count {
      mapping[index].removeAll { note in notesByPad.contains { $0.contains(note) } }
    }
    // The song's scored aliases and audible samples use the same resolved map.
    // Lab restores the lesson map when leaving the Songs page.
    io.setMIDIMapping(mapping)
  }

  func showLibrary() {
    stop(); isActive = true; setLibraryVisible(true)
    reloadLibrary()
  }

  private func reloadLibrary(message: String? = nil) {
    libraryGeneration += 1
    let token = libraryGeneration, selection = selectedSong?.id
    library.setStatus("Loading your song library…", busy: true)
    DrumxSongLibrary.readingQueue.async { [weak self] in
      let result = DrumxSongLibrary.read()
      DispatchQueue.main.async { [weak self] in
        guard let self, self.libraryGeneration == token, self.inLibrary, self.isActive else { return }
        self.library.update(songs: result.songs, selecting: selection)
        var status = "\(result.songs.count.formatted()) songs in your library. "
        status += message ?? "Add an unpacked Songs directory to play its files in place. Refresh rescans registered directories."
        if !result.errors.isEmpty { status += " \(result.errors.count) unreadable manifest(s): \(result.errors[0])" }
        self.library.setStatus(status, busy: self.importBusy)
        if let selected = self.selectedSong, self.previewCancellation == nil { self.schedulePreview(selected) }
        DrumxSongLibrary.repairIndexIfNeeded(result.songs) { [weak self] repair in
          guard let self, self.isActive, self.inLibrary else { return }
          if case .success(let count) = repair, count > 0 {
            self.reloadLibrary(message: "Song intensity ratings updated.")
          }
        }
      }
    }
  }

  func registerDirectory(_ url: URL) { DrumxSongLibrary.registerDirectory(url) }

  private func refreshLibrary() {
    guard !importBusy, preparingID == nil else { return }
    stopPreview()
    let directories = DrumxSongLibrary.registeredDirectories
    guard !directories.isEmpty else {
      reloadLibrary(message: "Library refreshed. Add a song directory to include its new songs in future refreshes.")
      return
    }
    importBusy = true; libraryGeneration += 1
    library.setStatus("Refreshing \(directories.count) song \(directories.count == 1 ? "directory" : "directories")…", busy: true)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let messages = directories.map { url -> String in
        do { return try DrumxSongLibrary.importSource(url, scan: true) }
        catch { return "\(url.lastPathComponent): \(error.localizedDescription)" }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.importBusy = false; self.reloadLibrary(message: messages.joined(separator: " "))
      }
    }
  }

  func stop() {
    generation += 1
    libraryGeneration += 1; isActive = false; stopPreview()
    preparingID = nil
    playPreparationCancellation?.cancel(); playPreparationCancellation = nil
    clock.stop(at: DrumxIO.hostNowSeconds())
    transport.stop(); timer?.invalidate(); timer = nil; playing = false
    io.setSongSampleSuppressed(false)
  }

  func interrupt(reason: String) { pause(reason: reason) }

  func handleMIDI(note: Int, velocity: Int, hostTime: Double) {
    guard !inLibrary, let pad = mapping.firstIndex(where: { $0.contains(note) }), velocity > 0 else { return }
    receive(pad: pad, velocity: velocity, hostTime: hostTime)
  }

  @discardableResult func handleKey(_ event: NSEvent) -> Bool {
    guard !event.isARepeat, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
    // Native search editing and control activation keep their usual behavior.
    if inLibrary {
      if event.keyCode == 125 || event.keyCode == 126 {
        library.moveSelection(event.keyCode == 125 ? 1 : -1); return true
      }
      if view.window?.firstResponder is NSTextView { return false }
      if event.keyCode == 49 { library.onPreviewToggle?(); return true }
      if event.keyCode == 53 { stop(); onBack(); return true }
      if event.keyCode == 36 { prepareAndPlay(); return true }
      return false
    }
    if event.keyCode == 53 { showLibrary(); return true }
    if event.keyCode == 36 { restart(); return true }
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if key == "p" { togglePause(); return true }
    guard let pad = ["a": 0, "s": 1, " ": 2, "d": 3, "f": 4, "g": 5, "w": 6, "h": 7][key] else { return false }
    let velocity = event.modifierFlags.contains(.shift) ? 48 : 108
    io.playPad(pad: pad, velocity: velocity)
    receive(pad: pad, velocity: velocity, hostTime: event.timestamp)
    return true
  }

  private func receive(pad: Int, velocity: Int, hostTime: Double) {
    guard !inLibrary, (0..<8).contains(pad), (1...127).contains(velocity) else { return }
    var judgment = Int(DX_IGNORED.rawValue)
    if let time = clock.songTime(capturedAt: hostTime, offsetMS: inputOffsetMilliseconds),
      time >= -0.125, time <= (timing?.duration ?? 0) + 0.125 {
      let result = dx_core_input(core, Int32(pad), time, Double(velocity) / 127)
      judgment = Int(result.judgment)
      inputLedger.receive(id: result.id, eventID: Int(result.event_id), time: result.time_seconds,
        isExtra: result.judgment == Int32(DX_EXTRA.rawValue))
      if result.event_id >= 0 {
        recentTiming.record(id: result.id, time: result.time_seconds, offsetMS: result.offset_ms, eventID: Int(result.event_id))
      }
      highway.timingFeedback = recentTiming.state(at: max(0, highway.time))
      dx_core_snapshot(core, &snapshot); highway.snapshot = snapshot
      if completed { updateResult() } else { refreshScore() }
    }
    highway.showHit(pad: pad, judgment: judgment)
  }

  private func selectSong(_ song: DrumxSong) {
    let changed = selectedSong?.id != song.id
    if changed {
      generation += 1; preparingID = nil; difficulty = song.selectedDifficulty
      playPreparationCancellation?.cancel(); playPreparationCancellation = nil
      loadedSong = nil; prepared = nil; preparedID = nil
      if !song.difficulties.contains(difficulty) { difficulty = song.difficulties.last ?? "expert" }
      library.setStatus("Choose a difficulty, then play with your MIDI kit or keyboard.", busy: importBusy)
    }
    selectedSong = song; refreshSelection()
    if changed { schedulePreview(song) }
  }
  private func refreshSelection() {
    guard let selectedSong else { return }
    library.select(song: selectedSong, difficulty: difficulty,
      noteCount: selectedSong.noteCount(for: difficulty))
    refreshPersonalBest()
  }

  private func refreshPersonalBest(force: Bool = false) {
    guard let song = selectedSong, let profileID else { library.setBest(nil); return }
    let selection = BestSelection(profileID: profileID, songID: song.id, difficulty: difficulty)
    guard force || bestSelection != selection else { return }
    bestSelection = selection; bestReadGeneration += 1
    let token = bestReadGeneration
    library.setBest(nil)
    scoreQueue.async { [weak self] in
      guard let self else { return }
      let result = Result { try self.scoreStore.summary(profileID: selection.profileID,
        songID: selection.songID, difficulty: selection.difficulty) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.bestReadGeneration == token, self.bestSelection == selection else { return }
        switch result {
        case .success(let summary): self.library.setBest(summary)
        case .failure(let error): self.library.setBest(nil, error: error.localizedDescription)
        }
      }
    }
  }

  private func chooseImport(scan: Bool) {
    guard !importBusy else { return }
    let panel = NSOpenPanel()
    panel.title = scan ? "Add a song directory" : "Import a Clone Hero or YARG song"
    panel.message = scan ? "Choose your unpacked Songs folder. Drumx indexes drum charts and plays audio from this directory without copying it. Keep it in place."
      : "Choose a complete song folder, .sng, or .zip containing notes.mid or notes.chart and audio."
    panel.canChooseDirectories = true; panel.canChooseFiles = !scan
    panel.allowsMultipleSelection = false; panel.prompt = scan ? "Add directory" : "Import song"
    let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      if response == .OK, let url = panel.url { self?.importSource(url, scan: scan) }
    }
    if let window = view.window { panel.beginSheetModal(for: window, completionHandler: done) }
    else { done(panel.runModal()) }
  }

  private func importSource(_ url: URL, scan: Bool) {
    guard !importBusy else { return }
    if !inLibrary { showLibrary() }
    stopPreview()
    importBusy = true
    library.setStatus(scan ? "Indexing drum songs in \(url.lastPathComponent) without copying their audio…"
      : "Importing \(url.lastPathComponent)…", busy: true)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try DrumxSongLibrary.importSource(url, scan: scan) }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.importBusy = false
        switch result {
        case .success(let message):
          if scan { self.registerDirectory(url) }
          self.reloadLibrary(message: message)
        case .failure(let error): self.reloadLibrary(message: error.localizedDescription)
        }
      }
    }
  }

  private func stopPreview() {
    previewGeneration += 1
    previewWork?.cancel(); previewWork = nil
    previewCancellation?.cancel(); previewCancellation = nil
    previewTransport.stop(); previewTimer?.invalidate(); previewTimer = nil; currentPreview = nil
    library.setPreviewState(active: false)
  }

  private func schedulePreview(_ song: DrumxSong, delay: Double = 0.3) {
    stopPreview()
    guard isActive, inLibrary, !importBusy, preparingID == nil, !song.audio.isEmpty else { return }
    let token = previewGeneration, cancellation = DrumxSongPreparationCancellation()
    previewCancellation = cancellation; library.setPreviewState(active: false, pending: true)
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.previewGeneration == token, !cancellation.isCancelled else { return }
      self.previewWork = nil
      let cached = self.preparedID == song.id ? self.prepared : nil
      DrumxSongPreparedAudio.preparationQueue.async { [weak self] in
        let result = Result { () throws -> DrumxSongPreparedPreview in
          if cancellation.isCancelled { throw CancellationError() }
          return try DrumxSongPreparedAudio.preparePreview(song, fullAudio: cached, cancellation: cancellation)
        }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isActive, self.inLibrary, self.previewGeneration == token,
            !cancellation.isCancelled, self.selectedSong?.id == song.id,
            !self.importBusy, self.preparingID == nil else { return }
          switch result {
          case .success(let preview):
            do {
              try self.previewTransport.start(preview.audio, position: preview.playbackStart,
                audioLead: 0, countdown: 0.15, mode: .reference)
              self.currentPreview = preview; self.previewTransport.setVolume(0)
              self.library.setPreviewState(active: true)
              self.library.setPreviewPosition(current: preview.sourceStart, end: preview.sourceStart + preview.duration)
              let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tickPreview() }
              self.previewTimer = timer; RunLoop.main.add(timer, forMode: .common)
            } catch { self.stopPreview(); self.library.setStatus("Preview unavailable: \(error.localizedDescription)") }
          case .failure(let error):
            self.stopPreview(); self.library.setStatus("Preview unavailable: \(error.localizedDescription)")
          }
        }
      }
    }
    previewWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func tickPreview() {
    guard let preview = currentPreview, previewTransport.isRunning, isActive, inLibrary else { stopPreview(); return }
    let position = DrumxIO.hostNowSeconds() - previewTransport.epoch
    guard position < preview.playbackEnd else { stopPreview(); return }
    let fadeIn = min(1, max(0, (position - preview.playbackStart) / 0.35))
    let fadeOut = min(1, max(0, (preview.playbackEnd - position) / 0.8))
    previewTransport.setVolume(Float(0.50 * min(fadeIn, fadeOut)))
    library.setPreviewPosition(current: preview.sourceStart + max(0, position - preview.playbackStart),
      end: preview.sourceStart + preview.duration)
  }

  private func prepareAndPlay() {
    guard let song = selectedSong, !importBusy, preparingID == nil else { return }
    stopPreview()
    generation += 1
    let token = generation
    let cancellation = DrumxSongPreparationCancellation()
    playPreparationCancellation = cancellation
    let cachedAudio = preparedID == song.id ? prepared : nil
    preparingID = song.id
    library.setStatus("Loading \(song.title)'s drum charts and preparing its audio…", busy: true)
    DrumxSongPreparedAudio.preparationQueue.async { [weak self] in
      let result = Result { () throws -> (DrumxSong, DrumxSongPreparedAudio) in
        if cancellation.isCancelled { throw CancellationError() }
        let fullSong = try DrumxSongLibrary.loadFull(song)
        if cancellation.isCancelled { throw CancellationError() }
        let audio = try cachedAudio ?? DrumxSongPreparedAudio.prepare(fullSong, cancellation: cancellation)
        if cancellation.isCancelled { throw CancellationError() }
        return (fullSong, audio)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token, !cancellation.isCancelled else { return }
        self.preparingID = nil; self.playPreparationCancellation = nil
        switch result {
        case .success(let (fullSong, audio)):
          self.loadedSong = fullSong
          self.prepared = audio; self.preparedID = song.id
          self.beginSong(fullSong, prepared: audio)
        case .failure(let error): self.library.setStatus(error.localizedDescription)
        }
      }
    }
  }

  private func beginSong(_ song: DrumxSong, prepared: DrumxSongPreparedAudio) {
    stop()
    isActive = true
    updateSampleSuppression()
    guard let profileID else {
      library.setStatus("Choose a player profile before starting a song.")
      return
    }
    let timing = DrumxSongChartTiming(song: song, difficulty: difficulty, audioDuration: prepared.duration)
    var events = timing.notes.map { DXSongEvent(pad: Int32($0.pad), time_seconds: $0.time) }
    let loaded = events.withUnsafeMutableBufferPointer {
      dx_core_load_song(core, timing.duration, $0.baseAddress, Int32($0.count))
    }
    guard loaded != 0 else {
      library.setStatus("This difficulty has invalid, duplicate, or unsupported drum notes. Try another difficulty or reimport the chart.")
      return
    }
    self.timing = timing; self.prepared = prepared; preparedID = song.id
    pausedPosition = 0; completed = false; clock = DrumxSongClock()
    attemptID = UUID(); attemptProfileID = profileID; attemptSongID = song.id
    attemptDifficulty = difficulty; attemptCompletedAt = nil
    inputLedger = DrumxSongInputLedger(); scoredMetrics = nil; scoreRevision = 0
    performanceMuted = false
    missDeadlines = DrumxSongStemGate.missDeadlines(targets: timing.notes.enumerated().map {
      DrumxSongGateTarget(id: $0.offset, pad: $0.element.pad, time: $0.element.time)
    })
    recentTiming.reset(); highway.timingFeedback = recentTiming.state(at: 0)
    highway.reset(); highway.notes = timing.notes; highway.duration = timing.duration
    highway.gridLines = DrumxSongGrid.lines(resolution: song.resolution, tempos: song.tempos,
      signatures: song.timeSignatures, lead: timing.lead, duration: timing.duration)
    highway.score = nil; highway.personalBestPoints = nil; highway.recordText = ""
    dx_core_snapshot(core, &snapshot); highway.snapshot = snapshot
    refreshScore(); loadAttemptBest()
    songTitle.stringValue = song.title
    songSubtitle.stringValue = "\(song.artist)   /   \(difficulty.capitalized) drums   /   \(song.drumMode)"
    updateAudioMix()
    setLibraryVisible(false)
    startTransport(countdown: 2)
  }

  private func startTransport(countdown: Double) {
    guard let prepared, let timing else { return }
    do {
      try transport.start(prepared, position: pausedPosition, audioLead: timing.lead,
        countdown: countdown, mode: audioMode, performanceMuted: performanceMuted)
      // Resume countdown cannot turn a newly played hit into an earlier strike.
      // A fresh song still accepts the first target's ordinary early window.
      let captureStart = transport.epoch + pausedPosition - (pausedPosition == 0 ? 0.125 : 0)
      clock.begin(epoch: transport.epoch, at: max(DrumxIO.hostNowSeconds(), captureStart))
      playing = true; pauseButton.title = "Pause"; pauseButton.isEnabled = true
      highway.stateText = ""; highway.detailText = ""
      timer?.invalidate()
      let next = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
      timer = next; RunLoop.main.add(next, forMode: .common)
      tick(); view.window?.makeFirstResponder(view)
    } catch {
      transport.stop(); playing = false; pauseButton.title = "Resume"
      highway.stateText = "Audio unavailable"
      highway.detailText = error.localizedDescription
      highway.needsDisplay = true
    }
  }

  private func tick() {
    guard playing, let timing else { return }
    let rawTime = DrumxIO.hostNowSeconds() - transport.epoch
    let time = pausedPosition > 0 ? max(pausedPosition, rawTime) : rawTime
    dx_core_advance(core, time); dx_core_snapshot(core, &snapshot)
    highway.time = min(timing.duration, time); highway.snapshot = snapshot
    refreshScore()
    highway.timingFeedback = recentTiming.state(at: max(0, time))
    if rawTime < pausedPosition {
      highway.stateText = "Ready in \(Int(ceil(pausedPosition - rawTime)))"
      highway.detailText = "Follow the notes to the shared NOW line."
    } else { highway.stateText = ""; highway.detailText = "" }
    if !transport.isRunning { pause(reason: "Audio stopped. Resume to continue this song."); return }
    if time >= timing.duration + 0.15 {
      clock.stop(at: transport.epoch + timing.duration + 0.125)
      playing = false; completed = true; pausedPosition = timing.duration
      transport.stop(); timer?.invalidate(); timer = nil
      pauseButton.title = "Finished"; pauseButton.isEnabled = false
      updateResult()
    }
    highway.needsDisplay = true
  }

  private func pause(reason: String = "Press P or Resume when you are ready.") {
    guard playing, let timing else { return }
    let now = DrumxIO.hostNowSeconds()
    pausedPosition = min(timing.duration, max(pausedPosition, now - transport.epoch))
    dx_core_advance(core, pausedPosition); dx_core_snapshot(core, &snapshot)
    refreshScore()
    clock.stop(at: now); transport.stop(); playing = false
    timer?.invalidate(); timer = nil
    pauseButton.title = "Resume"; highway.time = pausedPosition; highway.snapshot = snapshot
    highway.stateText = "Paused"; highway.detailText = reason; highway.needsDisplay = true
    view.window?.makeFirstResponder(view)
  }

  private func updateResult() {
    refreshScore()
    highway.completed = true; highway.stateText = "Song complete"
    let total = snapshot.total
    highway.detailText = total.has_accuracy != 0
      ? String(format: "%.0f%% hit rate   ·   %.0f%% timing accuracy", total.hit_rate_percent, total.timing_accuracy_percent)
      : "Your song results stay separate from your learning progress."
    highway.snapshot = snapshot; highway.needsDisplay = true
  }

  private func loadAttemptBest() {
    guard let player = attemptProfileID, let songID = attemptSongID else { return }
    let id = attemptID, difficulty = attemptDifficulty
    scoreQueue.async { [weak self] in
      guard let self else { return }
      let result = Result { try self.scoreStore.summary(profileID: player, songID: songID, difficulty: difficulty) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.attemptID == id, !self.completed else { return }
        switch result {
        case .success(let summary): self.highway.personalBestPoints = summary?.best.score.points
        case .failure: self.highway.recordText = "Previous best unavailable"
        }
        self.highway.needsDisplay = true
      }
    }
  }

  /// Chart judgments, not display frames, invalidate the score. The core can
  /// correct an expired miss after a delayed timestamped MIDI packet arrives.
  private func refreshScore() {
    let total = snapshot.total
    let metrics = [Int(total.expected), Int(total.matched), Int(total.missed), Int(total.extra), completed ? 1 : 0]
    guard metrics != scoredMetrics else { return }
    scoredMetrics = metrics; scoreRevision += 1
    let count = Int(dx_core_event_count(core))
    var notes: [DrumxSongScoredNote] = []
    notes.reserveCapacity(Int(total.matched + total.missed))
    for index in 0..<count {
      var event = DXEvent()
      if dx_core_event(core, Int32(index), &event) != 0, event.resolved != 0 {
        notes.append(.init(id: Int(event.id), time: event.time_seconds, hit: event.hit != 0))
      }
    }
    let muted = DrumxSongStemGate.isMuted(resolvedNotes: notes,
      hitTimes: inputLedger.creditedHitTimes, missDeadlines: missDeadlines)
    if muted != performanceMuted {
      performanceMuted = muted
      transport.setPerformanceMuted(muted)
      updateAudioMix()
    }
    let score = DrumxSongScore(expectedNotes: count, resolvedNotes: notes,
      extraTimes: inputLedger.extraTimes, completed: completed)
    guard score.isValid, score.matched == Int(total.matched), score.missed == Int(total.missed),
      score.extra == Int(total.extra) else {
      highway.score = nil; highway.recordText = "Score unavailable: input totals could not be verified."
      highway.needsDisplay = true
      return
    }
    highway.score = score
    guard completed, let player = attemptProfileID, let songID = attemptSongID else { return }
    if attemptCompletedAt == nil { attemptCompletedAt = Date() }
    let attempt = DrumxSongAttempt(id: attemptID, profileID: player, songID: songID,
      difficulty: attemptDifficulty, completedAt: attemptCompletedAt!, revision: scoreRevision, score: score)
    pendingScores[attempt.id] = attempt
    highway.personalBestPoints = nil; highway.recordText = "Saving result…"
    savePendingScore(attempt.id)
  }

  private func savePendingScore(_ id: UUID) {
    guard !savingScores.contains(id), let attempt = pendingScores[id] else { return }
    savingScores.insert(id)
    if id == attemptID, completed { highway.recordText = "Saving result…" }
    updateScoreSaveFeedback()
    scoreQueue.async { [weak self] in
      guard let self else { return }
      let result = Result { try self.scoreStore.record(attempt) }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.savingScores.remove(id)
        // A correction arriving during disk I/O supersedes the queued version.
        // Its completion must be verified before we show a personal best.
        if let latest = self.pendingScores[id], latest.revision > attempt.revision {
          self.savePendingScore(id)
          return
        }
        switch result {
        case .success(let saved):
          self.pendingScores.removeValue(forKey: id); self.scoreSaveErrors.removeValue(forKey: id)
          if self.attemptID == id, self.completed {
            self.highway.personalBestPoints = saved.best.score.points
            self.highway.recordText = saved.best.id == id
              ? (saved.personalBest ? "New personal best · saved" : "Personal best · saved") : "Result saved"
          }
          if self.profileID == attempt.profileID, self.selectedSong?.id == attempt.songID,
            self.difficulty == attempt.difficulty { self.refreshPersonalBest(force: true) }
        case .failure(let error):
          self.scoreSaveErrors[id] = error.localizedDescription
          if self.attemptID == id, self.completed { self.highway.recordText = "Result waiting to save · Retry save" }
        }
        self.updateScoreSaveFeedback()
        self.finishScoreCloseWaitersIfReady()
      }
    }
  }

  private func retryPendingScores() {
    for id in pendingScores.keys.sorted(by: { $0.uuidString < $1.uuidString }) { savePendingScore(id) }
  }

  private func finishScoreCloseWaitersIfReady() {
    guard savingScores.isEmpty, !scoreCloseWaiters.isEmpty else { return }
    let waiters = scoreCloseWaiters
    scoreCloseWaiters.removeAll()
    for completion in waiters { completion(pendingScores.isEmpty) }
  }

  private func updateScoreSaveFeedback() {
    let failures = scoreSaveErrors.filter { pendingScores[$0.key] != nil }
    if let first = failures.sorted(by: { $0.key.uuidString < $1.key.uuidString }).first {
      let count = failures.count
      library.setScoreSaveError("\(count) completed \(count == 1 ? "take is" : "takes are") waiting to save. \(first.value)")
    } else { library.setScoreSaveError(nil) }
    if completed {
      if savingScores.contains(attemptID) { pauseButton.title = "Saving…"; pauseButton.isEnabled = false }
      else if pendingScores[attemptID] != nil { pauseButton.title = "Retry save"; pauseButton.isEnabled = true }
      else { pauseButton.title = "Finished"; pauseButton.isEnabled = false }
    }
    highway.needsDisplay = true
  }

  private func setLibraryVisible(_ visible: Bool) {
    inLibrary = visible; library.isHidden = !visible
    for item in [highway, backButton, pauseButton, restartButton, songTitle, songSubtitle,
                 scrollSpeedLabel, scrollSpeedControl, recordedDrumsButton, audioMixLabel] { item.isHidden = visible }
    updateSampleSuppression()
    layout(); view.window?.makeFirstResponder(view)
  }
  private func layout() {
    let w = view.bounds.width, h = view.bounds.height
    library.frame = view.bounds
    backButton.frame = NSRect(x: 25, y: 11, width: 103, height: 36)
    songTitle.frame = NSRect(x: 150, y: 8, width: max(160, w - 680), height: 33)
    songSubtitle.frame = NSRect(x: 151, y: 43, width: max(160, w - 680), height: 24)
    scrollSpeedLabel.frame = NSRect(x: w - 473, y: 13, width: 193, height: 18)
    scrollSpeedControl.frame = NSRect(x: w - 479, y: 34, width: 200, height: 23)
    restartButton.frame = NSRect(x: w - 258, y: 18, width: 105, height: 40)
    pauseButton.frame = NSRect(x: w - 141, y: 18, width: 105, height: 40)
    audioMixLabel.frame = NSRect(x: 151, y: 78, width: max(160, w - 455), height: 22)
    recordedDrumsButton.frame = NSRect(x: w - 258, y: 69, width: 222, height: 34)
    highway.frame = NSRect(x: 0, y: 110, width: w, height: max(200, h - 110))
    highway.needsDisplay = true
  }

  @objc private func backToLibrary() { showLibrary() }
  private func updateAudioMix() {
    let mix = DrumxSongStemMix(stems: prepared?.stems ?? [], mode: audioMode,
      performanceMuted: performanceMuted)
    recordedDrumsButton.isEnabled = mix.hasSeparateDrums
    if mix.hasSeparateDrums {
      if recordedDrumsButton.numberOfItems != DrumxSongAudioMode.allCases.count {
        recordedDrumsButton.removeAllItems()
        recordedDrumsButton.addItems(withTitles: DrumxSongAudioMode.allCases.map(\.title))
      }
      recordedDrumsButton.selectItem(at: DrumxSongAudioMode.allCases.firstIndex(of: audioMode) ?? 0)
    } else if recordedDrumsButton.itemTitles != ["Recorded drums: In mix"] {
      recordedDrumsButton.removeAllItems(); recordedDrumsButton.addItem(withTitle: "Recorded drums: In mix")
    }
    audioMixLabel.stringValue = mix.status
    audioMixLabel.toolTip = mix.status
    updateSampleSuppression()
  }
  private func updateSampleSuppression() {
    // Full mixes always use their original recording. The disabled In mix
    // control must not inherit invisible sample behavior from a previous song.
    let embeddedDrums = !inLibrary && prepared.map {
      !DrumxSongStemMix(stems: $0.stems).hasSeparateDrums
    } == true
    io.setSongSampleSuppressed(isActive && (audioMode != .practice || embeddedDrums))
  }
  @objc private func changeRecordedDrums() {
    guard let prepared, DrumxSongStemMix(stems: prepared.stems).hasSeparateDrums else { return }
    let index = recordedDrumsButton.indexOfSelectedItem
    guard DrumxSongAudioMode.allCases.indices.contains(index) else { return }
    audioMode = DrumxSongAudioMode.allCases[index]
    UserDefaults.standard.set(audioMode.rawValue, forKey: "drumx.songs.recordedDrumsMode")
    transport.setMode(audioMode)
    updateAudioMix()
  }
  @objc private func scrollSpeedChanged() {
    highway.scrollSpeed = scrollSpeedControl.doubleValue
    UserDefaults.standard.set(highway.scrollSpeed, forKey: "drumx.songs.scrollSpeed")
  }
  @objc private func togglePause() {
    guard !inLibrary else { return }
    if completed { retryPendingScores(); return }
    if playing { pause() } else { startTransport(countdown: 0.4) }
  }
  @objc private func restart() {
    guard let loadedSong, let prepared, !inLibrary else { return }
    beginSong(loadedSong, prepared: prepared)
  }
}
