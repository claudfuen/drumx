import Foundation
import AVFoundation
import Synchronization

struct DrumxSampleEntry: Decodable, Equatable {
    let pad: Int
    let velocityMin: Int
    let velocityMax: Int
    let roundRobin: Int
    /// Relative to the Resources directory, one level above the manifest folder.
    let file: String
}

struct DrumxSampleLayer: Equatable {
    let pad: Int
    let velocityMin: Int
    let velocityMax: Int
    let sampleIndices: [Int]
}

enum DrumxSamplerError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let detail): return detail }
    }
}

/// Validated metadata and deterministic per-layer alternation, independent of audio.
struct DrumxSampleSelector {
    let entries: [DrumxSampleEntry]
    let layers: [DrumxSampleLayer]
    private var nextAlternate: [Int]

    init(entries: [DrumxSampleEntry]) throws {
        guard !entries.isEmpty, entries.count <= 1024 else {
            throw DrumxSamplerError.invalid("Sample manifest is empty or too large.")
        }
        for entry in entries {
            guard (0..<128).contains(entry.pad), (1...127).contains(entry.velocityMin),
                  (entry.velocityMin...127).contains(entry.velocityMax), entry.roundRobin >= 0,
                  !entry.file.isEmpty, !entry.file.hasPrefix("/"),
                  !entry.file.split(separator: "/").contains("..") else {
                throw DrumxSamplerError.invalid("Invalid sample entry: \(entry.file)")
            }
        }
        var collected: [DrumxSampleLayer] = []
        for pad in Set(entries.map(\.pad)).sorted() {
            var previousMaximum = 0
            let minimums = Set(entries.filter { $0.pad == pad }.map(\.velocityMin)).sorted()
            for minimum in minimums {
                let indices = entries.indices.filter {
                    entries[$0].pad == pad && entries[$0].velocityMin == minimum
                }.sorted { entries[$0].roundRobin < entries[$1].roundRobin }
                let maximum = entries[indices[0]].velocityMax
                guard minimum == previousMaximum + 1,
                      indices.allSatisfy({ entries[$0].velocityMax == maximum }),
                      Set(indices.map { entries[$0].roundRobin }).count == indices.count,
                      Set(indices.map { entries[$0].file }).count == indices.count else {
                    throw DrumxSamplerError.invalid("Velocity layers overlap, have gaps, or repeat an alternate for pad \(pad).")
                }
                collected.append(DrumxSampleLayer(pad: pad, velocityMin: minimum,
                    velocityMax: maximum, sampleIndices: indices))
                previousMaximum = maximum
            }
            guard previousMaximum == 127 else {
                throw DrumxSamplerError.invalid("Velocity layers must cover 1...127 for pad \(pad).")
            }
        }
        self.entries = entries
        layers = collected
        nextAlternate = Array(repeating: 0, count: collected.count)
    }

    mutating func select(pad: Int, velocity: Int) -> Int? {
        guard (1...127).contains(velocity), let layerIndex = layers.firstIndex(where: {
            $0.pad == pad && velocity >= $0.velocityMin && velocity <= $0.velocityMax
        }) else { return nil }
        let layer = layers[layerIndex]
        let index = layer.sampleIndices[nextAlternate[layerIndex]]
        nextAlternate[layerIndex] = (nextAlternate[layerIndex] + 1) % layer.sampleIndices.count
        // Velocity selects a real recorded dynamic layer. Preserve its original
        // amplitude; per-hit player volume changes can synchronize with rendering.
        return index
    }
}

struct DrumxSampleBank {
    let selector: DrumxSampleSelector
    let buffers: [AVAudioPCMBuffer]
    let format: AVAudioFormat

    /// Disk access, FLAC decoding, and PCM conversion happen only during loading.
    static func load(manifestURL: URL, sampleRate: Double) throws -> DrumxSampleBank {
        guard sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 192_000,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw DrumxSamplerError.invalid("Unsupported sampler output format.")
        }
        let entries = try JSONDecoder().decode([DrumxSampleEntry].self, from: Data(contentsOf: manifestURL))
        let selector = try DrumxSampleSelector(entries: entries)
        let resourceRoot = manifestURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        var buffers: [AVAudioPCMBuffer] = []
        var totalFrames: Int64 = 0
        for entry in entries {
            let url = resourceRoot.appendingPathComponent(entry.file).standardizedFileURL
            guard url.path.hasPrefix(resourceRoot.path + "/") else {
                throw DrumxSamplerError.invalid("Sample path leaves the asset directory.")
            }
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0, file.length <= 30 * Int64(file.processingFormat.sampleRate),
                  file.processingFormat.channelCount > 0, file.processingFormat.channelCount <= 2,
                  let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                               frameCapacity: AVAudioFrameCount(file.length)) else {
                throw DrumxSamplerError.invalid("Invalid or oversized sample: \(entry.file)")
            }
            try file.read(into: source)
            let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * sampleRate
                / source.format.sampleRate) + 256)
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
                  let converter = AVAudioConverter(from: source.format, to: format) else {
                throw DrumxSamplerError.invalid("Cannot convert sample: \(entry.file)")
            }
            var supplied = false
            var conversionError: NSError?
            let result = converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied { status.pointee = .endOfStream; return nil }
                supplied = true
                status.pointee = .haveData
                return source
            }
            guard result != .error, conversionError == nil, converted.frameLength > 0 else {
                throw conversionError ?? DrumxSamplerError.invalid("Could not decode \(entry.file)")
            }
            totalFrames += Int64(converted.frameLength)
            guard totalFrames <= 32_000_000 else {
                throw DrumxSamplerError.invalid("Sample bank exceeds the in-memory size limit.")
            }
            buffers.append(converted)
        }
        return DrumxSampleBank(selector: selector, buffers: buffers, format: format)
    }
}

struct DrumxSamplerDiagnostics {
    let loadedSamples: Int
    let velocityLayers: Int
    let monitoring: Bool
    let scheduledHits: UInt64
    let staleHitsDropped: UInt64
    let queuedHitsDropped: Int
    let voicesStolen: UInt64
    let activeVoices: Int
    let maximumVoices: Int
    let lastSampleFile: String?
}

/// A bounded voice pool controlled on one dedicated serial queue. MIDI scheduling
/// never waits for the main/UI thread. AVAudioPlayerNode performs audio rendering;
/// this class installs no render or completion callbacks and does no per-hit I/O.
/// Queue scheduling and AVAudioPlayerNode are not a custom hard-realtime engine.
/// Physical MIDI-to-speaker latency has not been measured.
final class DrumxSampler {
    static let voiceLimit = 32
    static let queuedHitLimit = 128
    static let maximumTriggerAge = 0.100

    /// Assigned/read on main; delivery always marshals to main.
    var onStatusChanged: ((String) -> Void)?
    private let queue = DispatchQueue(label: "org.drumx.sampler", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let pendingHits = Atomic<Int>(0)
    private let overflowHits = Atomic<Int>(0)
    // Everything below is owned by queue.
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private var bank: DrumxSampleBank?
    private var selector: DrumxSampleSelector?
    private var players: [AVAudioPlayerNode] = []
    private var playerStarted = Array(repeating: false, count: voiceLimit)
    private var voiceEnds = Array(repeating: 0.0, count: voiceLimit)
    private var nextVoice = 0
    private var enabled = false
    private var volume: Float = 0.7
    private var noteToPad = Array(repeating: -1, count: 128)
    private var midiGeneration: UInt64 = 0
    private var midiLearnActive = false
    private var inputCutoff = 0.0
    private var scheduledHits: UInt64 = 0
    private var staleHits: UInt64 = 0
    private var stolenVoices: UInt64 = 0
    private var lastSampleFile: String?

    init() { queue.setSpecific(key: queueKey, value: true) }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) == true { tearDownEngine() }
        else { queue.sync { tearDownEngine() } }
    }

    func load(manifestURL: URL) throws {
        try queue.sync {
            let newEngine = AVAudioEngine()
            let outputRate = newEngine.outputNode.outputFormat(forBus: 0).sampleRate
            let newBank = try DrumxSampleBank.load(manifestURL: manifestURL, sampleRate: outputRate)
            tearDownEngine()
            enabled = false
            bank = newBank
            selector = newBank.selector
            for _ in 0..<Self.voiceLimit {
                let player = AVAudioPlayerNode()
                newEngine.attach(player)
                newEngine.connect(player, to: newEngine.mainMixerNode, format: newBank.format)
                players.append(player)
            }
            newEngine.mainMixerNode.outputVolume = volume * 0.65
            newEngine.prepare()
            engine = newEngine
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: newEngine, queue: nil
            ) { [weak self, weak newEngine] _ in
                self?.queue.async { [weak self, weak newEngine] in
                    guard let self, let newEngine, self.engine === newEngine else { return }
                    self.enabled = false
                    self.silenceVoices()
                    newEngine.stop()
                    self.report("Drum sound paused after an audio device change. Toggle it on to restart.")
                }
            }
            report("Drum samples loaded · \(newBank.buffers.count) recordings")
        }
    }

    func setEnabled(_ requested: Bool) {
        let cutoff = DrumxIO.hostNowSeconds()
        queue.async { [weak self] in
            guard let self else { return }
            self.inputCutoff = cutoff
            guard requested else {
                self.enabled = false
                self.silenceVoices()
                self.report("Drum sound off")
                return
            }
            guard let engine = self.engine, self.bank != nil else {
                self.report("Drum samples are not loaded.")
                return
            }
            do {
                if !engine.isRunning { try engine.start() }
                for index in self.players.indices where !self.playerStarted[index] {
                    self.players[index].play()
                    self.playerStarted[index] = true
                }
                self.enabled = true
                self.report("Drum sound ready · 4 velocity layers · 2 alternates")
            } catch {
                self.enabled = false
                self.report("Drum sound could not start: \(error.localizedDescription)")
            }
        }
    }

    func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.volume = min(1, max(0, value))
            self.engine?.mainMixerNode.outputVolume = self.volume * 0.65
        }
    }

    func setMapping(_ notesByPad: [[Int]]) {
        var mapping = Array(repeating: -1, count: 128)
        for (pad, notes) in notesByPad.prefix(128).enumerated() {
            for note in notes where (0..<128).contains(note) && mapping[note] == -1 {
                mapping[note] = pad
            }
        }
        let snapshot = mapping
        let cutoff = DrumxIO.hostNowSeconds()
        queue.async { [weak self] in
            self?.noteToPad = snapshot
            self?.inputCutoff = cutoff
        }
    }

    func setLearnActive(_ active: Bool) {
        let cutoff = DrumxIO.hostNowSeconds()
        queue.async { [weak self] in
            self?.midiLearnActive = active
            self?.inputCutoff = cutoff
            if active, let self { self.silenceVoices(restart: self.enabled) }
        }
    }

    func setMIDIGeneration(_ generation: UInt64) {
        let cutoff = DrumxIO.hostNowSeconds()
        queue.async { [weak self] in
            self?.midiGeneration = generation
            self?.inputCutoff = cutoff
            if let self { self.silenceVoices(restart: self.enabled) }
        }
    }

    /// Safe on CoreMIDI's receive thread. The small bounded queue hop bypasses UI.
    func receiveMIDI(note: Int, velocity: Int, generation: UInt64,
                     receivedAt: Double = DrumxIO.hostNowSeconds()) {
        enqueueHit(pad: nil, note: note, velocity: velocity, generation: generation, arrival: receivedAt)
    }

    /// Keyboard and other explicit pad triggers use the same sample selector.
    func playPad(pad: Int, velocity: Int) {
        enqueueHit(pad: pad, note: nil, velocity: velocity, generation: nil, arrival: DrumxIO.hostNowSeconds())
    }

    private func enqueueHit(pad: Int?, note: Int?, velocity: Int, generation: UInt64?, arrival: Double) {
        guard (1...127).contains(velocity), arrival.isFinite else { return }
        let previous = pendingHits.wrappingAdd(1, ordering: .relaxed).oldValue
        guard previous < Self.queuedHitLimit else {
            _ = pendingHits.wrappingSubtract(1, ordering: .relaxed)
            _ = overflowHits.wrappingAdd(1, ordering: .relaxed)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            defer { _ = self.pendingHits.wrappingSubtract(1, ordering: .relaxed) }
            let now = DrumxIO.hostNowSeconds()
            guard now - arrival <= Self.maximumTriggerAge else {
                self.staleHits &+= 1
                return
            }
            guard self.enabled, !self.midiLearnActive, arrival >= self.inputCutoff else { return }
            let resolvedPad: Int
            if let note, let generation {
                guard generation == self.midiGeneration, (0..<128).contains(note) else { return }
                resolvedPad = self.noteToPad[note]
            } else if let pad { resolvedPad = pad }
            else { return }
            self.schedule(pad: resolvedPad, velocity: velocity, now: now)
        }
    }

    private func schedule(pad: Int, velocity: Int, now: Double) {
        guard let bank, engine != nil,
              let selected = selector?.select(pad: pad, velocity: velocity) else { return }
        var chosen = -1
        for offset in 0..<players.count {
            let index = (nextVoice + offset) % players.count
            if voiceEnds[index] <= now { chosen = index; break }
        }
        if chosen < 0 {
            chosen = voiceEnds.indices.min(by: { voiceEnds[$0] < voiceEnds[$1] }) ?? 0
            stolenVoices &+= 1
        }
        let player = players[chosen]
        let buffer = bank.buffers[selected]
        // Free voices have finished their previous buffer. Interrupt only when
        // stealing a voice, avoiding unnecessary synchronization with rendering.
        let options: AVAudioPlayerNodeBufferOptions = voiceEnds[chosen] > now ? .interrupts : []
        player.scheduleBuffer(buffer, at: nil, options: options, completionHandler: nil)
        if !playerStarted[chosen] { player.play(); playerStarted[chosen] = true }
        voiceEnds[chosen] = now + Double(buffer.frameLength) / bank.format.sampleRate + 0.010
        nextVoice = (chosen + 1) % players.count
        scheduledHits &+= 1
        lastSampleFile = bank.selector.entries[selected].file
    }

    func diagnostics() -> DrumxSamplerDiagnostics {
        queue.sync {
            let now = DrumxIO.hostNowSeconds()
            return DrumxSamplerDiagnostics(loadedSamples: bank?.buffers.count ?? 0,
                velocityLayers: bank?.selector.layers.count ?? 0, monitoring: enabled,
                scheduledHits: scheduledHits, staleHitsDropped: staleHits,
                queuedHitsDropped: overflowHits.load(ordering: .relaxed), voicesStolen: stolenVoices,
                activeVoices: voiceEnds.filter { $0 > now }.count, maximumVoices: Self.voiceLimit,
                lastSampleFile: lastSampleFile)
        }
    }

    private func silenceVoices(restart: Bool = false) {
        players.forEach { $0.stop() }
        playerStarted = Array(repeating: false, count: Self.voiceLimit)
        voiceEnds = Array(repeating: 0, count: Self.voiceLimit)
        // Empty playing nodes produce silence. Keep their timelines warm across
        // learn/reconnect controls so the next chord does not start cold voices.
        if restart {
            for index in players.indices {
                players[index].play()
                playerStarted[index] = true
            }
        }
    }

    private func tearDownEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        silenceVoices()
        engine?.stop()
        engine = nil
        players = []
        nextVoice = 0
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatusChanged?(message) }
    }
}
