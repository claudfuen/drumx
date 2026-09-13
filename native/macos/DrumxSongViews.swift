import AppKit
import ImageIO

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

final class DrumxSongTableView: NSTableView {
  var onKey: ((NSEvent) -> Bool)?
  override func keyDown(with event: NSEvent) {
    if onKey?(event) != true { super.keyDown(with: event) }
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
  private var requestedPath: String?
  private var generation: UInt64 = 0
  private static let thumbnails: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>(); cache.countLimit = 64
    cache.totalCostLimit = 64 * 1024 * 1024; return cache
  }()
  private static let decoding: OperationQueue = {
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 2
    queue.qualityOfService = .userInitiated; queue.name = "org.drumx.song-artwork"; return queue
  }()
  func load(path: String?) {
    if path == requestedPath && image != nil { return }
    requestedPath = path; generation &+= 1
    let token = generation
    image = nil
    guard let path else { return }
    if let cached = Self.thumbnails.object(forKey: path as NSString) { image = cached; return }
    Self.decoding.addOperation { [weak self] in
      guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary),
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 512,
          kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
      else { return }
      let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
      Self.thumbnails.setObject(image, forKey: path as NSString, cost: thumbnail.bytesPerRow * thumbnail.height)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token, self.requestedPath == path else { return }
        self.image = image
      }
    }
  }
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

private final class DrumxSongIntensityMarks: NSView {
  private var rating: DrumxSongIntensity?
  override var isFlipped: Bool { true }
  func setRating(_ rating: DrumxSongIntensity?) {
    self.rating = rating
    toolTip = rating.map { "\($0.source.capitalized) drum intensity: \($0.level) of 6" } ?? "Drum intensity rating pending"
    setAccessibilityLabel(toolTip); needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let rating else {
      DrumxSongInk.draw("Pending", in: bounds, size: 10, color: DrumxSongInk.muted); return
    }
    let diameter = min(10, max(5, (bounds.width - 16) / 5)), gap: CGFloat = 4
    let y = (bounds.height - diameter) / 2
    for index in 0..<5 {
      let x = CGFloat(index) * (diameter + gap)
      if rating.level == 6 {
        let devil = NSBezierPath(ovalIn: NSRect(x: x, y: y + 1, width: diameter, height: diameter))
        devil.move(to: NSPoint(x: x + 1, y: y + diameter * 0.48))
        devil.line(to: NSPoint(x: x, y: y - 3))
        devil.line(to: NSPoint(x: x + diameter * 0.48, y: y + 1)); devil.close()
        devil.move(to: NSPoint(x: x + diameter - 1, y: y + diameter * 0.48))
        devil.line(to: NSPoint(x: x + diameter, y: y - 3))
        devil.line(to: NSPoint(x: x + diameter * 0.52, y: y + 1)); devil.close()
        NSColor(calibratedRed: 0.88, green: 0.41, blue: 0.36, alpha: 1).setFill(); devil.fill()
        DrumxSongInk.background.setFill()
        for eye in [0.28, 0.66] {
          NSBezierPath(ovalIn: NSRect(x: x + diameter * eye, y: y + diameter * 0.45,
            width: max(1, diameter * 0.14), height: max(1, diameter * 0.14))).fill()
        }
      } else {
        let circle = NSBezierPath(ovalIn: NSRect(x: x + 0.5, y: y + 0.5, width: diameter - 1, height: diameter - 1))
        if index < rating.level { DrumxSongInk.paper.withAlphaComponent(0.85).setFill(); circle.fill() }
        else { DrumxSongInk.muted.withAlphaComponent(0.40).setStroke(); circle.lineWidth = 1; circle.stroke() }
      }
    }
  }
}

private final class DrumxSongRow: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 3, dy: 2)
    DrumxSongInk.lime.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    DrumxSongInk.lime.withAlphaComponent(0.72).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 12,
      width: 3, height: max(0, rect.height - 24)), xRadius: 1.5, yRadius: 1.5).fill()
  }
}

private final class DrumxSongCell: NSTableCellView {
  private let songTitle = DrumxSongInk.label("", size: 15, weight: .medium)
  private let songArtist = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let songDuration = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let levels = DrumxSongInk.label("", size: 11, weight: .medium, color: DrumxSongInk.muted)
  private let intensity = DrumxSongIntensityMarks()
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    for view in [songTitle, songArtist, songDuration, levels, intensity] { addSubview(view) }
    textField = songTitle; songDuration.alignment = .right; levels.alignment = .right
    songDuration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
  }
  required init?(coder: NSCoder) { nil }
  func configure(_ song: DrumxSong, difficulty: String) {
    songTitle.stringValue = song.title; songArtist.stringValue = song.artist
    songDuration.stringValue = DrumxSongInk.duration(song.durationSeconds)
    levels.stringValue = ["easy", "medium", "hard", "expert"].map {
      song.difficulties.contains($0) ? ($0 == "expert" ? "X" : String($0.prefix(1)).uppercased()) : "·"
    }.joined(separator: "  ")
    intensity.setRating(song.intensity(for: difficulty))
    toolTip = "\(song.title) by \(song.artist) · \(song.difficulties.map { $0.capitalized }.joined(separator: ", "))"
  }
  override func layout() {
    super.layout()
    let textWidth = max(70, bounds.width - 164)
    songTitle.frame = NSRect(x: 16, y: 10, width: textWidth, height: 23)
    songArtist.frame = NSRect(x: 16, y: 34, width: textWidth, height: 20)
    songDuration.frame = NSRect(x: bounds.width - 139, y: 24, width: 43, height: 20)
    levels.frame = NSRect(x: bounds.width - 85, y: 13, width: 69, height: 18)
    intensity.frame = NSRect(x: bounds.width - 83, y: 37, width: 65, height: 16)
  }
}

private final class DrumxSongPreviewTrack: NSView {
  var progress: Double = 0 { didSet { needsDisplay = true } }
  var active = false { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    let track = NSRect(x: 0, y: bounds.midY - 1.5, width: bounds.width, height: 3)
    DrumxSongInk.paper.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
    if active {
      DrumxSongInk.lime.withAlphaComponent(0.8).setFill()
      NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY,
        width: bounds.width * min(1, max(0, progress)), height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }
  }
}

final class DrumxSongLibraryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  var onBack: (() -> Void)?
  var onImport: (() -> Void)?
  var onDirectory: (() -> Void)?
  var onRefresh: (() -> Void)?
  var onEncore: (() -> Void)?
  var onPlay: (() -> Void)?
  var onSelection: ((DrumxSong) -> Void)?
  var onNoSelection: (() -> Void)?
  var onDifficulty: ((String) -> Void)?
  var onPreviewToggle: (() -> Void)?
  var onRetryScoreSave: (() -> Void)?
  private var songs: [DrumxSong] = [], filtered: [DrumxSong] = []
  private var selectedID: String?
  private var displayedSongID: String?
  private var applyingFilter = false
  private var busy = false
  private var statusMessage = ""
  private var scoreSaveError: String?
  private var selectedNoteCount = 0
  private var previewOrigin: Double?
  private var previewEnd: Double?
  private var previewCurrent: Double?
  private let heading = DrumxSongInk.label("Songs", size: 32, weight: .semibold)
  private let count = DrumxSongInk.label("0 songs", size: 13, color: DrumxSongInk.muted)
  private let back = LessonButton(title: "‹  Home", target: nil, action: nil)
  private let importButton = LessonButton(title: "Import song", target: nil, action: nil)
  private let directory = LessonButton(title: "Add folder", target: nil, action: nil)
  private let refresh = LessonButton(title: "Refresh", target: nil, action: nil)
  private let encore = LessonButton(title: "Encore ↗", target: nil, action: nil)
  private let search = NSSearchField()
  private let sort = DrumxPopUpButton()
  private let filter = DrumxPopUpButton()
  private let listHeading = DrumxSongInk.label("SONG / ARTIST", size: 10, weight: .medium, color: DrumxSongInk.muted)
  private let timeHeading = DrumxSongInk.label("TIME", size: 10, weight: .medium, color: DrumxSongInk.muted)
  private let levelsHeading = DrumxSongInk.label("DRUMS", size: 10, weight: .medium, color: DrumxSongInk.muted)
  private let table = DrumxSongTableView()
  var onKey: ((NSEvent) -> Bool)? {
    didSet { table.onKey = onKey }
  }
  private let scroll = NSScrollView()
  private let selectedHeading = DrumxSongInk.label("SELECTED SONG", size: 10, weight: .medium, color: DrumxSongInk.muted)
  private let artwork = DrumxSongArtwork()
  private let title = DrumxSongInk.label("Your next song", size: 27, weight: .semibold)
  private let artist = DrumxSongInk.label("Choose something to play.", size: 15, color: DrumxSongInk.muted)
  private let metadata = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let intensityLabel = DrumxSongInk.label("Intensity", size: 11, color: DrumxSongInk.muted)
  private let intensity = DrumxSongIntensityMarks()
  private let intensitySource = DrumxSongInk.label("", size: 10, color: DrumxSongInk.muted)
  private let preview = LessonButton(title: "▶  Preview", target: nil, action: nil)
  private let previewTime = DrumxSongInk.label("Mid-song excerpt", size: 11, color: DrumxSongInk.muted)
  private let previewTrack = DrumxSongPreviewTrack()
  private let difficultyLabel = DrumxSongInk.label("PLAY DIFFICULTY", size: 10, weight: .medium, color: DrumxSongInk.muted)
  private let difficulty = DrumxPopUpButton()
  private let detail = DrumxSongInk.label("", size: 12, color: DrumxSongInk.muted)
  private let bestHeading = DrumxSongInk.label("YOUR BEST", size: 10, weight: .medium, color: DrumxSongInk.muted)
  private let stars = DrumxSongInk.label("", size: 21, weight: .medium, color: DrumxSongInk.lime)
  private let bestValue = DrumxSongInk.label("No completed plays yet", size: 13, color: DrumxSongInk.muted)
  private let bestDetail = DrumxSongInk.label("", size: 11, color: DrumxSongInk.muted)
  private let play = LessonButton(title: "Play song  ↵", target: nil, action: nil)
  private let hint = DrumxSongInk.label("↑ ↓  Browse     Enter  Play     Space  Preview", size: 11, color: DrumxSongInk.muted)
  private let status = DrumxSongInk.label("", size: 11, color: DrumxSongInk.muted)
  private let retrySave = LessonButton(title: "Retry save", target: nil, action: nil)
  private let empty = NSTextField(wrappingLabelWithString: "Add your first songs\n\nImport a song or add a folder to start your library.")

  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    for item in [heading, count, back, importButton, directory, refresh, encore, search, sort, filter,
      listHeading, timeHeading, levelsHeading, scroll, selectedHeading, artwork, title, artist, metadata,
      intensityLabel, intensity, intensitySource,
      preview, previewTime, previewTrack, difficultyLabel, difficulty, detail, bestHeading, stars,
      bestValue, bestDetail, play, hint, status, retrySave, empty] { addSubview(item) }
    for (button, selector) in [(back, #selector(goBack)), (encore, #selector(openEncore)),
      (directory, #selector(addDirectory)), (importButton, #selector(importSong)), (play, #selector(playSong)),
      (preview, #selector(togglePreview)), (refresh, #selector(refreshLibrary)),
      (retrySave, #selector(retryScoreSave))] {
      button.target = self; button.action = selector; button.isBordered = false; button.quiet = true
    }
    play.quiet = false; play.primary = true
    retrySave.isHidden = true
    search.placeholderString = "Search songs or artists"; search.delegate = self
    search.controlSize = .large; search.focusRingType = .none
    search.setAccessibilityLabel("Search your song library")
    sort.addItems(withTitles: ["Artist A–Z", "Title A–Z", "Duration"])
    sort.target = self; sort.action = #selector(filtersChanged)
    sort.setAccessibilityLabel("Sort songs")
    filter.addItems(withTitles: ["All difficulties", "Easy", "Medium", "Hard", "Expert"])
    filter.target = self; filter.action = #selector(filtersChanged)
    filter.setAccessibilityLabel("Filter songs by authored difficulty")
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("song"))
    table.addTableColumn(column); table.headerView = nil; table.rowHeight = 64
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.dataSource = self; table.delegate = self; table.backgroundColor = .clear
    table.selectionHighlightStyle = .regular; table.focusRingType = .none
    table.target = self; table.doubleAction = #selector(playSong)
    table.setAccessibilityLabel("Song library")
    scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.drawsBackground = false; scroll.borderType = .noBorder
    difficulty.target = self; difficulty.action = #selector(difficultyChanged)
    difficulty.setAccessibilityLabel("Play difficulty")
    for field in [title, artist, metadata] { field.alignment = .center }
    previewTime.alignment = .right; timeHeading.alignment = .right; levelsHeading.alignment = .right
    levelsHeading.toolTip = "Authored difficulties: Easy, Medium, Hard, Expert. Marks below show drum intensity."
    title.maximumNumberOfLines = 1
    empty.font = .systemFont(ofSize: 16); empty.textColor = DrumxSongInk.muted; empty.alignment = .center
    play.isEnabled = false; difficulty.isEnabled = false; preview.isEnabled = false
    setAccessibilityLabel("Songs")
  }
  required init?(coder: NSCoder) { nil }

  private var listWidth: CGFloat { max(360, (bounds.width - 80) * 0.56) }
  private var card: NSRect {
    NSRect(x: 28 + listWidth + 24, y: 88, width: max(280, bounds.width - listWidth - 80),
      height: max(450, bounds.height - 146))
  }
  override func draw(_ dirtyRect: NSRect) {
    DrumxSongInk.surface.withAlphaComponent(0.82).setFill()
    NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16).fill()
    DrumxSongInk.paper.withAlphaComponent(0.075).setStroke()
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 28, y: 75)); divider.line(to: NSPoint(x: bounds.width - 28, y: 75))
    divider.lineWidth = 1; divider.stroke()
  }
  override func layout() {
    super.layout()
    let w = bounds.width, h = bounds.height, list = listWidth, rect = card
    heading.frame = NSRect(x: 28, y: 24, width: 108, height: 41)
    count.frame = NSRect(x: 148, y: 37, width: max(110, w - 665), height: 22)
    let utilityWidths: [CGFloat] = [82, 102, 96, 82, 94]
    var utilityX = w - 28 - utilityWidths.reduce(0, +)
    for (button, width) in zip([back, importButton, directory, refresh, encore], utilityWidths) {
      button.frame = NSRect(x: utilityX, y: 28, width: width, height: 34); utilityX += width
    }
    search.frame = NSRect(x: 28, y: 90, width: max(120, list - 255), height: 34)
    sort.frame = NSRect(x: 28 + list - 247, y: 90, width: 112, height: 34)
    filter.frame = NSRect(x: 28 + list - 127, y: 90, width: 127, height: 34)
    listHeading.frame = NSRect(x: 44, y: 142, width: list - 175, height: 17)
    timeHeading.frame = NSRect(x: 28 + list - 139, y: 142, width: 43, height: 17)
    levelsHeading.frame = NSRect(x: 28 + list - 85, y: 142, width: 69, height: 17)
    scroll.frame = NSRect(x: 28, y: 166, width: list, height: max(160, h - 230))
    table.tableColumns.first?.width = scroll.contentSize.width
    empty.frame = NSRect(x: 55, y: 250, width: list - 54, height: 150)
    let x = rect.minX + 24, inner = rect.width - 48
    selectedHeading.frame = NSRect(x: x, y: rect.minY + 18, width: inner, height: 18)
    let compact = h < 790
    let lowerY: CGFloat
    if compact {
      let artSize = min(128, max(92, inner * 0.29))
      artwork.frame = NSRect(x: x, y: rect.minY + 45, width: artSize, height: artSize)
      let textX = artwork.frame.maxX + 18, textW = inner - artSize - 18
      title.alignment = .left; artist.alignment = .left; metadata.alignment = .left
      title.maximumNumberOfLines = 2; title.lineBreakMode = .byWordWrapping
      title.font = .systemFont(ofSize: 23, weight: .semibold)
      title.frame = NSRect(x: textX, y: artwork.frame.minY + 2, width: textW, height: 58)
      artist.frame = NSRect(x: textX, y: artwork.frame.minY + 64, width: textW, height: 23)
      metadata.frame = NSRect(x: textX, y: artwork.frame.minY + 90, width: textW, height: 20)
      lowerY = artwork.frame.maxY + 22
    } else {
      let artSize = min(190, max(112, (h - 560) * 0.7))
      artwork.frame = NSRect(x: rect.midX - artSize / 2, y: rect.minY + 45, width: artSize, height: artSize)
      let textY = artwork.frame.maxY + 17
      title.alignment = .center; artist.alignment = .center; metadata.alignment = .center
      title.maximumNumberOfLines = 1; title.lineBreakMode = .byTruncatingTail
      title.font = .systemFont(ofSize: inner < 340 ? 24 : 27, weight: .semibold)
      title.frame = NSRect(x: x - 1, y: textY, width: inner + 2, height: 36)
      artist.frame = NSRect(x: x, y: textY + 39, width: inner, height: 24)
      metadata.frame = NSRect(x: x, y: textY + 65, width: inner, height: 20)
      lowerY = textY + 92
    }
    intensityLabel.frame = NSRect(x: rect.midX - 109, y: lowerY, width: 54, height: 17)
    intensity.frame = NSRect(x: rect.midX - 49, y: lowerY - 2, width: 73, height: 20)
    intensitySource.frame = NSRect(x: rect.midX + 31, y: lowerY + 1, width: 87, height: 17)
    preview.frame = NSRect(x: x - 6, y: lowerY + 34, width: 128, height: 32)
    previewTime.frame = NSRect(x: x + 128, y: lowerY + 43, width: inner - 128, height: 18)
    previewTrack.frame = NSRect(x: x, y: lowerY + 70, width: inner, height: 8)
    difficultyLabel.frame = NSRect(x: x, y: lowerY + 93, width: 130, height: 17)
    difficulty.frame = NSRect(x: x + inner - 142, y: lowerY + 84, width: 142, height: 34)
    detail.frame = NSRect(x: x, y: lowerY + 127, width: inner, height: 21)
    bestHeading.frame = NSRect(x: x, y: lowerY + 166, width: inner, height: 17)
    stars.frame = NSRect(x: x, y: lowerY + 188, width: 130, height: 28)
    bestValue.frame = NSRect(x: x + (stars.stringValue.isEmpty ? 0 : 139), y: lowerY + 193,
      width: inner - (stars.stringValue.isEmpty ? 0 : 139), height: 21)
    bestDetail.frame = NSRect(x: x, y: lowerY + 220, width: inner, height: 19)
    play.frame = NSRect(x: x, y: rect.maxY - 64, width: inner, height: 43)
    hint.frame = NSRect(x: 31, y: h - 42, width: list, height: 20)
    status.frame = NSRect(x: rect.minX + 3, y: h - 42,
      width: rect.width - (scoreSaveError == nil ? 6 : 102), height: 20)
    retrySave.frame = NSRect(x: rect.maxX - 92, y: h - 49, width: 92, height: 32)
  }

  func update(songs: [DrumxSong], selecting: String? = nil) {
    self.songs = songs; selectedID = selecting ?? selectedID; filterSongs()
  }
  func setStatus(_ message: String, busy: Bool = false) {
    self.busy = busy; statusMessage = message
    status.stringValue = scoreSaveError ?? message; status.toolTip = scoreSaveError ?? message
    importButton.isEnabled = !busy; directory.isEnabled = !busy; refresh.isEnabled = !busy
    play.isEnabled = !busy && selectedID != nil && selectedNoteCount > 0
  }
  func setPreviewState(active: Bool, pending: Bool = false) {
    preview.title = active ? "■  Stop preview" : pending ? "Cancel preview" : "▶  Preview"
    preview.isEnabled = selectedID != nil; preview.needsDisplay = true
    previewTrack.active = active
    if pending || !active {
      previewOrigin = nil; previewEnd = nil; previewCurrent = nil; previewTrack.progress = 0
      previewTime.stringValue = pending ? "Preparing preview…" : "Mid-song excerpt"
    }
  }
  func setPreviewPosition(current: Double, end: Double) {
    guard current.isFinite, end.isFinite, end > current else { return }
    if previewOrigin == nil || previewEnd != end || current < (previewCurrent ?? current) {
      previewOrigin = current
    }
    previewEnd = end; previewCurrent = current
    let origin = previewOrigin ?? current
    previewTrack.progress = (current - origin) / max(0.01, end - origin)
    previewTime.stringValue = "\(DrumxSongInk.duration(current)) / \(DrumxSongInk.duration(end))"
  }
  func setBest(_ summary: DrumxSongScoreSummary?, error: String? = nil) {
    bestDetail.toolTip = nil
    guard let summary else {
      stars.stringValue = ""; bestValue.stringValue = error == nil ? "No completed plays yet" : "Best score unavailable"
      bestDetail.stringValue = ""; bestValue.toolTip = error; needsLayout = true; return
    }
    let score = summary.best.score
    stars.stringValue = String(repeating: "★", count: min(5, max(0, score.stars)))
      + String(repeating: "☆", count: 5 - min(5, max(0, score.stars)))
    bestValue.stringValue = "\(score.points.formatted()) points"; bestValue.toolTip = nil
    bestDetail.stringValue = "\(score.fullCombo ? "Full combo" : "Best combo \(score.bestCombo.formatted())")  ·  \(summary.playCount.formatted()) \(summary.playCount == 1 ? "play" : "plays")"
    bestDetail.toolTip = "Completed \(summary.best.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f", score.hitRatePercent))% hit rate"
    needsLayout = true
  }
  func setScoreSaveError(_ message: String?) {
    scoreSaveError = message; retrySave.isHidden = message == nil
    status.stringValue = message ?? statusMessage; status.toolTip = message ?? statusMessage
    status.textColor = message == nil ? DrumxSongInk.muted : NSColor(calibratedRed: 0.91, green: 0.66, blue: 0.47, alpha: 1)
    needsLayout = true
  }
  func moveSelection(_ offset: Int) {
    guard !filtered.isEmpty else { return }
    let row = table.selectedRow < 0 ? 0 : min(filtered.count - 1, max(0, table.selectedRow + offset))
    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    table.scrollRowToVisible(row); window?.makeFirstResponder(table)
  }
  func select(song: DrumxSong, difficulty selected: String, noteCount: Int) {
    let changedSong = displayedSongID != song.id
    displayedSongID = song.id
    selectedID = song.id; selectedNoteCount = noteCount
    title.stringValue = song.title; title.toolTip = song.title; artist.stringValue = song.artist
    metadata.stringValue = [song.album, DrumxSongInk.duration(song.durationSeconds)]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    metadata.toolTip = song.charter.flatMap { $0.isEmpty ? nil : "Chart by \($0)" }
    let rating = song.intensity(for: selected)
    intensity.setRating(rating); intensitySource.stringValue = rating?.source.capitalized ?? ""
    detail.stringValue = "\(noteCount.formatted()) notes"
      + (song.instrumentCount(for: selected).map { "  ·  \($0) kit voices" } ?? "")
      + (song.charter.flatMap { $0.isEmpty ? nil : "  ·  \($0)" } ?? "")
    detail.toolTip = song.warnings.isEmpty ? nil : song.warnings.joined(separator: "\n")
    if changedSong || artwork.image == nil { artwork.load(path: song.albumArtPath) }
    difficulty.removeAllItems()
    for item in song.difficulties { difficulty.addItem(withTitle: item.capitalized); difficulty.lastItem?.representedObject = item }
    difficulty.selectItem(withTitle: selected.capitalized)
    difficulty.isEnabled = true; play.isEnabled = !busy && noteCount > 0
    bestHeading.stringValue = "YOUR BEST  ·  \(selected.uppercased())"
    if changedSong { setBest(nil) }
  }
  private func notifySelection(_ song: DrumxSong) {
    onSelection?(song)
    if filter.indexOfSelectedItem > 0,
      let selected = filter.titleOfSelectedItem?.lowercased(), song.difficulties.contains(selected) {
      onDifficulty?(selected)
    }
  }
  private func filterSongs() {
    let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedDifficulty = filter.indexOfSelectedItem > 0 ? filter.titleOfSelectedItem?.lowercased() : nil
    filtered = songs.filter {
      (query.isEmpty || "\($0.title) \($0.artist) \($0.album ?? "") \($0.charter ?? "")".localizedCaseInsensitiveContains(query))
        && (selectedDifficulty == nil || $0.difficulties.contains(selectedDifficulty!))
    }
    let sortIndex = sort.indexOfSelectedItem
    filtered.sort { left, right in
      if sortIndex == 2 && left.durationSeconds != right.durationSeconds { return left.durationSeconds < right.durationSeconds }
      let first = sortIndex == 0 ? left.artist.localizedStandardCompare(right.artist) : left.title.localizedStandardCompare(right.title)
      if first != .orderedSame { return first == .orderedAscending }
      let second = left.title.localizedStandardCompare(right.title)
      return second == .orderedSame ? left.id < right.id : second == .orderedAscending
    }
    count.stringValue = filtered.count == songs.count
      ? "\(songs.count.formatted()) \(songs.count == 1 ? "song" : "songs")"
      : "\(filtered.count.formatted()) of \(songs.count.formatted()) songs"
    applyingFilter = true
    table.reloadData(); empty.isHidden = !filtered.isEmpty
    empty.stringValue = songs.isEmpty ? "Add your first songs\n\nImport a song or add a folder to start your library." : "No matching songs\n\nTry a different search or difficulty."
    if let index = filtered.firstIndex(where: { $0.id == selectedID }) ?? (filtered.isEmpty ? nil : 0) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      table.scrollRowToVisible(index); applyingFilter = false; notifySelection(filtered[index])
    } else {
      table.deselectAll(nil); selectedID = nil; selectedNoteCount = 0
      play.isEnabled = false; difficulty.isEnabled = false; preview.isEnabled = false
      title.stringValue = songs.isEmpty ? "Your next song" : "Nothing selected"
      artist.stringValue = songs.isEmpty ? "Add something you love to play." : "Try another search or difficulty."
      metadata.stringValue = ""; detail.stringValue = ""; artwork.load(path: nil); displayedSongID = nil
      intensity.setRating(nil); intensitySource.stringValue = ""
      difficulty.removeAllItems(); setBest(nil); setPreviewState(active: false)
      applyingFilter = false; onNoSelection?()
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !applyingFilter, filtered.indices.contains(table.selectedRow) else { return }
    notifySelection(filtered[table.selectedRow])
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { DrumxSongRow() }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier = NSUserInterfaceItemIdentifier("song-cell")
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? DrumxSongCell ?? DrumxSongCell()
    let level = filter.indexOfSelectedItem > 0 ? filter.titleOfSelectedItem!.lowercased() : filtered[row].selectedDifficulty
    cell.identifier = identifier; cell.configure(filtered[row], difficulty: level); return cell
  }
  func controlTextDidChange(_ obj: Notification) { filterSongs() }
  @objc private func filtersChanged() { filterSongs() }
  @objc private func goBack() { onBack?() }
  @objc private func openEncore() { onEncore?() }
  @objc private func addDirectory() { onDirectory?() }
  @objc private func refreshLibrary() { onRefresh?() }
  @objc private func importSong() { onImport?() }
  @objc private func playSong() { if play.isEnabled { onPlay?() } }
  @objc private func togglePreview() { if preview.isEnabled { onPreviewToggle?() } }
  @objc private func retryScoreSave() { onRetryScoreSave?() }
  @objc private func difficultyChanged() {
    if let value = difficulty.selectedItem?.representedObject as? String { onDifficulty?(value) }
  }
}

final class DrumxSongHighwayView: NSView {
  var score: DrumxSongScore?
  var personalBestPoints: Int?
  var recordText = ""
  var timingFeedback = DrumxSongTimingFeedback().state(at: 0)
  /// Visual speed only. The audio transport and imported event times are untouched.
  var scrollSpeed: Double = 1.25 { didSet { needsDisplay = true } }
  var notes: [DrumxSongVisualNote] = []
  var gridLines: [DrumxSongGridLine] = []
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

  private func sideFeedback(roadWidth: CGFloat, nowY: CGFloat) {
    let margin: CGFloat = 24, available = (bounds.width - roadWidth) / 2 - margin * 2
    guard available >= 64 else { return }
    let panelW = min(160, available), leftX = (bounds.width - roadWidth) / 2 - panelW - 24
    let rightX = (bounds.width + roadWidth) / 2 + 24
    let y = max(120, nowY * 0.48)
    func ink(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 11,
             color: NSColor = DrumxSongInk.muted, weight: NSFont.Weight = .regular) {
      DrumxSongInk.draw(value, in: NSRect(x: x, y: y, width: panelW, height: size + 10),
        size: size, color: color, weight: weight)
    }
    ink("SCORE", x: leftX, y: y, size: 10, weight: .semibold)
    ink((score?.points ?? 0).formatted(), x: leftX, y: y + 23, size: min(29, panelW * 0.22),
      color: DrumxSongInk.paper, weight: .semibold)
    let stars = score?.stars ?? 0
    ink(String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars),
      x: leftX, y: y + 66, size: min(19, panelW / 6), color: DrumxSongInk.lime)
    let progressY = y + 97
    DrumxSongInk.paper.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: NSRect(x: leftX, y: progressY, width: panelW, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    DrumxSongInk.lime.setFill()
    NSBezierPath(roundedRect: NSRect(x: leftX, y: progressY,
      width: panelW * CGFloat(score?.progressToNextStar ?? 0), height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    ink("\(score?.multiplier ?? 1)×  MULTIPLIER", x: leftX, y: y + 119, size: 10,
      color: (score?.multiplier ?? 1) == 4 ? DrumxSongInk.lime : DrumxSongInk.paper, weight: .semibold)
    ink("\(score?.combo ?? 0) note streak", x: leftX, y: y + 143)
    ink("PERSONAL BEST", x: leftX, y: y + 194, size: 9, weight: .semibold)
    ink(personalBestPoints?.formatted() ?? "Set your first score", x: leftX, y: y + 213,
      size: 12, color: DrumxSongInk.paper)

    let feedback = timingFeedback
    let active = feedback.offsetMS != nil
    let tint = feedback.status == .centered ? DrumxSongInk.lime
      : feedback.status == .uneven ? DrumxSongInk.colors[2] : DrumxSongInk.colors[0]
    ink("TIMING", x: rightX, y: y, size: 10, weight: .semibold)
    ink(feedback.label, x: rightX, y: y + 24, size: min(16, panelW / 7),
      color: active ? tint : DrumxSongInk.muted, weight: .medium)
    let railY = y + 74, middle = rightX + panelW / 2
    DrumxSongInk.paper.withAlphaComponent(0.15).setFill()
    NSBezierPath(roundedRect: NSRect(x: rightX, y: railY, width: panelW, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    DrumxSongInk.lime.withAlphaComponent(0.35).setFill()
    NSRect(x: middle - panelW * 0.075, y: railY - 4, width: panelW * 0.15, height: 11).fill()
    if let offset = feedback.offsetMS {
      let x = middle + CGFloat(min(1, max(-1, offset / 80))) * (panelW / 2 - 4)
      tint.setFill(); NSBezierPath(ovalIn: NSRect(x: x - 4, y: railY - 3, width: 8, height: 8)).fill()
      ink(String(format: "%+.0f ms", offset), x: rightX, y: y + 122, size: 19, color: tint, weight: .medium)
    }
    ink("EARLY", x: rightX, y: railY + 17, size: 9)
    DrumxSongInk.draw("LATE", in: NSRect(x: rightX, y: railY + 17, width: panelW, height: 19),
      size: 9, color: DrumxSongInk.muted, align: .right)
    ink("Recent matched hits", x: rightX, y: y + 154, size: 10)
  }

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

  private func vertices(pad: Int, projection: DrumxProjection, distance: Double,
                        catcher: Bool = false, scaleX: Double = 1, scaleY: Double = 1) -> [DrumxProjectedPoint] {
    let center = DrumxSongGeometry.center(pad: pad, distance: distance, road: projection)
    let rings = DrumxSongGeometry.rings(pad: pad, distance: distance, road: projection, catcher: catcher)
    let alignment = DrumxSongGeometry.alignmentOffset(rings: rings, pad: pad, distance: distance, road: projection)
    return rings.last!.map {
      let point = DrumxSongGeometry.projectFace($0, pad: pad, distance: distance, road: projection)
      return DrumxProjectedPoint(x: center.x + (point.x - center.x) * scaleX,
                                 y: center.y + (point.y + alignment - center.y) * scaleY)
    }
  }

  private func shape(pad: Int, projection: DrumxProjection, distance: Double,
                     catcher: Bool = false, scaleX: Double = 1, scaleY: Double = 1) -> NSBezierPath {
    polygon(vertices(pad: pad, projection: projection, distance: distance,
      catcher: catcher, scaleX: scaleX, scaleY: scaleY))
  }

  private func material(pad: Int, projection: DrumxProjection, distance: Double,
                        alpha: Double, catcher: Bool = false) {
    let rings = DrumxSongGeometry.rings(pad: pad, distance: distance, road: projection, catcher: catcher)
    let color = DrumxSongInk.colors[pad]
    let factor = projection.width(at: distance) / projection.nearWidth
    let alignment = DrumxSongGeometry.alignmentOffset(rings: rings, pad: pad, distance: distance, road: projection)
    func projected(_ ring: [DrumxSongVertex]) -> NSBezierPath {
      polygon(ring.map {
        let point = DrumxSongGeometry.projectFace($0, pad: pad, distance: distance, road: projection)
        return DrumxProjectedPoint(x: point.x, y: point.y + alignment)
      })
    }
    let footprint = rings[0].map { DrumxSongVertex(x: $0.x, z: $0.z, height: 0) }
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(alpha * 0.65)
    shadow.shadowBlurRadius = CGFloat(3 * factor); shadow.shadowOffset = .zero; shadow.set()
    NSColor.black.withAlphaComponent(alpha * 0.42).setFill(); projected(footprint).fill()
    NSGraphicsContext.restoreGraphicsState()
    var faces: [[DrumxSongVertex]] = []
    for level in 0..<(rings.count - 1) {
      for index in rings[level].indices {
        let next = (index + 1) % rings[level].count
        faces.append([rings[level][index], rings[level][next], rings[level + 1][next], rings[level + 1][index]])
      }
    }
    // Paint back-to-front in camera depth. These are real projected bevel and
    // shell faces, including the lateral parallax of raised outer-lane notes.
    faces.sort {
      let a = $0.reduce(0) { $0 + $1.z - tan(DrumxSongGeometry.pitch) * $1.height }
      let b = $1.reduce(0) { $0 + $1.z - tan(DrumxSongGeometry.pitch) * $1.height }
      return a > b
    }
    for face in faces {
      let intensity = DrumxSongGeometry.light(face)
      let lit = color.blended(withFraction: max(0, 0.80 - intensity * 0.86), of: .black) ?? color
      let surface = catcher ? lit.blended(withFraction: 0.38, of: .black) ?? lit : lit
      surface.withAlphaComponent(alpha).setFill()
      let path = projected(face); path.fill()
      // A subpixel same-color stroke seals antialiasing seams between facets.
      surface.withAlphaComponent(alpha).setStroke(); path.lineWidth = 0.4; path.stroke()
    }
    let cap = projected(rings.last!)
    let capLight = color.blended(withFraction: catcher ? 0.90 : 0.42, of: catcher ? .black : .white) ?? color
    let capDark = color.blended(withFraction: catcher ? 0.98 : 0.12, of: .black) ?? color
    NSGraphicsContext.saveGraphicsState(); cap.addClip()
    NSGradient(starting: capLight.withAlphaComponent(alpha), ending: capDark.withAlphaComponent(alpha))?.draw(
      from: NSPoint(x: cap.bounds.minX, y: cap.bounds.minY),
      to: NSPoint(x: cap.bounds.maxX, y: cap.bounds.maxY), options: [])
    NSGraphicsContext.restoreGraphicsState()
    (catcher ? color : NSColor.white).withAlphaComponent(alpha * (catcher ? 0.70 : 0.38)).setStroke()
    cap.lineWidth = CGFloat(max(0.45, factor * 0.65)); cap.stroke()
  }

  private func catcher(pad: Int, projection: DrumxProjection, now: Double, reduceMotion: Bool) {
    let outline = shape(pad: pad, projection: projection, distance: 0, catcher: true)
    let color = DrumxSongInk.colors[pad]
    material(pad: pad, projection: projection, distance: 0, alpha: 1, catcher: true)
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
    let center = DrumxSongGeometry.center(pad: pad, distance: 0, road: projection)
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
      let ring = NSBezierPath(ovalIn: NSRect(x: CGFloat(x - ringWidth / 2), y: CGFloat(y - ringHeight / 2),
        width: CGFloat(ringWidth), height: CGFloat(ringHeight)))
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
    let nowY = max(220, h - 150), top: CGFloat = 56, railW = right - left
    let center = bounds.midX, nearWidth = min(650, w * 0.62)
    // Reuse the practice highway's homography with a fixed world surface. Speed
    // changes only seconds-to-distance, keeping gem dimensions and NOW fixed.
    // A world-depth unit is half a second at 1×, not an invented musical beat.
    let unitsPerSecond = 2.0 * min(1.8, max(0.7, scrollSpeed)), lookSeconds = 5.4 / unitsPerSecond
    let projection = DrumxProjection(centerX: Double(center), nearWidth: Double(nearWidth),
      topY: Double(top), strikeY: Double(nowY), previewBeats: 5.4, farScale: 0.28)
    let hostNow = DrumxIO.hostNowSeconds()
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    DrumxSongInk.draw("\(DrumxSongInk.duration(max(0, time)))  /  \(DrumxSongInk.duration(duration))",
      in: NSRect(x: left, y: 11, width: 160, height: 25), size: 13, color: DrumxSongInk.muted)
    let metrics = snapshot.total
    let accuracy = metrics.has_accuracy != 0 ? String(format: "%.0f%% hit", metrics.hit_rate_percent) : "Ready to play"
    DrumxSongInk.draw("\(accuracy)    ·    \(metrics.streak) streak    ·    \(metrics.missed) missed",
      in: NSRect(x: w - 470, y: 11, width: 425, height: 25), size: 14, weight: .medium, align: .right)
    DrumxSongInk.paper.withAlphaComponent(0.08).setFill()
    NSBezierPath(roundedRect: NSRect(x: left, y: 41, width: railW, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    DrumxSongInk.lime.setFill()
    NSBezierPath(roundedRect: NSRect(x: left, y: 41, width: railW * min(1, max(0, time / max(1, duration))), height: 3), xRadius: 1.5, yRadius: 1.5).fill()

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
    // Bar and pulse positions come from the song's tempo and meter map. They
    // use the same captured-time-to-distance transform as the note centers.
    var gridLow = 0, gridHigh = gridLines.count
    while gridLow < gridHigh {
      let middle = (gridLow + gridHigh) / 2
      if gridLines[middle].time < time { gridLow = middle + 1 } else { gridHigh = middle }
    }
    for grid in gridLines.dropFirst(gridLow) {
      if grid.time > time + lookSeconds { break }
      let distance = (grid.time - time) * unitsPerSecond
      let alpha = grid.kind == .bar ? 0.30 : grid.kind == .beat ? 0.16 : 0.075
      line(projection.project(lateral: -0.5, beatDistance: distance),
        projection.project(lateral: 0.5, beatDistance: distance),
        color: DrumxSongInk.paper.withAlphaComponent(alpha * projection.farVisibility(at: distance)),
        width: grid.kind == .bar ? 1.1 : 0.6)
    }
    roadLine.withAlphaComponent(0.48).setFill()
    polygon([DrumxProjectedPoint(x: Double(center) - Double(nearWidth) / 2, y: Double(nowY)),
      DrumxProjectedPoint(x: Double(center) + Double(nearWidth) / 2, y: Double(nowY)),
      DrumxProjectedPoint(x: Double(center) + Double(nearWidth) / 2 - 8, y: Double(nowY) + 7),
      DrumxProjectedPoint(x: Double(center) - Double(nearWidth) / 2 + 8, y: Double(nowY) + 7)]).fill()
    let strikeY = CGFloat(DrumxSongGeometry.center(pad: 2, distance: 0, road: projection).y)
    line(projection.project(lateral: -0.505, beatDistance: 0),
      projection.project(lateral: 0.505, beatDistance: 0),
      color: DrumxSongInk.paper.withAlphaComponent(0.65), width: 1)
    DrumxSongInk.draw("NOW", in: NSRect(x: center - nearWidth / 2 - 47, y: strikeY - 7, width: 39, height: 18),
      size: 10, color: DrumxSongInk.muted, weight: .medium, align: .center)

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
        material(pad: item.note.pad, projection: projection, distance: item.distance, alpha: alpha)

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

    sideFeedback(roadWidth: nearWidth, nowY: nowY)

    // Preserve the established physical-kit silhouettes beneath NOW. These
    // static references are not separate timing destinations.
    for (index, pad) in DrumxSongInk.handPads.enumerated() {
      let point = projection.project(lateral: projection.laneCenter(index), beatDistance: 0)
      let x = CGFloat(point.x), cymbal = [0, 6, 7].contains(pad), color = DrumxSongInk.colors[pad]
      let cy = nowY + (cymbal ? 29 : 43), radius = min(29, nearWidth / 7 * 0.29)
      let ry: CGFloat = cymbal ? 4.5 : 10
      line(DrumxProjectedPoint(x: Double(x), y: Double(nowY) + 9),
        DrumxProjectedPoint(x: Double(x), y: Double(cy) - Double(ry) - 3),
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
      let box = NSRect(x: w * 0.17, y: max(95, nowY * 0.32), width: w * 0.66, height: completed ? 254 : 141)
      DrumxSongInk.background.withAlphaComponent(0.94).setFill()
      NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16).fill()
      DrumxSongInk.draw(stateText, in: NSRect(x: box.minX + 15, y: box.minY + 27, width: box.width - 30, height: 48),
        size: 32, color: DrumxSongInk.lime, weight: .semibold, align: .center)
      DrumxSongInk.draw(detailText, in: NSRect(x: box.minX + 16, y: box.minY + 85, width: box.width - 32, height: 28),
        size: 13, color: DrumxSongInk.muted, align: .center)
      if completed {
        let earnedStars = score?.stars ?? 0
        DrumxSongInk.draw("\((score?.points ?? 0).formatted()) points    "
          + String(repeating: "★", count: earnedStars) + String(repeating: "☆", count: 5 - earnedStars),
          in: NSRect(x: box.minX + 16, y: box.minY + 122, width: box.width - 32, height: 30),
          size: 23, color: DrumxSongInk.lime, weight: .semibold, align: .center)
        DrumxSongInk.draw(recordText, in: NSRect(x: box.minX + 16, y: box.minY + 163, width: box.width - 32, height: 24),
          size: 13, color: DrumxSongInk.paper, align: .center)
        DrumxSongInk.draw("Enter to play again   ·   Escape to choose a song",
          in: NSRect(x: box.minX + 16, y: box.minY + 207, width: box.width - 32, height: 20),
          size: 11, color: DrumxSongInk.muted, align: .center)
      }
    }
  }
}
