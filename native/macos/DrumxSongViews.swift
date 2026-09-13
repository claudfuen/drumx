import AppKit

enum DrumxSongInk {
  static let background = NSColor(calibratedRed: 0.047, green: 0.063, blue: 0.071, alpha: 1)
  static let surface = NSColor(calibratedRed: 0.078, green: 0.102, blue: 0.109, alpha: 1)
  static let paper = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1)
  static let muted = NSColor(calibratedRed: 0.57, green: 0.65, blue: 0.64, alpha: 1)
  static let lime = NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.49, alpha: 1)
  // Keep the established practice palette, extending it across the whole kit.
  static let colors: [NSColor] = [
    NSColor(calibratedRed: 0.540, green: 0.792, blue: 0.808, alpha: 1),
    NSColor(calibratedRed: 0.807, green: 0.917, blue: 0.578, alpha: 1),
    NSColor(calibratedRed: 0.865, green: 0.683, blue: 0.442, alpha: 1),
    NSColor(calibratedRed: 0.860, green: 0.792, blue: 0.494, alpha: 1),
    NSColor(calibratedRed: 0.570, green: 0.708, blue: 0.893, alpha: 1),
    NSColor(calibratedRed: 0.708, green: 0.642, blue: 0.840, alpha: 1),
    NSColor(calibratedRed: 0.864, green: 0.728, blue: 0.525, alpha: 1),
    NSColor(calibratedRed: 0.556, green: 0.814, blue: 0.701, alpha: 1),
  ]
  static let handPads = [0, 6, 1, 3, 4, 5, 7]
  static let padNames = ["HI-HAT", "SNARE", "KICK", "TOM 1", "TOM 2", "TOM 3", "CRASH", "RIDE"]
  static let keys = ["A", "S", "SPACE", "D", "F", "G", "W", "H"]

  static func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                    color: NSColor = paper) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
  }

  static func draw(_ string: String, in rect: NSRect, size: CGFloat,
                   color: NSColor = paper, weight: NSFont.Weight = .regular,
                   align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align
    paragraph.lineBreakMode = .byTruncatingTail
    (string as NSString).draw(in: rect, withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color, .paragraphStyle: paragraph])
  }

  static func duration(_ seconds: Double) -> String {
    let safe = seconds.isFinite ? max(0, Int(seconds)) : 0
    return String(format: "%d:%02d", safe / 60, safe % 60)
  }
}

final class DrumxSongRootView: NSView {
  var onKey: ((NSEvent) -> Bool)?
  var onDrop: ((URL) -> Void)?
  var onResize: (() -> Void)?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame); registerForDraggedTypes([.fileURL])
  }
  required init?(coder: NSCoder) { nil }
  override func draw(_ dirtyRect: NSRect) { DrumxSongInk.background.setFill(); bounds.fill() }
  override func layout() { super.layout(); onResize?() }
  override func keyDown(with event: NSEvent) {
    if onKey?(event) != true { super.keyDown(with: event) }
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
  }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first else { return false }
    onDrop?(url); return true
  }
}

private final class DrumxSongArtwork: NSView {
  var image: NSImage? { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let shape = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState(); shape.addClip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    if let image {
      image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    } else {
      NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.31, blue: 0.20, alpha: 1),
        ending: DrumxSongInk.surface)?.draw(in: shape, angle: -35)
      for fraction in [0.25, 0.5, 0.76, 0.96] {
        let diameter = bounds.width * fraction
        DrumxSongInk.lime.withAlphaComponent(0.24).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: bounds.midX - diameter / 2,
          y: bounds.midY - diameter / 2, width: diameter, height: diameter))
        ring.lineWidth = fraction == 0.5 ? 3 : 1; ring.stroke()
      }
      DrumxSongInk.lime.setFill()
      NSBezierPath(ovalIn: NSRect(x: bounds.midX - 4, y: bounds.midY - 4, width: 8, height: 8)).fill()
    }
  }
}

final class DrumxSongLibraryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  var onBack: (() -> Void)?
  var onImport: (() -> Void)?
  var onDirectory: (() -> Void)?
  var onEncore: (() -> Void)?
  var onPlay: (() -> Void)?
  var onSelection: ((DrumxSong) -> Void)?
  var onNoSelection: (() -> Void)?
  var onDifficulty: ((String) -> Void)?
  private var songs: [DrumxSong] = [], filtered: [DrumxSong] = []
  private var selectedID: String?
  private let back = LessonButton(title: "‹  Home", target: nil, action: nil)
  private let heading = DrumxSongInk.label("Songs.", size: 48, weight: .semibold)
  private let subtitle = DrumxSongInk.label("Your kit. Your music.", size: 16, color: DrumxSongInk.muted)
  private let encore = LessonButton(title: "Browse Encore ↗", target: nil, action: nil)
  private let directory = LessonButton(title: "Add song directory", target: nil, action: nil)
  private let importButton = LessonButton(title: "Import song", target: nil, action: nil)
  private let search = NSSearchField()
  private let count = DrumxSongInk.label("YOUR LIBRARY", size: 11, weight: .semibold, color: DrumxSongInk.muted)
  private let table = NSTableView()
  private let scroll = NSScrollView()
  private let artwork = DrumxSongArtwork()
  private let title = DrumxSongInk.label("Bring your music.", size: 31, weight: .semibold)
  private let artist = DrumxSongInk.label("Import a Clone Hero or YARG song to get started.", size: 17, color: DrumxSongInk.muted)
  private let metadata = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let detail = NSTextField(wrappingLabelWithString: "")
  private let difficultyLabel = DrumxSongInk.label("DIFFICULTY", size: 10, weight: .semibold, color: DrumxSongInk.muted)
  private let difficulty = DrumxPopUpButton()
  private let play = LessonButton(title: "Play song", target: nil, action: nil)
  private let format = NSTextField(wrappingLabelWithString: "Song folders · .sng · .zip\nDrum charts in notes.mid or notes.chart")
  private let status = NSTextField(wrappingLabelWithString: "")
  private let empty = NSTextField(wrappingLabelWithString: "A library worth playing.\nImport a song, add a song directory, or drop a song folder here.")

  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    for item in [back, heading, subtitle, encore, directory, importButton, search, count, scroll,
                 artwork, title, artist, metadata, detail, difficultyLabel, difficulty, play, format, status, empty] {
      addSubview(item)
    }
    for (button, selector) in [(back, #selector(goBack)), (encore, #selector(openEncore)),
      (directory, #selector(addDirectory)), (importButton, #selector(importSong)), (play, #selector(playSong))] {
      button.target = self; button.action = selector; button.isBordered = false
    }
    importButton.primary = true; play.primary = true; back.quiet = true
    search.placeholderString = "Search songs, artists, or charters"; search.delegate = self
    search.setAccessibilityLabel("Search your song library")
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("song"))
    table.addTableColumn(column); table.headerView = nil; table.rowHeight = 74
    table.intercellSpacing = NSSize(width: 0, height: 3)
    table.dataSource = self; table.delegate = self
    table.backgroundColor = .clear; table.selectionHighlightStyle = .regular
    table.target = self; table.doubleAction = #selector(playSong)
    table.setAccessibilityLabel("Imported drum songs")
    scroll.documentView = table; scroll.hasVerticalScroller = true
    scroll.drawsBackground = false; scroll.borderType = .noBorder
    difficulty.target = self; difficulty.action = #selector(difficultyChanged)
    for field in [detail, format, status, empty] {
      field.font = .systemFont(ofSize: 12); field.textColor = DrumxSongInk.muted
    }
    empty.font = .systemFont(ofSize: 16); empty.alignment = .center
    detail.maximumNumberOfLines = 5; status.maximumNumberOfLines = 2
    play.isEnabled = false; difficulty.isEnabled = false
  }
  required init?(coder: NSCoder) { nil }

  override func draw(_ dirtyRect: NSRect) {
    DrumxSongInk.surface.setFill()
    NSBezierPath(roundedRect: NSRect(x: bounds.width * 0.44, y: 190,
      width: bounds.width * 0.56 - 36, height: max(180, bounds.height - 247)), xRadius: 16, yRadius: 16).fill()
  }

  override func layout() {
    super.layout()
    let w = bounds.width, h = bounds.height, left: CGFloat = 36
    let split = w * 0.44, sidebar = max(200, split - 60), rightX = split + 28
    let rightW = max(210, w - rightX - 64)
    back.frame = NSRect(x: 25, y: 19, width: 100, height: 32)
    heading.frame = NSRect(x: left, y: 59, width: 300, height: 62)
    subtitle.frame = NSRect(x: left + 3, y: 128, width: 300, height: 25)
    importButton.frame = NSRect(x: w - 168, y: 77, width: 132, height: 44)
    directory.frame = NSRect(x: w - 346, y: 77, width: 166, height: 44)
    encore.frame = NSRect(x: w - 507, y: 77, width: 149, height: 44)
    count.frame = NSRect(x: left + 3, y: 182, width: sidebar, height: 20)
    search.frame = NSRect(x: left, y: 214, width: sidebar, height: 32)
    scroll.frame = NSRect(x: left, y: 260, width: sidebar, height: max(100, h - 341))
    table.tableColumns.first?.width = sidebar
    empty.frame = NSRect(x: left + 14, y: 303, width: sidebar - 28, height: 125)
    let artSize = min(160, max(88, (h - 370) * 0.43))
    artwork.frame = NSRect(x: rightX, y: 216, width: artSize, height: artSize)
    let textX = rightX + artSize + 20, textW = rightW - artSize - 20
    title.frame = NSRect(x: textX, y: 222, width: textW, height: 41)
    title.font = .systemFont(ofSize: min(31, max(23, textW / 7)), weight: .semibold)
    artist.frame = NSRect(x: textX + 1, y: 265, width: textW, height: 29)
    metadata.frame = NSRect(x: rightX + 1, y: artwork.frame.maxY + 18, width: rightW, height: 21)
    let controlsY = h - 147
    detail.frame = NSRect(x: rightX + 1, y: metadata.frame.maxY + 12, width: rightW,
      height: max(20, min(72, controlsY - metadata.frame.maxY - 27)))
    difficultyLabel.frame = NSRect(x: rightX + 1, y: controlsY, width: 160, height: 19)
    difficulty.frame = NSRect(x: rightX, y: controlsY + 22, width: min(175, rightW * 0.47), height: 43)
    play.frame = NSRect(x: rightX + rightW * 0.52, y: controlsY + 22, width: rightW * 0.48, height: 43)
    format.frame = NSRect(x: textX + 1, y: 301, width: textW, height: 45)
    format.isHidden = artSize < 125
    status.frame = NSRect(x: left + 3, y: h - 48, width: w - 78, height: 39)
  }

  func update(songs: [DrumxSong], selecting: String? = nil) {
    self.songs = songs; selectedID = selecting ?? selectedID
    filterSongs()
  }
  func setStatus(_ message: String, busy: Bool = false) {
    status.stringValue = message
    importButton.isEnabled = !busy; directory.isEnabled = !busy
    play.isEnabled = !busy && selectedID != nil
  }
  func select(song: DrumxSong, difficulty selected: String, noteCount: Int) {
    selectedID = song.id; title.stringValue = song.title; artist.stringValue = song.artist
    metadata.stringValue = [song.album, "\(DrumxSongInk.duration(song.durationSeconds))",
      song.charter.flatMap { $0.isEmpty ? nil : "Chart: \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    let lanes = Set(song.notes(for: selected).compactMap { $0.pad }).count
    detail.stringValue = "\(noteCount.formatted()) drum notes  ·  \(lanes) instruments  ·  \(song.drumMode)\n"
      + (song.warnings.isEmpty ? "Play the original tempo map with your MIDI kit or keyboard. All song difficulties stay separate from your lessons."
         : song.warnings.prefix(2).joined(separator: " "))
    artwork.image = song.albumArtPath.flatMap { NSImage(contentsOfFile: $0) }
    difficulty.removeAllItems()
    for item in song.difficulties { difficulty.addItem(withTitle: item.capitalized); difficulty.lastItem?.representedObject = item }
    difficulty.selectItem(withTitle: selected.capitalized)
    difficulty.isEnabled = true; play.isEnabled = noteCount > 0
  }

  private func filterSongs() {
    let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    filtered = songs.filter { query.isEmpty || "\($0.title) \($0.artist) \($0.charter ?? "")".localizedCaseInsensitiveContains(query) }
    count.stringValue = "YOUR LIBRARY  /  \(filtered.count) \(filtered.count == 1 ? "SONG" : "SONGS")"
    table.reloadData(); empty.isHidden = !filtered.isEmpty
    empty.stringValue = songs.isEmpty ? "A library worth playing.\n\nImport a song, add a song directory, or drop a song folder here." : "No songs match your search."
    if let index = filtered.firstIndex(where: { $0.id == selectedID }) ?? (filtered.isEmpty ? nil : 0) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      onSelection?(filtered[index])
    } else {
      selectedID = nil; play.isEnabled = false; difficulty.isEnabled = false
      title.stringValue = songs.isEmpty ? "Bring your music." : "No matching songs"
      artist.stringValue = songs.isEmpty ? "Start with a song folder." : "Try another search."
      metadata.stringValue = ""; detail.stringValue = ""; artwork.image = nil
      difficulty.removeAllItems(); onNoSelection?()
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard filtered.indices.contains(table.selectedRow) else { return }
    onSelection?(filtered[table.selectedRow])
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let song = filtered[row], cell = NSTableCellView()
    let name = DrumxSongInk.label(song.title, size: 16, weight: .semibold)
    let artist = DrumxSongInk.label("\(song.artist)  ·  \(DrumxSongInk.duration(song.durationSeconds))", size: 12, color: DrumxSongInk.muted)
    name.frame = NSRect(x: 16, y: 38, width: tableView.bounds.width - 32, height: 24)
    artist.frame = NSRect(x: 16, y: 16, width: tableView.bounds.width - 32, height: 20)
    cell.addSubview(name); cell.addSubview(artist)
    return cell
  }
  func controlTextDidChange(_ obj: Notification) { filterSongs() }
  @objc private func goBack() { onBack?() }
  @objc private func openEncore() { onEncore?() }
  @objc private func addDirectory() { onDirectory?() }
  @objc private func importSong() { onImport?() }
  @objc private func playSong() { if play.isEnabled { onPlay?() } }
  @objc private func difficultyChanged() {
    if let value = difficulty.selectedItem?.representedObject as? String { onDifficulty?(value) }
  }
}

final class DrumxSongHighwayView: NSView {
  var notes: [DrumxSongVisualNote] = []
  var time: Double = -2
  var duration: Double = 1
  var snapshot = DXSnapshot()
  var stateText = ""
  var detailText = ""
  var completed = false
  var eventAt: ((Int) -> DXEvent?)?
  private var flashes: [Int: (host: Double, judgment: Int)] = [:]
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func showHit(pad: Int, judgment: Int) {
    flashes[pad] = (DrumxIO.hostNowSeconds(), judgment); needsDisplay = true
    // A paused transport has no display timer. Clear its transient acknowledgement
    // without touching audio scheduling or the captured input timestamp.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in self?.needsDisplay = true }
  }
  func reset() { flashes.removeAll(); completed = false; stateText = ""; detailText = "" }

  private let stage = NSColor(calibratedRed: 0.055, green: 0.076, blue: 0.082, alpha: 1)
  private let far = NSColor(calibratedRed: 0.078, green: 0.112, blue: 0.121, alpha: 1)
  private let near = NSColor(calibratedRed: 0.120, green: 0.178, blue: 0.186, alpha: 1)
  private let roadLine = NSColor(calibratedRed: 0.240, green: 0.315, blue: 0.320, alpha: 1)

  private func polygon(_ points: [DrumxProjectedPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: NSPoint(x: first.x, y: first.y))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.x, y: point.y)) }
    path.close(); return path
  }

  private func line(_ start: DrumxProjectedPoint, _ end: DrumxProjectedPoint,
                    color: NSColor, width: CGFloat = 1) {
    let path = NSBezierPath(); path.move(to: NSPoint(x: start.x, y: start.y))
    path.line(to: NSPoint(x: end.x, y: end.y)); color.setStroke(); path.lineWidth = width; path.stroke()
  }

  private func shape(pad: Int, projection: DrumxProjection, distance: Double,
                     catcher: Bool = false, scaleX: Double = 1, scaleY: Double = 1) -> NSBezierPath {
    let lateral = pad == 2 ? 0 : projection.laneCenter(DrumxSongInk.handPads.firstIndex(of: pad)!)
    let center = projection.project(lateral: lateral, beatDistance: distance)
    let points: [DrumxProjectedPoint]
    if pad == 2 {
      points = projection.rectangle(centerLateral: 0, beatDistance: distance,
        worldWidth: 0.99, worldDepth: catcher ? 0.065 : 0.045)
    } else if [0, 6, 7].contains(pad) {
      points = projection.cymbal(centerLateral: lateral, beatDistance: distance,
        worldWidth: (catcher ? 0.75 : 0.66) / 7, worldDepth: catcher ? 0.16 : 0.12)
    } else {
      points = projection.drum(centerLateral: lateral, beatDistance: distance,
        worldWidth: (catcher ? 0.75 : 0.66) / 7, worldDepth: catcher ? 0.16 : 0.12)
    }
    return polygon(points.map {
      DrumxProjectedPoint(x: center.x + ($0.x - center.x) * scaleX,
                          y: center.y + ($0.y - center.y) * scaleY)
    })
  }

  private func catcher(pad: Int, projection: DrumxProjection, now: Double, reduceMotion: Bool) {
    let outline = shape(pad: pad, projection: projection, distance: 0, catcher: true)
    let color = DrumxSongInk.colors[pad]
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
    shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
    stage.withAlphaComponent(0.94).setFill(); outline.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color.withAlphaComponent(0.20), ending: color.withAlphaComponent(0.025))?
      .draw(in: outline, angle: 90)
    color.withAlphaComponent(0.65).setStroke(); outline.lineWidth = 1.5; outline.stroke()
    guard let hit = flashes[pad] else { return }
    let age = now - hit.host, envelope = max(0, 1 - age / 0.27)
    guard envelope > 0 else { return }
    if age < 0.065 {
      NSColor.white.withAlphaComponent(0.22 * max(0, 1 - age / 0.065)).setFill(); outline.fill()
    }
    let compression = reduceMotion ? 0 : max(0, 1 - age / 0.07)
    let rebound = reduceMotion ? 0 : max(0, 1 - abs(age - 0.105) / 0.075)
    let response = shape(pad: pad, projection: projection, distance: 0, catcher: true,
      scaleX: 1 + 0.035 * rebound - 0.015 * compression,
      scaleY: 1 + 0.10 * rebound - 0.18 * compression)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = color.withAlphaComponent(0.48 * envelope)
    glow.shadowBlurRadius = reduceMotion ? 6 : 11; glow.shadowOffset = .zero; glow.set()
    color.withAlphaComponent(0.25 * envelope).setFill(); response.fill()
    color.withAlphaComponent(0.94 * envelope).setStroke(); response.lineWidth = 1.8; response.stroke()
    NSGraphicsContext.restoreGraphicsState()
  }

  private func hitBurst(pad: Int, projection: DrumxProjection, now: Double, reduceMotion: Bool) {
    guard let hit = flashes[pad], hit.judgment != Int(DX_IGNORED.rawValue) else { return }
    let progress = (now - hit.host) / 0.30
    guard progress >= 0, progress < 1 else { return }
    let isExtra = hit.judgment == Int(DX_EXTRA.rawValue)
    let color = isExtra ? NSColor(calibratedRed: 0.940, green: 0.451, blue: 0.395, alpha: 1)
      : DrumxSongInk.colors[pad]
    let alpha = 1 - progress
    let center = projection.project(lateral: pad == 2 ? 0
      : projection.laneCenter(DrumxSongInk.handPads.firstIndex(of: pad)!), beatDistance: 0)
    let x = center.x, y = center.y
    if reduceMotion || pad == 2 {
      color.withAlphaComponent(0.75 * alpha).setStroke()
      let outline = shape(pad: pad, projection: projection, distance: 0, catcher: true)
      outline.lineWidth = 2.2; outline.stroke()
      if pad == 2 && !reduceMotion {
        for side in [-1.0, 1.0] {
          let edge = x + side * projection.nearWidth * 0.505
          line(DrumxProjectedPoint(x: edge, y: y - 4),
            DrumxProjectedPoint(x: edge + side * 4 * progress, y: y - 7 - 22 * progress),
            color: color.withAlphaComponent(alpha), width: 2)
        }
      }
    } else if !isExtra {
      let ringWidth = 42 + 35 * progress, ringHeight = 10 + 11 * progress
      let ring = NSBezierPath(ovalIn: NSRect(x: x - ringWidth / 2, y: y - ringHeight / 2,
        width: ringWidth, height: ringHeight))
      color.withAlphaComponent(0.46 * alpha).setStroke(); ring.lineWidth = 1.25; ring.stroke()
      for side in -1...1 {
        let dx = Double(side) * (11 + 17 * progress), rise = 9 + 28 * progress
        line(DrumxProjectedPoint(x: x + dx * 0.8, y: y - rise + 5),
          DrumxProjectedPoint(x: x + dx, y: y - rise - 2),
          color: color.withAlphaComponent(0.8 * alpha), width: 1.6)
      }
    } else {
      for side in [-1.0, 1.0] {
        let dx = projection.nearWidth * 0.40 / 7 + 5 + 13 * progress
        color.withAlphaComponent(0.90 * alpha).setFill()
        polygon([DrumxProjectedPoint(x: x + side * dx, y: y - 5 - 7 * progress),
          DrumxProjectedPoint(x: x + side * (dx + 5), y: y - 1 - 7 * progress),
          DrumxProjectedPoint(x: x + side * (dx + 2), y: y + 3 - 7 * progress)]).fill()
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    stage.setFill(); bounds.fill()
    guard bounds.width > 200, bounds.height > 260 else { return }
    let w = bounds.width, h = bounds.height, left: CGFloat = 44, right = w - 44
    let nowY = max(220, h - 150), top: CGFloat = 66, railW = right - left
    let center = bounds.midX, nearWidth = min(870, w - 132)
    // Reuse the practice highway's homography. Here a world-depth unit is half
    // a second, not an invented musical beat: imported tempo maps remain exact.
    let unitsPerSecond = 2.0, lookSeconds = 2.7
    let projection = DrumxProjection(centerX: Double(center), nearWidth: Double(nearWidth),
      topY: Double(top), strikeY: Double(nowY), previewBeats: lookSeconds * unitsPerSecond)
    let hostNow = DrumxIO.hostNowSeconds()
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    DrumxSongInk.draw("\(DrumxSongInk.duration(max(0, time)))  /  \(DrumxSongInk.duration(duration))",
      in: NSRect(x: left, y: 18, width: 160, height: 25), size: 13, color: DrumxSongInk.muted)
    let metrics = snapshot.total
    let accuracy = metrics.has_accuracy != 0 ? String(format: "%.0f%% hit", metrics.hit_rate_percent) : "Ready to play"
    DrumxSongInk.draw("\(accuracy)    ·    \(metrics.streak) streak    ·    \(metrics.missed) missed",
      in: NSRect(x: w - 470, y: 18, width: 425, height: 25), size: 14, weight: .medium, align: .right)
    DrumxSongInk.paper.withAlphaComponent(0.08).setFill()
    NSBezierPath(roundedRect: NSRect(x: left, y: 51, width: railW, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    DrumxSongInk.lime.setFill()
    NSBezierPath(roundedRect: NSRect(x: left, y: 51, width: railW * min(1, max(0, time / max(1, duration))), height: 3), xRadius: 1.5, yRadius: 1.5).fill()

    let road = polygon([projection.project(lateral: -0.5, beatDistance: projection.previewBeats),
      projection.project(lateral: 0.5, beatDistance: projection.previewBeats),
      projection.project(lateral: 0.5, beatDistance: 0), projection.project(lateral: -0.5, beatDistance: 0)])
    NSGraphicsContext.saveGraphicsState()
    let roadShadow = NSShadow(); roadShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    roadShadow.shadowBlurRadius = 18; roadShadow.shadowOffset = NSSize(width: 0, height: -7); roadShadow.set()
    far.setFill(); road.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); road.addClip()
    NSGradient(starting: far, ending: near)?.draw(from: NSPoint(x: center, y: top),
      to: NSPoint(x: center, y: nowY), options: [])
    NSGraphicsContext.restoreGraphicsState()
    for slot in 0...7 {
      let lateral = -0.5 + Double(slot) / 7
      line(projection.project(lateral: lateral, beatDistance: projection.previewBeats),
        projection.project(lateral: lateral, beatDistance: 0),
        color: roadLine.withAlphaComponent(slot == 0 || slot == 7 ? 0.72 : 0.44),
        width: slot == 0 || slot == 7 ? 1 : 0.7)
    }
    // Unlabelled half-second subdivisions provide motion reference without
    // claiming the song has a fixed tempo or a particular time signature.
    let firstRow = Int(ceil(time * 2)), lastRow = Int(floor((time + lookSeconds) * 2))
    if lastRow >= firstRow {
      for row in firstRow...lastRow {
        let distance = (Double(row) / 2 - time) * unitsPerSecond
        line(projection.project(lateral: -0.5, beatDistance: distance),
          projection.project(lateral: 0.5, beatDistance: distance),
          color: roadLine.withAlphaComponent(0.51), width: 0.65)
      }
    }
    roadLine.withAlphaComponent(0.48).setFill()
    polygon([DrumxProjectedPoint(x: Double(center) - Double(nearWidth) / 2, y: Double(nowY)),
      DrumxProjectedPoint(x: Double(center) + Double(nearWidth) / 2, y: Double(nowY)),
      DrumxProjectedPoint(x: Double(center) + Double(nearWidth) / 2 - 8, y: Double(nowY) + 7),
      DrumxProjectedPoint(x: Double(center) - Double(nearWidth) / 2 + 8, y: Double(nowY) + 7)]).fill()
    line(projection.project(lateral: -0.5, beatDistance: 0), projection.project(lateral: 0.5, beatDistance: 0),
      color: DrumxSongInk.paper.withAlphaComponent(0.78), width: 1.5)
    DrumxSongInk.draw("NOW", in: NSRect(x: center - nearWidth / 2 - 50, y: nowY - 7, width: 39, height: 18),
      size: 11, color: DrumxSongInk.muted, weight: .medium, align: .center)

    // Binary search keeps a long song's drawing proportional to visible notes.
    var low = 0, high = notes.count
    while low < high {
      let middle = (low + high) / 2
      if notes[middle].time < time - 0.015 { low = middle + 1 } else { high = middle }
    }
    var visible: [(note: DrumxSongVisualNote, distance: Double, missed: Bool)] = []
    for index in low..<notes.count {
      let note = notes[index]
      if note.time > time + lookSeconds { break }
      let event = eventAt?(index)
      if let event, event.hit != 0 { continue }
      visible.append((note, (note.time - time) * unitsPerSecond, event?.resolved == 1))
    }
    // Foot geometry remains behind hand geometry, including simultaneous chords.
    // Within each layer, far notes draw first so nearer notes occlude correctly.
    catcher(pad: 2, projection: projection, now: hostNow, reduceMotion: reduceMotion)
    for footLayer in [true, false] {
      if !footLayer {
        hitBurst(pad: 2, projection: projection, now: hostNow, reduceMotion: reduceMotion)
        for pad in DrumxSongInk.handPads { catcher(pad: pad, projection: projection, now: hostNow, reduceMotion: reduceMotion) }
      }
      for item in visible.reversed() where (item.note.pad == 2) == footLayer {
        let alpha = projection.farVisibility(at: item.distance) * (item.missed ? 0.2 : 1)
        let color = DrumxSongInk.colors[item.note.pad]
        let gem = shape(pad: item.note.pad, projection: projection, distance: item.distance)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18 * alpha)
        shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
        color.withAlphaComponent(alpha).setFill(); gem.fill()
        NSGraphicsContext.restoreGraphicsState()
        if [0, 6, 7].contains(item.note.pad) {
          let lateral = projection.laneCenter(DrumxSongInk.handPads.firstIndex(of: item.note.pad)!)
          line(projection.project(lateral: lateral - 0.022, beatDistance: item.distance + 0.015),
            projection.project(lateral: lateral + 0.022, beatDistance: item.distance + 0.015),
            color: stage.withAlphaComponent(0.25 * alpha), width: 1)
        }
      }
    }
    for pad in DrumxSongInk.handPads { hitBurst(pad: pad, projection: projection, now: hostNow, reduceMotion: reduceMotion) }

    // The same atmospheric fade covers road edges, subdivisions and notes.
    let featherHeight = max(38, (nowY - top) * 0.18)
    NSGraphicsContext.saveGraphicsState()
    NSRect(x: 0, y: top, width: w, height: featherHeight).clip()
    NSGradient(starting: stage, ending: stage.withAlphaComponent(0))?.draw(
      from: NSPoint(x: center, y: top), to: NSPoint(x: center, y: top + featherHeight), options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Preserve the established physical-kit silhouettes beneath NOW. These
    // static references are not separate timing destinations.
    for (index, pad) in DrumxSongInk.handPads.enumerated() {
      let point = projection.project(lateral: projection.laneCenter(index), beatDistance: 0)
      let x = CGFloat(point.x), cymbal = [0, 6, 7].contains(pad), color = DrumxSongInk.colors[pad]
      let cy = nowY + (cymbal ? 29 : 43), radius = min(29, nearWidth / 7 * 0.29)
      let ry: CGFloat = cymbal ? 4.5 : 10
      line(DrumxProjectedPoint(x: x, y: nowY + 9), DrumxProjectedPoint(x: x, y: cy - ry - 3),
        color: roadLine.withAlphaComponent(0.75), width: 0.8)
      let oval = NSBezierPath(ovalIn: NSRect(x: x - radius, y: cy - ry, width: radius * 2, height: ry * 2))
      stage.setFill(); oval.fill(); color.withAlphaComponent(0.78).setStroke(); oval.lineWidth = 1.1; oval.stroke()
      if cymbal {
        color.withAlphaComponent(0.6).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3.5, y: cy - 1.4, width: 7, height: 2.8)).fill()
      } else {
        color.withAlphaComponent(0.22).setStroke()
        NSBezierPath(ovalIn: NSRect(x: x - radius + 4, y: cy - ry + 3, width: radius * 2 - 8, height: ry * 2 - 6)).stroke()
      }
      DrumxSongInk.draw("\(DrumxSongInk.padNames[pad]) · \(DrumxSongInk.keys[pad])",
        in: NSRect(x: x - nearWidth / 14, y: cy + ry + 8, width: nearWidth / 7, height: 19),
        size: min(11, nearWidth / 7 * 0.11), color: DrumxSongInk.paper, weight: .medium, align: .center)
    }
    DrumxSongInk.colors[2].withAlphaComponent(0.36).setFill()
    NSBezierPath(roundedRect: NSRect(x: center - nearWidth * 0.20, y: nowY + 83,
      width: nearWidth * 0.40, height: 2), xRadius: 1, yRadius: 1).fill()
    DrumxSongInk.draw("KICK · SPACE", in: NSRect(x: center - 100, y: nowY + 92, width: 200, height: 19),
      size: 11, color: DrumxSongInk.colors[2], weight: .medium, align: .center)
    DrumxSongInk.draw("P  pause       ·       ENTER  restart       ·       ESC  library",
      in: NSRect(x: left, y: h - 30, width: railW, height: 20), size: 11, color: DrumxSongInk.muted, align: .center)
    if !stateText.isEmpty {
      let box = NSRect(x: w * 0.17, y: max(95, nowY * 0.32), width: w * 0.66, height: completed ? 198 : 141)
      DrumxSongInk.background.withAlphaComponent(0.94).setFill()
      NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16).fill()
      DrumxSongInk.draw(stateText, in: NSRect(x: box.minX + 15, y: box.minY + 27, width: box.width - 30, height: 48),
        size: 32, color: DrumxSongInk.lime, weight: .semibold, align: .center)
      DrumxSongInk.draw(detailText, in: NSRect(x: box.minX + 16, y: box.minY + 85, width: box.width - 32, height: 28),
        size: 13, color: DrumxSongInk.muted, align: .center)
      if completed {
        DrumxSongInk.draw("\(metrics.matched) / \(metrics.expected) notes hit   ·   \(metrics.best_streak) best streak   ·   \(metrics.extra) extra hits",
          in: NSRect(x: box.minX + 16, y: box.minY + 127, width: box.width - 32, height: 25), size: 14, align: .center)
        DrumxSongInk.draw("Enter to play again   ·   Escape to choose a song",
          in: NSRect(x: box.minX + 16, y: box.minY + 163, width: box.width - 32, height: 20),
          size: 11, color: DrumxSongInk.muted, align: .center)
      }
    }
  }
}
