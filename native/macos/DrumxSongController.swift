import AppKit

/// Songs own their transport and results. No song play writes lesson progress.
final class DrumxSongController: NSObject {
  let view = DrumxSongRootView()
  private let library = DrumxSongLibraryView()
  private let highway = DrumxSongHighwayView()
  private let backButton = LessonButton(title: "‹  Library", target: nil, action: nil)
  private let pauseButton = LessonButton(title: "Pause", target: nil, action: nil)
  private let restartButton = LessonButton(title: "Restart", target: nil, action: nil)
  private let songTitle = DrumxSongInk.label("", size: 24, weight: .semibold)
  private let songSubtitle = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let io: DrumxIO
  private let onBack: () -> Void
  private let core: OpaquePointer
  private let transport = DrumxSongAudioTransport()
  private var clock = DrumxSongClock()
  private var timer: Timer?
  private var selectedSong: DrumxSong?
  private var difficulty = "expert"
  private var prepared: DrumxSongPreparedAudio?
  private var preparedID: String?
  private var timing: DrumxSongChartTiming?
  private var inLibrary = true
  private var playing = false
  private var completed = false
  private var pausedPosition: Double = 0
  private var generation = 0
  private var importBusy = false
  private var preparingID: String?
  private var snapshot = DXSnapshot()
  private static let defaultMapping = [[42, 44, 46], [38, 40], [35, 36], [48, 50], [45, 47], [41, 43], [49, 52, 55, 57], [51, 53, 59]]
  private var mapping = DrumxSongController.defaultMapping
  var inputOffsetMilliseconds: Double = 0

  init(io: DrumxIO, onBack: @escaping () -> Void) {
    self.io = io; self.onBack = onBack
    guard let core = dx_core_create() else { fatalError("Could not create song scoring core") }
    self.core = core
    super.init()
    for item in [library, highway, backButton, pauseButton, restartButton, songTitle, songSubtitle] { view.addSubview(item) }
    for (button, selector) in [(backButton, #selector(backToLibrary)),
      (pauseButton, #selector(togglePause)), (restartButton, #selector(restart))] {
      button.target = self; button.action = selector; button.isBordered = false
    }
    backButton.quiet = true; pauseButton.primary = true
    view.onResize = { [weak self] in self?.layout() }
    view.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    view.onDrop = { [weak self] url in self?.importSource(url, scan: false) }
    library.onBack = { [weak self] in self?.stop(); self?.onBack() }
    library.onImport = { [weak self] in self?.chooseImport(scan: false) }
    library.onDirectory = { [weak self] in self?.chooseImport(scan: true) }
    library.onEncore = { NSWorkspace.shared.open(URL(string: "https://www.enchor.us/")!) }
    library.onSelection = { [weak self] song in self?.selectSong(song) }
    library.onNoSelection = { [weak self] in
      guard let self else { return }
      self.selectedSong = nil; self.generation += 1; self.preparingID = nil
      self.library.setStatus("Import a song or adjust your search to choose what to play.", busy: self.importBusy)
    }
    library.onDifficulty = { [weak self] value in
      self?.difficulty = value; self?.refreshSelection()
    }
    library.onPlay = { [weak self] in self?.prepareAndPlay() }
    highway.eventAt = { [weak self] index in
      guard let self else { return nil }
      var event = DXEvent()
      return dx_core_event(self.core, Int32(index), &event) != 0 ? event : nil
    }
    transport.onInterrupted = { [weak self] reason in
      self?.pause(reason: reason)
    }
    setLibraryVisible(true)
  }

  deinit { timer?.invalidate(); transport.stop(); dx_core_destroy(core) }

  func setMIDIMapping(_ notesByPad: [[Int]]) {
    mapping = Self.defaultMapping
    let supplied = min(mapping.count, notesByPad.count)
    for index in 0..<supplied { mapping[index] = notesByPad[index] }
    // User-assigned notes win over remaining GM defaults, with one pad per hit.
    for index in supplied..<mapping.count {
      mapping[index].removeAll { note in notesByPad.contains { $0.contains(note) } }
    }
  }

  func showLibrary() {
    stop(); setLibraryVisible(true)
    let result = DrumxSongLibrary.read()
    library.update(songs: result.songs, selecting: selectedSong?.id)
    let status = result.errors.isEmpty
      ? "Imported songs stay in your private Drumx library. Drop a song folder, .sng, or .zip to add it."
      : "\(result.errors.count) song manifest(s) could not be read. \(result.errors[0])"
    library.setStatus(status, busy: importBusy)
  }

  func stop() {
    generation += 1
    preparingID = nil
    clock.stop(at: DrumxIO.hostNowSeconds())
    transport.stop(); timer?.invalidate(); timer = nil; playing = false
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
      if view.window?.firstResponder is NSTextView { return false }
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
      judgment = Int(dx_core_input(core, Int32(pad), time, Double(velocity) / 127).judgment)
      dx_core_snapshot(core, &snapshot); highway.snapshot = snapshot
      if completed { updateResult() }
    }
    highway.showHit(pad: pad, judgment: judgment)
  }

  private func selectSong(_ song: DrumxSong) {
    if selectedSong?.id != song.id {
      generation += 1; preparingID = nil; difficulty = song.selectedDifficulty
      if !song.difficulties.contains(difficulty) { difficulty = song.difficulties.last ?? "expert" }
      library.setStatus("Choose a difficulty, then play with your MIDI kit or keyboard.", busy: importBusy)
    }
    selectedSong = song; refreshSelection()
  }
  private func refreshSelection() {
    guard let selectedSong else { return }
    library.select(song: selectedSong, difficulty: difficulty,
      noteCount: selectedSong.notes(for: difficulty).count)
  }

  private func chooseImport(scan: Bool) {
    guard !importBusy else { return }
    let panel = NSOpenPanel()
    panel.title = scan ? "Add a song directory" : "Import a Clone Hero or YARG song"
    panel.message = scan ? "Choose your Songs folder. Drumx finds song folders and .sng/.zip packages inside it."
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
    importBusy = true
    library.setStatus(scan ? "Scanning \(url.lastPathComponent) and importing drum songs…"
      : "Importing \(url.lastPathComponent)…", busy: true)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try DrumxSongLibrary.importSource(url, scan: scan) }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.importBusy = false
        let songs = DrumxSongLibrary.read().songs
        self.library.update(songs: songs)
        switch result {
        case .success(let message):
          self.library.setStatus("\(message) \(songs.count) \(songs.count == 1 ? "song" : "songs") in your library.")
        case .failure(let error): self.library.setStatus(error.localizedDescription)
        }
      }
    }
  }

  private func prepareAndPlay() {
    guard let song = selectedSong, !importBusy, preparingID == nil else { return }
    generation += 1
    let token = generation
    if let prepared, preparedID == song.id { beginSong(song, prepared: prepared); return }
    preparingID = song.id
    library.setStatus("Preparing \(song.title). Decoding its audio stems for the first play…", busy: true)
    DrumxSongPreparedAudio.preparationQueue.async { [weak self] in
      let result = Result { try DrumxSongPreparedAudio.prepare(song) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token else { return }
        self.preparingID = nil
        switch result {
        case .success(let audio):
          self.prepared = audio; self.preparedID = song.id
          self.beginSong(song, prepared: audio)
        case .failure(let error): self.library.setStatus(error.localizedDescription)
        }
      }
    }
  }

  private func beginSong(_ song: DrumxSong, prepared: DrumxSongPreparedAudio) {
    stop()
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
    highway.reset(); highway.notes = timing.notes; highway.duration = timing.duration
    songTitle.stringValue = song.title
    songSubtitle.stringValue = "\(song.artist)   /   \(difficulty.capitalized) drums   /   \(song.drumMode)"
    setLibraryVisible(false)
    startTransport(countdown: 2)
  }

  private func startTransport(countdown: Double) {
    guard let prepared, let timing else { return }
    do {
      try transport.start(prepared, position: pausedPosition, audioLead: timing.lead, countdown: countdown)
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
    clock.stop(at: now); transport.stop(); playing = false
    timer?.invalidate(); timer = nil
    pauseButton.title = "Resume"; highway.time = pausedPosition; highway.snapshot = snapshot
    highway.stateText = "Paused"; highway.detailText = reason; highway.needsDisplay = true
    view.window?.makeFirstResponder(view)
  }

  private func updateResult() {
    highway.completed = true; highway.stateText = "Song complete"
    let total = snapshot.total
    highway.detailText = total.has_accuracy != 0
      ? String(format: "%.0f%% hit rate   ·   %.0f%% timing accuracy", total.hit_rate_percent, total.timing_accuracy_percent)
      : "Your song results stay separate from your learning progress."
    highway.snapshot = snapshot; highway.needsDisplay = true
  }

  private func setLibraryVisible(_ visible: Bool) {
    inLibrary = visible; library.isHidden = !visible
    for item in [highway, backButton, pauseButton, restartButton, songTitle, songSubtitle] { item.isHidden = visible }
    layout(); view.window?.makeFirstResponder(view)
  }
  private func layout() {
    let w = view.bounds.width, h = view.bounds.height
    library.frame = view.bounds
    backButton.frame = NSRect(x: 25, y: 20, width: 103, height: 36)
    songTitle.frame = NSRect(x: 150, y: 18, width: max(160, w - 430), height: 33)
    songSubtitle.frame = NSRect(x: 151, y: 55, width: max(160, w - 430), height: 24)
    restartButton.frame = NSRect(x: w - 258, y: 26, width: 105, height: 40)
    pauseButton.frame = NSRect(x: w - 141, y: 26, width: 105, height: 40)
    highway.frame = NSRect(x: 0, y: 95, width: w, height: max(200, h - 95))
    highway.needsDisplay = true
  }

  @objc private func backToLibrary() { showLibrary() }
  @objc private func togglePause() {
    guard !inLibrary, !completed else { return }
    if playing { pause() } else { startTransport(countdown: 0.4) }
  }
  @objc private func restart() {
    guard let selectedSong, let prepared, !inLibrary else { return }
    beginSong(selectedSong, prepared: prepared)
  }
}
