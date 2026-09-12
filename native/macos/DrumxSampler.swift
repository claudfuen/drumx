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

struct DrumxDemoHit: Equatable {
    let pad: Int
    let beat: Double
    let velocity: Int
}

/// A finite, sample-accurate arrangement prepared before playback. Rendering it
/// does not consume the live sampler's round-robin counters or emit input events.
struct DrumxDemoAudio {
    let buffer: AVAudioPCMBuffer
    let hits: [DrumxDemoHit]
    var durationSeconds: Double { Double(buffer.frameLength) / buffer.format.sampleRate }

    static func pattern(bars: Int) throws -> [DrumxDemoHit] {
        guard bars == 1 || bars == 4 else {
            throw DrumxSamplerError.invalid("The groove demo supports one or four bars.")
        }
        var hits: [DrumxDemoHit] = []
        for bar in 0..<bars {
            let start = Double(bar * 4)
            for eighth in 0..<8 {
                hits.append(DrumxDemoHit(pad: 0, beat: start + Double(eighth) / 2,
                                        velocity: eighth.isMultiple(of: 2) ? 90 : 78))
            }
            for beat in [1, 3] { hits.append(DrumxDemoHit(pad: 1, beat: start + Double(beat), velocity: 108)) }
            for beat in [0, 2] { hits.append(DrumxDemoHit(pad: 2, beat: start + Double(beat), velocity: 112)) }
        }
        return hits.sorted { $0.beat == $1.beat ? $0.pad < $1.pad : $0.beat < $1.beat }
    }

    static func render(bank: DrumxSampleBank, bpm: Double, bars: Int) throws -> DrumxDemoAudio {
        guard bpm.isFinite, bpm >= 20, bpm <= 400 else {
            throw DrumxSamplerError.invalid("The groove demo needs a tempo between 20 and 400 BPM.")
        }
        let hits = try pattern(bars: bars)
        let framesPerBeat = bank.format.sampleRate * 60 / bpm
        var selection = bank.selector
        var clips: [(Int, Int)] = []
        var totalFrames = Int(ceil(Double(bars * 4) * framesPerBeat))
        for hit in hits {
            guard let index = selection.select(pad: hit.pad, velocity: hit.velocity) else {
                throw DrumxSamplerError.invalid("The demo requires hi-hat, snare and kick samples.")
            }
            let start = Int((hit.beat * framesPerBeat).rounded())
            clips.append((index, start))
            totalFrames = max(totalFrames, start + Int(bank.buffers[index].frameLength))
        }
        guard let mixed = AVAudioPCMBuffer(pcmFormat: bank.format,
                                           frameCapacity: AVAudioFrameCount(totalFrames)),
              let output = mixed.floatChannelData else {
            throw DrumxSamplerError.invalid("Could not prepare the groove demo.")
        }
        mixed.frameLength = AVAudioFrameCount(totalFrames)
        for channel in 0..<Int(bank.format.channelCount) {
            output[channel].update(repeating: 0, count: totalFrames)
        }
        for (index, start) in clips {
            let sample = bank.buffers[index]
            guard let input = sample.floatChannelData else { continue }
            for channel in 0..<Int(bank.format.channelCount) {
                for frame in 0..<Int(sample.frameLength) {
                    output[channel][start + frame] += input[channel][frame]
                }
            }
        }
        // Preserve the mix's relative dynamics. Apply global headroom only when
        // overlapping samples would exceed full scale; never normalize each hit.
        var peak: Float = 0
        for channel in 0..<Int(bank.format.channelCount) {
            for frame in 0..<totalFrames { peak = max(peak, abs(output[channel][frame])) }
        }
        if peak > 0.98 {
            let gain: Float = 0.98 / peak
            for channel in 0..<Int(bank.format.channelCount) {
                for frame in 0..<totalFrames { output[channel][frame] *= gain }
            }
        }
        return DrumxDemoAudio(buffer: mixed, hits: hits)
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
    let demoScheduled: Bool
    let demoDurationSeconds: Double
    let demoFirstBeatHostTime: Double?
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
    var onAudioInterrupted: ((String) -> Void)?
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
    private var demoPlayer: AVAudioPlayerNode?
    private var demoBuffer: AVAudioPCMBuffer?
    private var demoGeneration: UInt64 = 0
    private var demoStartHostTime: Double?
    private var demoLength = 0.0
    private var demoStatus = "Groove demo stopped"

    var demoDurationSeconds: Double { queue.sync { demoLength } }
    var demoStatusDescription: String { queue.sync { demoStatus } }

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
            let demonstration = AVAudioPlayerNode()
            newEngine.attach(demonstration)
            newEngine.connect(demonstration, to: newEngine.mainMixerNode, format: newBank.format)
            demoPlayer = demonstration
            newEngine.mainMixerNode.outputVolume = volume * 0.65
            newEngine.prepare()
            engine = newEngine
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: newEngine, queue: nil
            ) { [weak self, weak newEngine] _ in
                self?.queue.async { [weak self, weak newEngine] in
                    guard let self, let newEngine, self.engine === newEngine else { return }
                    self.enabled = false
                    self.stopDemoOnQueue()
                    self.silenceVoices()
                    newEngine.stop()
                    let reason = "Audio device changed. Restart playback."
                    self.report(reason)
                    DispatchQueue.main.async { [weak self] in self?.onAudioInterrupted?(reason) }
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

    /// firstBeatHostTime is the estimated presentation time in the same native
    /// host-seconds domain as the click. The entire phrase is scheduled once.
    /// Monitoring/learn state controls live inputs only, not this explicit demo.
    @discardableResult
    func startDemo(bpm: Double, firstBeatHostTime: Double, bars: Int) -> Bool {
        queue.sync {
            stopDemoOnQueue()
            guard firstBeatHostTime.isFinite, firstBeatHostTime > DrumxIO.hostNowSeconds(),
                  let bank, let engine, let player = demoPlayer else {
                demoStatus = "Load drum samples and choose a future demo start time."
                return false
            }
            do {
                let audio = try DrumxDemoAudio.render(bank: bank, bpm: bpm, bars: bars)
                if !engine.isRunning { try engine.start() }
                let latency = max(0, player.outputPresentationLatency)
                let renderStart = firstBeatHostTime - latency
                guard renderStart > DrumxIO.hostNowSeconds() + 0.020 else {
                    demoStatus = "The demo missed its start time. Try again with a longer count-in."
                    return false
                }
                demoBuffer = audio.buffer
                demoLength = audio.durationSeconds
                demoStartHostTime = firstBeatHostTime
                let generation = demoGeneration
                player.scheduleBuffer(audio.buffer, at: nil, options: [], completionHandler: nil)
                player.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: renderStart)))
                demoStatus = "Groove demo scheduled"
                // Cleanup is not the musical clock. The PCM buffer ends by itself
                // even if this serial queue is busy; no per-note timer is involved.
                let remaining = firstBeatHostTime + demoLength - DrumxIO.hostNowSeconds() + 0.020
                queue.asyncAfter(deadline: .now() + max(0, remaining)) { [weak self] in
                    guard let self, self.demoGeneration == generation else { return }
                    self.stopDemoOnQueue()
                }
                return true
            } catch {
                demoStatus = "Groove demo unavailable: \(error.localizedDescription)"
                return false
            }
        }
    }

    /// Synchronous cancellation also invalidates cleanup from any earlier demo.
    func stopDemo() { queue.sync { stopDemoOnQueue() } }

    private func stopDemoOnQueue() {
        demoGeneration &+= 1
        demoPlayer?.stop()
        demoBuffer = nil
        demoStartHostTime = nil
        demoStatus = "Groove demo stopped"
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
                lastSampleFile: lastSampleFile, demoScheduled: demoStartHostTime != nil,
                demoDurationSeconds: demoLength, demoFirstBeatHostTime: demoStartHostTime)
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
        stopDemoOnQueue()
        demoPlayer = nil
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
